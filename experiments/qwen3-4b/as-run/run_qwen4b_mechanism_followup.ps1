param(
    [ValidateSet(
        'format_system_reasoning_off',
        'format_system_reasoning_capped_256'
    )]
    [string] $Condition = 'format_system_reasoning_off'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. "$PSScriptRoot\screen_helpers.ps1"

$conditionSpec = Get-MechanismConditionSpec -Condition $Condition

$root = 'E:\Temp\spar-odd-number-20260823\local-gpu'
$runtime = Join-Path $root 'runtime'
$exe = Join-Path $runtime 'llama-cli.exe'
$model = Join-Path $root 'models\Qwen3-4B-Q4_K_M.gguf'
$promptDir = Join-Path $root 'prompts'
$systemPromptPath = Join-Path $promptDir 'format_only_system.txt'
$resultDir = Join-Path $root "results\$($conditionSpec.ResultSlug)"
$logDir = Join-Path $resultDir 'logs'
$schedulePath = Join-Path $resultDir 'schedule.json'
$resultPath = Join-Path $resultDir 'results.jsonl'
$summaryPath = Join-Path $resultDir 'summary.json'
$expectedModelHash = '7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5'
$randomizationSeed = 20260823
$maxTokens = $conditionSpec.MaxTokens
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

$cells = @(
    'higher_current',
    'higher_archived',
    'higher_transform_nplus1',
    'higher_reversed_conflict',
    'maximize_current'
)
$pairedSeeds = @(
    1018934058,
    1141160237,
    1297383343,
    98600829,
    1779782018,
    157955827
)
$schedule = @(
    New-PairedInterleavedSchedule `
        -Cells $cells `
        -Seeds $pairedSeeds `
        -RandomizationSeed $randomizationSeed `
        -TrialTag $conditionSpec.TrialTag
)

$requiredFiles = @($exe, $model, $systemPromptPath)
foreach ($cell in $cells) {
    $spec = Get-MechanismCellSpec -Cell $cell
    $requiredFiles += Join-Path $promptDir $spec.PromptFile
}
foreach ($required in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required file is missing: $required"
    }
}

$actualHash = (Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $expectedModelHash) {
    throw "Model hash mismatch: $actualHash"
}

if (Get-Process -Name 'llama-cli' -ErrorAction SilentlyContinue) {
    throw 'A llama-cli process is already running; refusing to overlap model loads.'
}

$os = Get-CimInstance Win32_OperatingSystem
$preflightFreeRamMiB = [math]::Round($os.FreePhysicalMemory / 1KB)
if ($preflightFreeRamMiB -lt 6144) {
    throw "Preflight failed: only $preflightFreeRamMiB MiB system RAM is free."
}

$gpuFreeRaw = & nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>$null
if ($LASTEXITCODE -ne 0 -or -not $gpuFreeRaw) {
    throw 'Preflight failed: nvidia-smi did not report free GPU memory.'
}
$preflightFreeGpuMiB = [int](($gpuFreeRaw | Select-Object -First 1).Trim())
if ($preflightFreeGpuMiB -lt 8192) {
    throw "Preflight failed: only $preflightFreeGpuMiB MiB GPU memory is free."
}

if (Test-Path -LiteralPath $resultPath) {
    throw "Results already exist; refusing to overwrite: $resultPath"
}
if (Test-Path -LiteralPath $summaryPath) {
    throw "Summary already exists; refusing to overwrite: $summaryPath"
}

New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$scheduleDocument = [ordered]@{
    randomization_seed = $randomizationSeed
    randomization_method = 'Six paired sampling-seed blocks; SHA-256 seeded block order and cell order within each balanced block'
    model = 'Qwen3-4B-GGUF-Q4_K_M'
    model_sha256 = $actualHash
    runtime = 'llama.cpp b10566'
    condition = $Condition
    reasoning_mode = $conditionSpec.ReasoningMode
    reasoning_budget = $conditionSpec.ReasoningBudget
    system_prompt = [System.IO.File]::ReadAllText($systemPromptPath).TrimEnd()
    temperature = 0.7
    top_p = 0.95
    max_tokens = $maxTokens
    cells = @($cells | ForEach-Object { Get-MechanismCellSpec -Cell $_ })
    paired_sampling_seeds = $pairedSeeds
    trials = $schedule
}
[System.IO.File]::WriteAllText(
    $schedulePath,
    ($scheduleDocument | ConvertTo-Json -Depth 7),
    $utf8NoBom
)

