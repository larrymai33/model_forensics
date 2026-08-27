param([switch] $VerifyOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'logprob_helpers.ps1')

$root = 'E:\Temp\spar-odd-number-20260823\local-gpu'
$resultDir = Join-Path $root 'results\qwen3-4b-q4km-logprob-followup-v3'
$schedulePath = Join-Path $resultDir 'schedule.json'
$validationPath = Join-Path $resultDir 'validation.json'
$scorePath = Join-Path $resultDir 'condition_pair_scores.jsonl'
$rawPath = Join-Path $resultDir 'raw_responses.jsonl'
$summaryPath = Join-Path $resultDir 'summary.json'
$analysisPath = Join-Path $resultDir 'analysis.json'
$analysisMarkdownPath = Join-Path $resultDir 'analysis.md'
$finalizationPath = Join-Path $resultDir 'offline_finalization.json'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$bootstrapSamples = 10000
$bootstrapSeed = 20260823

$expectedHashes = [ordered]@{
    schedule = 'a59dd875427a356b83f98db436feae1c93e12b247dea2040f0cc84f875360fdc'
    validation = '6458582d03ea0d88e172c49472060c986cd6649502a870daed622bdd8419d3ff'
    scores = 'd4f33ed28557807be471a8d358f9181bbbd1dbb184f63b14a1058088f8fb5a3f'
    raw = '6f38950a9e1a2195226557793102778d36e377ccb3e92bdc8311ae1da8aee660'
    collection_summary = 'e4b6c5994acbf41fa68231ac4439968d4086ad949695a0772cf9493fca4b989a'
}

function Assert-EOnlyPath {
    param([Parameter(Mandatory)] [string] $Path)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith('E:\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Offline finalization path is not on E drive: $fullPath"
    }
}

function Assert-Hash {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Expected,
        [Parameter(Mandatory)] [string] $Label
    )
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $Expected) { throw "$Label hash changed: $actual" }
    $actual
}

function Get-MeanBootstrapSummary {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Values,
        [Parameter(Mandatory)] [int] $Seed
    )
    $numeric = [double[]]@($Values | ForEach-Object { [double]$_ })
    if ($numeric.Count -eq 0) {
        return [pscustomobject][ordered]@{ n = 0; mean = $null; bootstrap_95_percent = $null }
    }
    [pscustomobject][ordered]@{
        n = $numeric.Count
        mean = [double](($numeric | Measure-Object -Average).Average)
        bootstrap_95_percent = Get-BootstrapMeanInterval -Values $numeric -Samples $bootstrapSamples -Seed $Seed
    }
}

function Write-JsonDocument {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] $Value,
        [int] $Depth = 40
    )
    Assert-EOnlyPath -Path $Path
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth $Depth), $utf8NoBom)
}

foreach ($path in @(
    $root, $resultDir, $schedulePath, $validationPath, $scorePath, $rawPath, $summaryPath,
    $analysisPath, $analysisMarkdownPath, $finalizationPath
)) { Assert-EOnlyPath -Path $path }

