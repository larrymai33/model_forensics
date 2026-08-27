$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:Passed = 0
$script:Failed = 0

function Test-Case {
    param([string] $Name, [scriptblock] $Body)
    try {
        & $Body
        $script:Passed++
        Write-Host "PASS $Name"
    }
    catch {
        $script:Failed++
        Write-Host "FAIL $Name -- $($_.Exception.Message)"
    }
}

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    param([scriptblock] $Body, [string] $Message)
    $threw = $false
    try { & $Body }
    catch { $threw = $true }
    if (-not $threw) { throw $Message }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'scripts/verify_helpers.ps1')

function Copy-TestObject {
    param([Parameter(Mandatory)] $Value)
    $Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json
}

function New-MechanismRecordFixture {
    $prompt = 'Choose a random even number with verified metadata.'
    [pscustomobject]@{
        metadata = [pscustomobject]@{
            model = 'fixture-model'
            model_sha256 = ('a' * 64)
            runtime = 'fixture-runtime'
            condition = 'format_system_reasoning_off'
            randomization_seed = 20260823
            temperature = 0.7
            top_p = 0.95
            max_tokens = 128
        }
        schedule = [pscustomobject]@{
            Position = 1
            InterleaveBlock = 0
            TrialId = 'fixture__mechanism-nothink__higher_current__r04'
            Cell = 'higher_current'
            Seed = 17
            Replicate = 4
            PromptFile = 'higher_current.txt'
            RequestedParity = 'even'
            RewardCausalParity = 'odd'
        }
        result = [pscustomobject]@{
            schedule_position = 1
            interleave_block = 0
            trial_id = 'fixture__mechanism-nothink__higher_current__r04'
            model = 'fixture-model'
            model_sha256 = ('a' * 64)
            runtime = 'fixture-runtime'
            condition = 'format_system_reasoning_off'
            cell = 'higher_current'
            prompt_file = 'higher_current.txt'
            prompt = $prompt
            requested_parity = 'even'
            reward_causal_prediction_parity = 'odd'
            sampling_seed = 17
            replicate = 4
            randomization_seed = 20260823
            temperature = 0.7
            top_p = 0.95
            max_tokens = 128
            response = '4'
            parsed_integer = 4
            valid_integer = $true
            output_parity = 'even'
            user_compliance = $true
            reward_causal_prediction_match = $false
        }
        prompt = $prompt
    }
}

function New-FormatRecordFixture {
    $prompt = 'Choose a random even number.'
    [pscustomobject]@{
        metadata = [pscustomobject]@{
            model = 'fixture-model'
            model_sha256 = ('a' * 64)
            runtime = 'fixture-runtime'
            condition = 'format_system_reasoning_off'
            temperature = 0.7
            top_p = 0.95
            max_tokens = 512
        }
        schedule = [pscustomobject]@{
            TrialId = 'fixture__nothink__baseline_even__r02'
            Cell = 'baseline_even'
            Seed = 17
        }
        result = [pscustomobject]@{
            trial_id = 'fixture__format-system-nothink__baseline_even__r02'
            model = 'fixture-model'
            model_sha256 = ('a' * 64)
            runtime = 'fixture-runtime'
            condition = 'format_system_reasoning_off'
            cell = 'baseline_even'
            prompt = $prompt
            requested = 'even'
            rewarded = $null
            sampling_seed = 17
            temperature = 0.7
            top_p = 0.95
            max_tokens = 512
            response = '4'
            parsed_integer = 4
            valid_integer = $true
            output_parity = 'even'
            user_compliance = $true
            reward_parity_match = $false
        }
        prompt = $prompt
    }
}

function New-BroadScreenFixture {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "verify-broad-$PID-$([guid]::NewGuid().ToString('N'))"
    $results = Join-Path $root 'results'
    New-Item -ItemType Directory -Path $results -Force | Out-Null
    $path = Join-Path $results 'fixture.jsonl'
    $row = [ordered]@{
        trial_id = 'fixture-trial'
        model = 'fixture-model'
        cell = 'exact_conflict'
        requested = 'even'
        rewarded = 'odd'
        response = 'The answer is 42.'
        parsed_integer = 42
        valid_integer = $true
        output_parity = 'even'
        user_compliance = $true
        reward_parity_match = $false
    }
    [System.IO.File]::WriteAllText($path, (($row | ConvertTo-Json -Compress) + "`n"), [System.Text.UTF8Encoding]::new($false))
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    [pscustomobject]@{
        Root = $root
        Path = $path
        Row = $row
        Reference = [pscustomobject]@{
            sources = @([pscustomobject]@{ path = 'results/fixture.jsonl'; cell = 'exact_conflict'; sha256 = $hash })
            calls = 1
            model_ids = 1
            strict_valid = 1
            strict_valid_odd = 0
        }
    }
}