$records = [System.Collections.Generic.List[object]]::new()
$fatalReason = $null
$index = 0
foreach ($trial in $schedule) {
    $index += 1
    $promptPath = Join-Path $promptDir $trial.PromptFile
    $promptText = [System.IO.File]::ReadAllText($promptPath)
    $stdoutPath = Join-Path $logDir "$($trial.TrialId).stdout.txt"
    $stderrPath = Join-Path $logDir "$($trial.TrialId).stderr.txt"
    $loaderPath = Join-Path $logDir "$($trial.TrialId).loader.log"

    $arguments = @(
        '-m', $model,
        '-ngl', '37',
        '-sm', 'none',
        '--fit', 'off',
        '-c', '1024',
        '-n', [string]$maxTokens,
        '-b', '64',
        '-ub', '64',
        '-fa', 'on',
        '-ctk', 'q8_0',
        '-ctv', 'q8_0',
        '-cram', '0',
        '--single-turn',
        '--no-warmup',
        '--no-display-prompt',
        '--no-show-timings',
        '--simple-io',
        '-t', '1',
        '-tb', '1',
        '-s', [string]$trial.Seed,
        '--temp', '0.7',
        '--top-p', '0.95',
        '-sysf', $systemPromptPath,
        '-lv', '4',
        '--log-file', $loaderPath,
        '-f', $promptPath
    )
    if ($conditionSpec.ReasoningMode -eq 'on') {
        $arguments += @('--reasoning', 'on', '--reasoning-budget', [string]$conditionSpec.ReasoningBudget)
    }
    else {
        $arguments += @('--reasoning', 'off')
    }

    $memoryCounter = [System.Diagnostics.PerformanceCounter]::new('Memory', 'Available MBytes')
    [void]$memoryCounter.NextValue()
    $process = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $runtime `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath `
        -WindowStyle Hidden -PassThru
    $started = Get-Date
    $minimumFreeRamMiB = [double]$preflightFreeRamMiB
    $peakWorkingSetMiB = 0.0
    $peakTotalGpuUsedMiB = 0
    $lastGpuSample = [datetime]::MinValue
    $abortReason = $null

    try {
        while (-not $process.HasExited) {
            $freeRamMiB = [double]$memoryCounter.NextValue()
            if ($freeRamMiB -lt $minimumFreeRamMiB) { $minimumFreeRamMiB = $freeRamMiB }

            $process.Refresh()
            $workingSetMiB = $process.WorkingSet64 / 1MB
            if ($workingSetMiB -gt $peakWorkingSetMiB) { $peakWorkingSetMiB = $workingSetMiB }

            if (((Get-Date) - $lastGpuSample).TotalMilliseconds -ge 750) {
                $gpuUsedRaw = & nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>$null
                if ($LASTEXITCODE -eq 0 -and $gpuUsedRaw) {
                    $gpuUsedMiB = [int](($gpuUsedRaw | Select-Object -First 1).Trim())
                    if ($gpuUsedMiB -gt $peakTotalGpuUsedMiB) { $peakTotalGpuUsedMiB = $gpuUsedMiB }
                }
                $lastGpuSample = Get-Date
            }

            if ($freeRamMiB -lt 4096) { $abortReason = 'free RAM below 4096 MiB'; break }
            if ($workingSetMiB -gt 4096) { $abortReason = 'working set above 4096 MiB'; break }
            if (((Get-Date) - $started).TotalSeconds -gt 120) { $abortReason = '120 second timeout'; break }
            Start-Sleep -Milliseconds 100
        }

        if ($abortReason -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        $process.WaitForExit()
        $process.Refresh()
    }
    finally {
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        $memoryCounter.Dispose()
    }

    $elapsedSeconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 3)
    $loaderText = if (Test-Path -LiteralPath $loaderPath) {
        [System.IO.File]::ReadAllText($loaderPath)
    }
    else {
        ''
    }
    $fullGpuOffload = [regex]::IsMatch(
        $loaderText,
        '(?i)offloaded\s+37/37\s+layers\s+to\s+GPU'
    )
    $evaluationTokens = $null
    $evalMatch = [regex]::Match($loaderText, '(?m)\|\s+eval time\s+=.*?/\s+(\d+)\s+tokens')
    if ($evalMatch.Success) { $evaluationTokens = [int]$evalMatch.Groups[1].Value }

    $displayedResponse = $null
    $response = $null
    $reasoning = $null
    $reasoningCompleted = $null
    $score = $null
    $finishReason = $null
    $errorText = $null
    $trialFailure = $null

    if ($abortReason) {
        $trialFailure = $abortReason
    }
    elseif ($process.ExitCode -ne 0) {
        $stderrText = if (Test-Path -LiteralPath $stderrPath) {
            [System.IO.File]::ReadAllText($stderrPath)
        }
        else {
            ''
        }
        $trialFailure = "llama-cli exited with code $($process.ExitCode): $stderrText"
    }
    elseif (-not $fullGpuOffload) {
        $trialFailure = 'loader log did not verify full 37/37 layer GPU offload'
    }
    else {
        try {
            $rawOutput = [System.IO.File]::ReadAllText($stdoutPath)
            $displayedResponse = Get-LlamaResponse -RawOutput $rawOutput -PromptText $promptText
            $splitResponse = Split-LlamaReasoning -DisplayedResponse $displayedResponse
            $response = $splitResponse.Content
            $reasoning = $splitResponse.Reasoning
            $reasoningCompleted = $splitResponse.Completed
            if ($null -ne $response) {
                $score = Score-MechanismResponse -Response $response -Cell $trial.Cell
            }
            $finishReason = if ($evaluationTokens -ge $maxTokens) { 'length' } else { 'stop' }
        }
        catch {
            $trialFailure = "response parsing failed: $($_.Exception.Message)"
        }
    }
    if ($trialFailure) { $errorText = $trialFailure }

    $record = [ordered]@{
        schedule_position = $trial.Position
        interleave_block = $trial.InterleaveBlock
        trial_id = $trial.TrialId
        model = 'Qwen3-4B-GGUF-Q4_K_M'
        model_sha256 = $actualHash
        runtime = 'llama.cpp b10566'
        condition = $Condition
        reasoning_mode = $conditionSpec.ReasoningMode
        reasoning_budget = $conditionSpec.ReasoningBudget
        cell = $trial.Cell
        prompt_file = $trial.PromptFile
        prompt = $promptText.TrimEnd()
        requested_parity = $trial.RequestedParity
        reward_causal_prediction_parity = $trial.RewardCausalParity
        sampling_seed = $trial.Seed
        replicate = $trial.Replicate
        randomization_seed = $randomizationSeed
        temperature = 0.7
        top_p = 0.95
        max_tokens = $maxTokens
        displayed_response = $displayedResponse
        reasoning = $reasoning
        reasoning_completed = $reasoningCompleted
        response = $response
        parsed_integer = if ($score) { $score.ParsedInteger } else { $null }
        valid_integer = if ($score) { $score.ValidInteger } else { $false }
        output_parity = if ($score) { $score.OutputParity } else { $null }
        user_compliance = if ($score) { $score.UserCompliance } else { $false }
        reward_causal_prediction_match = if ($score) { $score.RewardCausalParityMatch } else { $null }
        finish_reason = $finishReason
        evaluation_tokens = $evaluationTokens
        full_gpu_offload_37_of_37 = $fullGpuOffload
        exit_code = $process.ExitCode
        aborted = [bool]$abortReason
        error = $errorText
        elapsed_seconds = $elapsedSeconds
        minimum_free_ram_mib = [math]::Round($minimumFreeRamMiB)
        peak_process_working_set_mib = [math]::Round($peakWorkingSetMiB)
        peak_total_gpu_used_mib = $peakTotalGpuUsedMiB
        collected_at_utc = [datetime]::UtcNow.ToString('o')
    }

    $recordObject = [pscustomobject]$record
    $records.Add($recordObject)
    [System.IO.File]::AppendAllText(
        $resultPath,
        (($recordObject | ConvertTo-Json -Depth 7 -Compress) + [Environment]::NewLine),
        $utf8NoBom
    )
    Write-Output ("[{0}/{1}] {2} seed={3} -> valid={4} parity={5} causal={6}" -f `
        $index, $schedule.Count, $trial.Cell, $trial.Seed, $recordObject.valid_integer, `
        $recordObject.output_parity, $recordObject.reward_causal_prediction_match)

    if ($trialFailure) {
        $fatalReason = "$($trial.TrialId): $trialFailure"
        break
    }
}