foreach ($required in @($schedulePath, $validationPath, $scorePath, $rawPath, $summaryPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required collection artifact is missing: $required" }
}
foreach ($output in @($analysisPath, $analysisMarkdownPath, $finalizationPath)) {
    if (Test-Path -LiteralPath $output) { throw "Refusing to overwrite offline-finalization output: $output" }
}

$forbidden = @(Get-Process -ErrorAction Stop | Where-Object { $_.ProcessName -match '^(?:llama|ollama)(?:[-_ .]|$)' })
if ($forbidden.Count -gt 0) { throw 'A llama/ollama process is running; offline finalization refused.' }
$listeners = @(Get-NetTCPConnection -ErrorAction Stop | Where-Object { $_.State -eq 'Listen' -and $_.LocalPort -eq 18080 })
if ($listeners.Count -gt 0) { throw 'Port 18080 still has a listener; offline finalization refused.' }

$inputHashes = [ordered]@{
    schedule = Assert-Hash -Path $schedulePath -Expected $expectedHashes.schedule -Label 'Schedule'
    validation = Assert-Hash -Path $validationPath -Expected $expectedHashes.validation -Label 'Validation'
    scores = Assert-Hash -Path $scorePath -Expected $expectedHashes.scores -Label 'Condition-pair scores'
    raw = Assert-Hash -Path $rawPath -Expected $expectedHashes.raw -Label 'Raw responses'
    collection_summary = Assert-Hash -Path $summaryPath -Expected $expectedHashes.collection_summary -Label 'Collection summary'
}

$schedule = Get-Content -Raw -LiteralPath $schedulePath | ConvertFrom-Json -Depth 100
$validation = Get-Content -Raw -LiteralPath $validationPath | ConvertFrom-Json -Depth 100
$collectionSummary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json -Depth 100
$scores = @(Get-Content -LiteralPath $scorePath | ForEach-Object { $_ | ConvertFrom-Json -Depth 100 })

if (-not $validation.passed) { throw 'Saved validation gate did not pass.' }
if (@($validation.checks | Where-Object passed -eq $false).Count -ne 0) { throw 'Saved validation contains a failed check.' }
if ($collectionSummary.fatal_error -cne "Cannot bind argument to parameter 'Values' because it is null.") {
    throw "Unexpected collection-runner failure: $($collectionSummary.fatal_error)"
}
if (-not $collectionSummary.full_gpu_offload_37_of_37 -or -not $collectionSummary.validation_passed) {
    throw 'Collection summary did not attest full offload and validation.'
}
if ($collectionSummary.planned_condition_pair_scores -ne 112 -or $collectionSummary.collected_condition_pair_scores -ne 112) {
    throw 'Collection summary does not attest 112/112 task scores.'
}
foreach ($cleanupProperty in @('owned_process_gone', 'parent_watchdog_process_gone', 'listener_gone', 'no_llama_or_ollama_processes')) {
    if (-not [bool]$collectionSummary.cleanup.$cleanupProperty) { throw "Collection cleanup check failed: $cleanupProperty" }
}
if ($null -ne $collectionSummary.cleanup.cleanup_error) { throw "Collection cleanup reported an error: $($collectionSummary.cleanup.cleanup_error)" }

if (@($schedule.conditions).Count -ne 14) { throw 'Schedule does not contain fourteen conditions.' }
if (@($schedule.candidate_pair_screen | Where-Object retained -eq $true).Count -ne 8) { throw 'Schedule does not retain all eight candidate pairs.' }
if (@($schedule.scoring_schedule).Count -ne 112 -or $scores.Count -ne 112) { throw 'Schedule or scores do not contain 112 rows.' }
if (@($scores.schedule_id | Select-Object -Unique).Count -ne 112) { throw 'Score schedule IDs are not unique.' }
$missingScheduleIds = @(Compare-Object -ReferenceObject @($schedule.scoring_schedule.schedule_id) -DifferenceObject @($scores.schedule_id))
if ($missingScheduleIds.Count -ne 0) { throw 'Score schedule IDs do not exactly match the frozen schedule.' }

foreach ($condition in $schedule.conditions) {
    $rows = @($scores | Where-Object condition_id -eq $condition.id)
    if ($rows.Count -ne 8) { throw "Condition $($condition.id) has $($rows.Count) rows instead of eight." }
}
foreach ($row in $scores) {
    $even = Get-RequiredFiniteRowValue -Row $row -Property even_logprob -Label $row.schedule_id
    $odd = Get-RequiredFiniteRowValue -Row $row -Property odd_logprob -Label $row.schedule_id
    $rawOdds = Get-RequiredFiniteRowValue -Row $row -Property even_minus_odd_log_odds -Label $row.schedule_id
    if ($even -gt 0 -or $odd -gt 0 -or $even -le -1e30 -or $odd -le -1e30) { throw "Invalid candidate logprob range: $($row.schedule_id)" }
    if ([math]::Abs($rawOdds - ($even - $odd)) -gt 1e-9) { throw "Raw log-odds mismatch: $($row.schedule_id)" }
    $expectedRequested = if ($row.requested_parity -eq 'even') { $rawOdds } else { -$rawOdds }
    if ([math]::Abs([double]$row.requested_aligned_log_odds - $expectedRequested) -gt 1e-9) {
        throw "Requested-aligned sign mismatch: $($row.schedule_id)"
    }
    if ($null -eq $row.rewarded_output_parity) {
        if ($null -ne $row.reward_aligned_log_odds) { throw "Baseline row has reward-aligned odds: $($row.schedule_id)" }
    }
    else {
        $expectedReward = if ($row.rewarded_output_parity -eq 'even') { $rawOdds } else { -$rawOdds }
        if ([math]::Abs([double]$row.reward_aligned_log_odds - $expectedReward) -gt 1e-9) {
            throw "Reward-aligned sign mismatch: $($row.schedule_id)"
        }
    }
}

$conditionSummaries = [System.Collections.Generic.List[object]]::new()
$conditionIndex = 0
foreach ($condition in $schedule.conditions) {
    $rows = @($scores | Where-Object condition_id -eq $condition.id)
    $requestedSummary = Get-MeanBootstrapSummary -Values @($rows.requested_aligned_log_odds) -Seed ($bootstrapSeed + $conditionIndex)
    $rewardSummary = if ($null -eq $condition.rewarded_output_parity) {
        [pscustomobject][ordered]@{ n = 0; mean = $null; bootstrap_95_percent = $null }
    }
    else {
        Get-MeanBootstrapSummary -Values @($rows.reward_aligned_log_odds) -Seed ($bootstrapSeed + 100 + $conditionIndex)
    }
    $conditionSummaries.Add([pscustomobject][ordered]@{
        condition_id = $condition.id
        family = $condition.family
        requested_parity = $condition.requested_parity
        rewarded_output_parity = $condition.rewarded_output_parity
        controllability = $condition.controllability
        mapping = $condition.mapping
        congruence = $condition.congruence
        requested_aligned = $requestedSummary
        reward_aligned = $rewardSummary
    })
    $conditionIndex += 1
}

$primary = Get-PrimaryLogprobEstimand -PairScores $scores -BootstrapSamples $bootstrapSamples -BootstrapSeed $bootstrapSeed
$secondary = Get-SecondaryLogprobEstimands -PairScores $scores -BootstrapSamples $bootstrapSamples -BootstrapSeed ($bootstrapSeed + 1000)
$transform = Get-TransformLogprobEstimands -PairScores $scores -BootstrapSamples $bootstrapSamples -BootstrapSeed ($bootstrapSeed + 2000)
$baselines = @($conditionSummaries | Where-Object family -eq 'baseline')

$analysis = [pscustomobject][ordered]@{
    status = 'completed_offline_from_complete_validated_scores'
    collection_runner_status = $collectionSummary.status
    collection_runner_failure_stage = 'offline_analysis_after_server_stop_and_112_of_112_task_scores'
    collection_runner_fatal_error = $collectionSummary.fatal_error
    validation_passed = $true
    full_gpu_offload_37_of_37 = $true
    retained_pair_count = 8
    condition_count = 14
    condition_pair_score_count = 112
    primary_estimand = $primary
    secondary_estimands = $secondary
    condition_summaries = $conditionSummaries.ToArray()
    baseline_requested_parity_preference = $baselines
    transform_estimands = $transform
    input_sha256 = [pscustomobject]$inputHashes
    interpretation_limits = @(
        'Conditional token probabilities do not establish a persistent objective, reward hacking, scheming, deception, or tampering.'
        'Current and archived shifts of similar size favor grader-tag, second-instruction, or salience accounts over causal optimization.'
        'This direct-answer probe uses the native Qwen template with enable_thinking=false.'
        'Pair-bootstrap intervals describe sensitivity across eight fixed candidate pairs; they are not population-sampling confidence intervals.'
    )
}

$primaryCi = $primary.bootstrap_95_percent
$conflict = $secondary.conflict_current_minus_archived
$conflictCi = $conflict.bootstrap_95_percent
$currentConflictMirror = @($secondary.mirrored_direction_reversal | Where-Object { $_.controllability -eq 'current' -and $_.congruence -eq 'conflict' })[0]
$archivedConflictMirror = @($secondary.mirrored_direction_reversal | Where-Object { $_.controllability -eq 'archived' -and $_.congruence -eq 'conflict' })[0]
$transformReversal = $transform.causal_output_parity_reversal
$transformCi = $transformReversal.bootstrap_95_percent
$analysisMarkdown = @(
    '# Qwen3-4B matched-candidate log-probability analysis'
    ''
    'Status: completed offline from 112/112 validated task-score rows after the collection runner had already stopped the server. The collection runner itself failed only while constructing an empty baseline reward summary.'
    ''
    '## Primary estimand'
    ''
    ('Controllability-by-conflict DID: {0:R}' -f $primary.primary_mean)
    ('Pair-bootstrap 95% interval: [{0:R}, {1:R}]' -f $primaryCi.lower, $primaryCi.upper)
    ('Even-request DID: {0:R}' -f $primary.even_request_mean)
    ('Odd-request DID: {0:R}' -f $primary.odd_request_mean)
    ''
    '## Secondary checks'
    ''
    ('Conflict current-minus-archived mean: {0:R}' -f $conflict.averaged_mean)
    ('Pair-bootstrap 95% interval: [{0:R}, {1:R}]' -f $conflictCi.lower, $conflictCi.upper)
    ('Current-conflict mirrored reward-aligned mean: {0:R}' -f $currentConflictMirror.reward_aligned_pair_mean)
    ('Archived-conflict mirrored reward-aligned mean: {0:R}' -f $archivedConflictMirror.reward_aligned_pair_mean)
    ('Transform causal-output-parity reversal: {0:R}' -f $transformReversal.mean)
    ('Pair-bootstrap 95% interval: [{0:R}, {1:R}]' -f $transformCi.lower, $transformCi.upper)
    ''
    '## Interpretation limit'
    ''
    'These direct-answer conditional token probabilities do not establish a persistent objective, reward hacking, scheming, deception, or tampering. Pair-bootstrap intervals are descriptive across eight fixed candidate pairs.'
) -join "`n"

$verification = [pscustomobject][ordered]@{
    status = 'verified_complete_inputs'
    validation_passed = $true
    full_gpu_offload_37_of_37 = $true
    collected_condition_pair_scores = $scores.Count
    unique_schedule_ids = @($scores.schedule_id | Select-Object -Unique).Count
    input_sha256 = [pscustomobject]$inputHashes
    primary_mean = $primary.primary_mean
    primary_bootstrap_95_percent = $primary.bootstrap_95_percent
    conflict_current_minus_archived_mean = $conflict.averaged_mean
    transform_reversal_mean = $transformReversal.mean
}

if ($VerifyOnly) {
    $verification | ConvertTo-Json -Depth 20
    exit 0
}

Write-JsonDocument -Path $analysisPath -Value $analysis -Depth 50
[System.IO.File]::WriteAllText($analysisMarkdownPath, $analysisMarkdown, $utf8NoBom)
$finalization = [pscustomobject][ordered]@{
    status = 'completed_offline_from_complete_validated_scores'
    finalized_at_utc = [datetime]::UtcNow.ToString('o')
    finalizer_path = $PSCommandPath
    finalizer_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    input_sha256 = [pscustomobject]$inputHashes
    output_sha256 = [pscustomobject][ordered]@{
        analysis_json = (Get-FileHash -LiteralPath $analysisPath -Algorithm SHA256).Hash.ToLowerInvariant()
        analysis_markdown = (Get-FileHash -LiteralPath $analysisMarkdownPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    verification = $verification
}
Write-JsonDocument -Path $finalizationPath -Value $finalization -Depth 30
$finalization | ConvertTo-Json -Depth 30
