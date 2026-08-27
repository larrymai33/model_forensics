param(
    [ValidateSet(
        'native_template_reasoning_off',
        'format_system_reasoning_off',
        'format_system_reasoning_capped_256'
    )]
    [string] $Condition = 'native_template_reasoning_off'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. "$PSScriptRoot\screen_helpers.ps1"

$root = 'E:\Temp\spar-odd-number-20260823\local-gpu'
$runtime = Join-Path $root 'runtime'
$exe = Join-Path $runtime 'llama-cli.exe'
$model = Join-Path $root 'models\Qwen3-4B-Q4_K_M.gguf'
$promptDir = Join-Path $root 'prompts'
$formatSystemPath = Join-Path $promptDir 'format_only_system.txt'
$conditionSlug = if ($Condition -eq 'format_system_reasoning_off') {
    'qwen3-4b-q4km-format-system-nothink-screen'
}
elseif ($Condition -eq 'format_system_reasoning_capped_256') {
    'qwen3-4b-q4km-format-system-think256-screen'
}
else {
    'qwen3-4b-q4km-nothink-screen'
}
$resultDir = Join-Path $root "results\$conditionSlug"
$logDir = Join-Path $resultDir 'logs'
$resultPath = Join-Path $resultDir 'results.jsonl'
$summaryPath = Join-Path $resultDir 'summary.json'
$expectedModelHash = '7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

$schedule = @(
    [pscustomobject]@{ TrialId = 'qwen3-4b__nothink__baseline_even__r02'; Cell = 'baseline_even'; Seed = 330750393 },
    [pscustomobject]@{ TrialId = 'qwen3-4b__nothink__exact_conflict__r04'; Cell = 'exact_conflict'; Seed = 1779782018 },
    [pscustomobject]@{ TrialId = 'qwen3-4b__nothink__exact_conflict__r05'; Cell = 'exact_conflict'; Seed = 157955827 },
    [pscustomobject]@{ TrialId = 'qwen3-4b__nothink__baseline_even__r01'; Cell = 'baseline_even'; Seed = 664903576 },
    [pscustomobject]@{ TrialId = 'qwen3-4b__nothink__exact_conflict__r00'; Cell = 'exact_conflict'; Seed = 1018934058 },
    [pscustomobject]@{ TrialId = 'qwen3-4b__nothink__exact_conflict__r02'; Cell = 'exact_conflict'; Seed = 1297383343 },
    [pscustomobject]@{ TrialId = 'qwen3-4b__nothink__exact_conflict__r03'; Cell = 'exact_conflict'; Seed = 98600829 },
    [pscustomobject]@{ TrialId = 'qwen3-4b__nothink__baseline_even__r00'; Cell = 'baseline_even'; Seed = 1343256690 },
    [pscustomobject]@{ TrialId = 'qwen3-4b__nothink__exact_conflict__r01'; Cell = 'exact_conflict'; Seed = 1141160237 }
)

$requiredFiles = @($exe, $model, (Join-Path $promptDir 'baseline_even.txt'), (Join-Path $promptDir 'exact_conflict.txt'))
if ($Condition -ne 'native_template_reasoning_off') { $requiredFiles += $formatSystemPath }
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
$preflightFreeGpuMiB = [int](($gpuFreeRaw | Select-Object -First 1).Trim())
if ($preflightFreeGpuMiB -lt 8192) {
    throw "Preflight failed: only $preflightFreeGpuMiB MiB GPU memory is free."
}

if (Test-Path -LiteralPath $resultPath) {
    throw "Results already exist; refusing to overwrite: $resultPath"
}
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
[System.IO.File]::WriteAllText(
    (Join-Path $resultDir 'schedule.json'),
    ($schedule | ConvertTo-Json -Depth 4),
    $utf8NoBom
)

$records = [System.Collections.Generic.List[object]]::new()
$index = 0
foreach ($trial in $schedule) {
    $index += 1
    $trialId = if ($Condition -eq 'format_system_reasoning_off') {
        $trial.TrialId -replace '__nothink__', '__format-system-nothink__'
    }
    elseif ($Condition -eq 'format_system_reasoning_capped_256') {
        $trial.TrialId -replace '__nothink__', '__format-system-think256__'
    }
    else {
        $trial.TrialId
    }
    $promptName = if ($trial.Cell -eq 'exact_conflict') { 'exact_conflict.txt' } else { 'baseline_even.txt' }
    $promptPath = Join-Path $promptDir $promptName
    $promptText = [System.IO.File]::ReadAllText($promptPath)
    $stdoutPath = Join-Path $logDir "$trialId.stdout.txt"
    $stderrPath = Join-Path $logDir "$trialId.stderr.txt"
    $loaderPath = Join-Path $logDir "$trialId.loader.log"

    $arguments = @(
        '-m', $model,
        '-ngl', 'all',
        '-sm', 'none',
        '--fit', 'off',
        '-c', '1024',
        '-n', '512',
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
        '-lv', '3',
        '--log-file', $loaderPath
    )
    if ($Condition -eq 'format_system_reasoning_capped_256') {
        $arguments += @('--reasoning', 'on', '--reasoning-budget', '256')
    }
    else {
        $arguments += @('--reasoning', 'off')
    }
    if ($Condition -ne 'native_template_reasoning_off') {
        $arguments += @('-sysf', $formatSystemPath)
    }
    $arguments += @('-f', $promptPath)

    $memoryCounter = [System.Diagnostics.PerformanceCounter]::new('Memory', 'Available MBytes')
    [void]$memoryCounter.NextValue()
    $process = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $runtime `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath `
        -WindowStyle Hidden -PassThru
    $started = Get-Date
    $minimumFreeRamMiB = [double]::PositiveInfinity
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
                $gpuUsedMiB = [int](($gpuUsedRaw | Select-Object -First 1).Trim())
                if ($gpuUsedMiB -gt $peakTotalGpuUsedMiB) { $peakTotalGpuUsedMiB = $gpuUsedMiB }
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
    }
    finally {
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        $memoryCounter.Dispose()
    }

    $elapsedSeconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 3)
    $displayedResponse = $null
    $response = $null
    $reasoning = $null
    $reasoningCompleted = $null
    $score = $null
    $evaluationTokens = $null
    $finishReason = $null
    $errorText = $null

    if (-not $abortReason -and $process.ExitCode -eq 0) {
        $rawOutput = [System.IO.File]::ReadAllText($stdoutPath)
        $displayedResponse = Get-LlamaResponse -RawOutput $rawOutput -PromptText $promptText
        $splitResponse = Split-LlamaReasoning -DisplayedResponse $displayedResponse
        $response = $splitResponse.Content
        $reasoning = $splitResponse.Reasoning
        $reasoningCompleted = $splitResponse.Completed
        if ($null -ne $response) {
            $rewardedParity = if ($trial.Cell -eq 'exact_conflict') { 'odd' } else { $null }
            $score = Score-OddNumberResponse -Response $response -RequestedParity 'even' -RewardedParity $rewardedParity
        }
        $loaderText = [System.IO.File]::ReadAllText($loaderPath)
        $evalMatch = [regex]::Match($loaderText, '(?m)\|\s+eval time\s+=.*?/\s+(\d+)\s+tokens')
        if ($evalMatch.Success) { $evaluationTokens = [int]$evalMatch.Groups[1].Value }
        $finishReason = if ($evaluationTokens -ge 512) { 'length' } else { 'stop' }
    }
    else {
        $errorText = if ($abortReason) { $abortReason } else { [System.IO.File]::ReadAllText($stderrPath) }
    }

    $record = [ordered]@{
        trial_id = $trialId
        model = 'Qwen3-4B-GGUF-Q4_K_M'
        model_sha256 = $actualHash
        runtime = 'llama.cpp b10566'
        condition = $Condition
        cell = $trial.Cell
        prompt = $promptText.TrimEnd()
        requested = 'even'
        rewarded = if ($trial.Cell -eq 'exact_conflict') { 'odd' } else { $null }
        sampling_seed = $trial.Seed
        temperature = 0.7
        top_p = 0.95
        max_tokens = 512
        displayed_response = $displayedResponse
        reasoning = $reasoning
        reasoning_completed = $reasoningCompleted
        response = $response
        parsed_integer = if ($score) { $score.ParsedInteger } else { $null }
        valid_integer = if ($score) { $score.ValidInteger } else { $false }
        output_parity = if ($score) { $score.OutputParity } else { $null }
        user_compliance = if ($score) { $score.UserCompliance } else { $false }
        reward_parity_match = if ($score) { $score.RewardParityMatch } else { $null }
        finish_reason = $finishReason
        evaluation_tokens = $evaluationTokens
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
        (($recordObject | ConvertTo-Json -Depth 6 -Compress) + [Environment]::NewLine),
        $utf8NoBom
    )
    Write-Output ("[{0}/{1}] {2} seed={3} -> valid={4} parity={5} finish={6}" -f `
        $index, $schedule.Count, $trial.Cell, $trial.Seed, $recordObject.valid_integer, `
        $recordObject.output_parity, $recordObject.finish_reason)

    if ($abortReason) {
        throw "Safety abort in ${trialId}: $abortReason"
    }
}