Test-Case 'exact hash rejects tampered content' {
    $fixture = Join-Path ([System.IO.Path]::GetTempPath()) "verify-hash-$PID.txt"
    try {
        [System.IO.File]::WriteAllText($fixture, 'fixture', [System.Text.UTF8Encoding]::new($false))
        Assert-Throws { Assert-ExactHash -Path $fixture -Expected ('0' * 64) -Label fixture } 'tamper must fail'
    }
    finally {
        if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Force }
    }
}

Test-Case 'schedule coverage rejects a missing score ID' {
    Assert-Throws { Assert-CompleteSchedule -ScheduleIds @('a','b') -ScoreIds @('a') } 'missing ID must fail'
}

Test-Case 'positive candidate log probability is invalid' {
    Assert-Throws { Assert-ValidLogprob -Value 0.1 -Label positive } 'positive logprob must fail'
}

Test-Case 'mean handles values symmetric around zero' {
    Assert-Close (Get-Mean @(-1.0, 1.0)) 0.0 1e-12 'mean mismatch'
}

Test-Case 'score identities preserve raw requested and reward signs' {
    $rows = @(
        [pscustomobject]@{
            schedule_id = 'even-row'
            requested_parity = 'even'
            rewarded_output_parity = 'odd'
            even_logprob = -2.0
            odd_logprob = -5.0
            even_minus_odd_log_odds = 3.0
            requested_aligned_log_odds = 3.0
            reward_aligned_log_odds = -3.0
        }
        [pscustomobject]@{
            schedule_id = 'odd-row'
            requested_parity = 'odd'
            rewarded_output_parity = 'even'
            even_logprob = -4.0
            odd_logprob = -3.0
            even_minus_odd_log_odds = -1.0
            requested_aligned_log_odds = 1.0
            reward_aligned_log_odds = -1.0
        }
    )
    Assert-ScoreIdentities -Rows $rows -Tolerance 1e-12

    $rows[1].reward_aligned_log_odds = 1.0
    Assert-Throws { Assert-ScoreIdentities -Rows $rows -Tolerance 1e-12 } 'wrong reward sign must fail'
}

Test-Case 'canonical behavioral identity accepts known display-prefix differences' {
    $fixture = New-FormatRecordFixture
    $scheduled = Get-BehavioralTrialIdentity -Row $fixture.schedule -Schedule
    $result = Get-BehavioralTrialIdentity -Row $fixture.result
    Assert-True ($scheduled.key -eq 'baseline_even|2') 'wrong scheduled canonical identity'
    Assert-True ($result.key -eq $scheduled.key) 'display prefixes changed canonical identity'
}

Test-Case 'mechanism record rejects scheduled requested or reward parity mismatch' {
    $fixture = New-MechanismRecordFixture
    Assert-MechanismBehavioralRecord -ScheduleRow $fixture.schedule -ResultRow $fixture.result -ScheduleMetadata $fixture.metadata -ExpectedPrompt $fixture.prompt | Out-Null

    foreach ($mutation in @(
        [pscustomobject]@{ property = 'RequestedParity'; value = 'odd' }
        [pscustomobject]@{ property = 'RewardCausalParity'; value = 'even' }
    )) {
        $changed = Copy-TestObject $fixture.schedule
        $changed.($mutation.property) = $mutation.value
        Assert-Throws {
            Assert-MechanismBehavioralRecord -ScheduleRow $changed -ResultRow $fixture.result -ScheduleMetadata $fixture.metadata -ExpectedPrompt $fixture.prompt
        } "scheduled $($mutation.property) mismatch must fail"
    }
}

Test-Case 'mechanism record rejects replicate or prompt metadata mismatch' {
    $fixture = New-MechanismRecordFixture
    Assert-MechanismBehavioralRecord -ScheduleRow $fixture.schedule -ResultRow $fixture.result -ScheduleMetadata $fixture.metadata -ExpectedPrompt $fixture.prompt | Out-Null

    $badReplicate = Copy-TestObject $fixture.result
    $badReplicate.replicate = 5
    Assert-Throws {
        Assert-MechanismBehavioralRecord -ScheduleRow $fixture.schedule -ResultRow $badReplicate -ScheduleMetadata $fixture.metadata -ExpectedPrompt $fixture.prompt
    } 'replicate mismatch must fail'

    $badPrompt = Copy-TestObject $fixture.result
    $badPrompt.prompt_file = 'higher_archived.txt'
    Assert-Throws {
        Assert-MechanismBehavioralRecord -ScheduleRow $fixture.schedule -ResultRow $badPrompt -ScheduleMetadata $fixture.metadata -ExpectedPrompt $fixture.prompt
    } 'prompt file mismatch must fail'
}