$postOs = Get-CimInstance Win32_OperatingSystem
$postFreeRamMiB = [math]::Round($postOs.FreePhysicalMemory / 1KB)
$postGpuUsedRaw = & nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>$null
$postGpuUsedMiB = if ($LASTEXITCODE -eq 0 -and $postGpuUsedRaw) {
    [int](($postGpuUsedRaw | Select-Object -First 1).Trim())
}
else {
    $null
}
$lingering = @(Get-Process -Name 'llama-cli' -ErrorAction SilentlyContinue)
if ($lingering.Count -gt 0 -and -not $fatalReason) {
    $fatalReason = "$($lingering.Count) llama-cli process(es) remained after the run"
}

$cellSummaries = [ordered]@{}
foreach ($cell in $cells) {
    $spec = Get-MechanismCellSpec -Cell $cell
    $cellRecords = @($records | Where-Object cell -eq $cell)
    $cellSummaries[$cell] = [ordered]@{
        requested_parity = $spec.RequestedParity
        reward_causal_prediction_parity = $spec.RewardCausalParity
        trials_collected = $cellRecords.Count
        valid_trials = @($cellRecords | Where-Object valid_integer).Count
        user_compliant_trials = @($cellRecords | Where-Object user_compliance).Count
        reward_causal_prediction_matches = @(
            $cellRecords | Where-Object { $_.reward_causal_prediction_match -eq $true }
        ).Count
        odd_valid_trials = @(
            $cellRecords | Where-Object { $_.valid_integer -and $_.output_parity -eq 'odd' }
        ).Count
        even_valid_trials = @(
            $cellRecords | Where-Object { $_.valid_integer -and $_.output_parity -eq 'even' }
        ).Count
    }
}