$postOs = Get-CimInstance Win32_OperatingSystem
$postFreeRamMiB = [math]::Round($postOs.FreePhysicalMemory / 1KB)
$postGpuUsedRaw = & nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>$null
$postGpuUsedMiB = [int](($postGpuUsedRaw | Select-Object -First 1).Trim())
$lingering = @(Get-Process -Name 'llama-cli' -ErrorAction SilentlyContinue)

$summary = [ordered]@{
    model = 'Qwen3-4B-GGUF-Q4_K_M'
    condition = $Condition
    trials = $records.Count
    valid_trials = @($records | Where-Object valid_integer).Count
    odd_valid_trials = @($records | Where-Object { $_.valid_integer -and $_.output_parity -eq 'odd' }).Count
    baseline_trials = @($records | Where-Object cell -eq 'baseline_even').Count
    baseline_valid = @($records | Where-Object { $_.cell -eq 'baseline_even' -and $_.valid_integer }).Count
    baseline_compliant = @($records | Where-Object { $_.cell -eq 'baseline_even' -and $_.user_compliance }).Count
    conflict_trials = @($records | Where-Object cell -eq 'exact_conflict').Count
    conflict_valid = @($records | Where-Object { $_.cell -eq 'exact_conflict' -and $_.valid_integer }).Count
    conflict_reward_matches = @($records | Where-Object { $_.cell -eq 'exact_conflict' -and $_.reward_parity_match -eq $true }).Count
    minimum_free_ram_mib = ($records | Measure-Object minimum_free_ram_mib -Minimum).Minimum
    maximum_process_working_set_mib = ($records | Measure-Object peak_process_working_set_mib -Maximum).Maximum
    maximum_total_gpu_used_mib = ($records | Measure-Object peak_total_gpu_used_mib -Maximum).Maximum
    preflight_free_ram_mib = $preflightFreeRamMiB
    preflight_free_gpu_mib = $preflightFreeGpuMiB
    postflight_free_ram_mib = $postFreeRamMiB
    postflight_total_gpu_used_mib = $postGpuUsedMiB
    lingering_llama_processes = $lingering.Count
}
[System.IO.File]::WriteAllText($summaryPath, ($summary | ConvertTo-Json -Depth 5), $utf8NoBom)
$summary | ConvertTo-Json -Depth 5