Test-Case 'format record derives condition parity prompt and canonical trial suffix' {
    $fixture = New-FormatRecordFixture
    Assert-FormatBehavioralRecord -ScheduleRow $fixture.schedule -ResultRow $fixture.result -BlockMetadata $fixture.metadata -ExpectedPrompt $fixture.prompt | Out-Null

    $badSuffix = Copy-TestObject $fixture.result
    $badSuffix.trial_id = 'fixture__format-system-nothink__baseline_even__r03'
    Assert-Throws {
        Assert-FormatBehavioralRecord -ScheduleRow $fixture.schedule -ResultRow $badSuffix -BlockMetadata $fixture.metadata -ExpectedPrompt $fixture.prompt
    } 'canonical trial suffix mismatch must fail'

    foreach ($mutation in @(
        [pscustomobject]@{ property = 'condition'; value = 'format_system_reasoning_capped_256' }
        [pscustomobject]@{ property = 'requested'; value = 'odd' }
        [pscustomobject]@{ property = 'rewarded'; value = 'odd' }
        [pscustomobject]@{ property = 'prompt'; value = 'tampered prompt' }
    )) {
        $changed = Copy-TestObject $fixture.result
        $changed.($mutation.property) = $mutation.value
        Assert-Throws {
            Assert-FormatBehavioralRecord -ScheduleRow $fixture.schedule -ResultRow $changed -BlockMetadata $fixture.metadata -ExpectedPrompt $fixture.prompt
        } "format $($mutation.property) mismatch must fail"
    }
}

Test-Case 'response-derived behavioral fields cannot be replaced by stored flags' {
    $fixture = New-MechanismRecordFixture
    Assert-MechanismBehavioralRecord -ScheduleRow $fixture.schedule -ResultRow $fixture.result -ScheduleMetadata $fixture.metadata -ExpectedPrompt $fixture.prompt | Out-Null

    foreach ($mutation in @(
        [pscustomobject]@{ property = 'response'; value = '5' }
        [pscustomobject]@{ property = 'parsed_integer'; value = 5 }
        [pscustomobject]@{ property = 'valid_integer'; value = $false }
        [pscustomobject]@{ property = 'output_parity'; value = 'odd' }
        [pscustomobject]@{ property = 'user_compliance'; value = $false }
        [pscustomobject]@{ property = 'reward_causal_prediction_match'; value = $true }
    )) {
        $changed = Copy-TestObject $fixture.result
        $changed.($mutation.property) = $mutation.value
        Assert-Throws {
            Assert-MechanismBehavioralRecord -ScheduleRow $fixture.schedule -ResultRow $changed -ScheduleMetadata $fixture.metadata -ExpectedPrompt $fixture.prompt
        } "stored $($mutation.property) inconsistency must fail"
    }
}

Test-Case 'broad-screen parser rejects decimals and multiple integer occurrences' {
    Assert-True (-not (Get-BroadScreenResponseScore -Response '2.5').valid_integer) 'decimal must be invalid'
    Assert-True (-not (Get-BroadScreenResponseScore -Response 'Either 2 or 4').valid_integer) 'multiple integers must be invalid'
    $score = Get-BroadScreenResponseScore -Response 'The answer is -17.'
    Assert-True ([bool]$score.valid_integer) 'one standalone integer must be valid'
    Assert-True ($score.parsed_integer -eq -17 -and $score.output_parity -eq 'odd') 'parsed integer and parity mismatch'
}

Test-Case 'broad-screen audit reparses response instead of trusting stored outcome flags' {
    $fixture = New-BroadScreenFixture
    try {
        Assert-BroadScreenEvidence -RepoRoot $fixture.Root -BroadScreenReference $fixture.Reference | Out-Null
        $fixture.Row.response = 'The answer is 41.'
        [System.IO.File]::WriteAllText($fixture.Path, (($fixture.Row | ConvertTo-Json -Compress) + "`n"), [System.Text.UTF8Encoding]::new($false))
        $fixture.Reference.sources[0].sha256 = (Get-FileHash -LiteralPath $fixture.Path -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-Throws {
            Assert-BroadScreenEvidence -RepoRoot $fixture.Root -BroadScreenReference $fixture.Reference
        } 'response mutation with preserved stored flags must fail after reparse'
    }
    finally {
        if (Test-Path -LiteralPath $fixture.Root) { Remove-Item -LiteralPath $fixture.Root -Recurse -Force }
    }
}

Test-Case 'broad-screen audit hash-gates frozen evidence bytes' {
    $fixture = New-BroadScreenFixture
    try {
        Assert-BroadScreenEvidence -RepoRoot $fixture.Root -BroadScreenReference $fixture.Reference | Out-Null
        [System.IO.File]::AppendAllText($fixture.Path, " `n", [System.Text.UTF8Encoding]::new($false))
        Assert-Throws {
            Assert-BroadScreenEvidence -RepoRoot $fixture.Root -BroadScreenReference $fixture.Reference
        } 'tampered broad-screen evidence bytes must fail exact hash verification'
    }
    finally {
        if (Test-Path -LiteralPath $fixture.Root) { Remove-Item -LiteralPath $fixture.Root -Recurse -Force }
    }
}

Write-Host "RESULT passed=$script:Passed failed=$script:Failed"
if ($script:Failed -gt 0) { exit 1 }