$summary = [ordered]@{
    status = if ($fatalReason) { 'aborted_or_failed' } else { 'completed' }
    fatal_error = $fatalReason
    model = 'Qwen3-4B-GGUF-Q4_K_M'
    model_sha256 = $actualHash
    condition = $Condition
    reasoning_mode = $conditionSpec.ReasoningMode
    reasoning_budget = $conditionSpec.ReasoningBudget
    randomization_seed = $randomizationSeed
    planned_trials = $schedule.Count
    trials_collected = $records.Count
    valid_trials = @($records | Where-Object valid_integer).Count
    full_gpu_offload_verified_trials = @($records | Where-Object full_gpu_offload_37_of_37).Count
    cell_summaries = $cellSummaries
    minimum_free_ram_mib = if ($records.Count -gt 0) {
        ($records | Measure-Object minimum_free_ram_mib -Minimum).Minimum
    }
    else { $null }
    maximum_process_working_set_mib = if ($records.Count -gt 0) {
        ($records | Measure-Object peak_process_working_set_mib -Maximum).Maximum
    }
    else { $null }
    maximum_total_gpu_used_mib = if ($records.Count -gt 0) {
        ($records | Measure-Object peak_total_gpu_used_mib -Maximum).Maximum
    }
    else { $null }
    preflight_free_ram_mib = $preflightFreeRamMiB
    preflight_free_gpu_mib = $preflightFreeGpuMiB
    postflight_free_ram_mib = $postFreeRamMiB
    postflight_total_gpu_used_mib = $postGpuUsedMiB
    lingering_llama_processes = $lingering.Count
}
[System.IO.File]::WriteAllText($summaryPath, ($summary | ConvertTo-Json -Depth 8), $utf8NoBom)
$summary | ConvertTo-Json -Depth 8

if ($fatalReason) {
    throw "Mechanism follow-up stopped: $fatalReason"
}
