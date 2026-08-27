$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'logprob_helpers.ps1')

$resultDir = 'E:\Temp\spar-odd-number-20260823\local-gpu\results\qwen3-4b-q4km-logprob-followup-v3'
$scorePath = Join-Path $resultDir 'condition_pair_scores.jsonl'
$outputPath = Join-Path $resultDir 'exploratory_user_alignment_decomposition.json'
$expectedScoreHash = 'd4f33ed28557807be471a8d358f9181bbbd1dbb184f63b14a1058088f8fb5a3f'
$actualScoreHash = (Get-FileHash -LiteralPath $scorePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualScoreHash -cne $expectedScoreHash) { throw "Score file hash changed: $actualScoreHash" }
if (Test-Path -LiteralPath $outputPath) { throw "Refusing to overwrite: $outputPath" }

$scores = @(Get-Content -LiteralPath $scorePath | ForEach-Object { $_ | ConvertFrom-Json -Depth 100 })
$pairRows = [System.Collections.Generic.List[object]]::new()
foreach ($pairId in @($scores.pair_id | Select-Object -Unique)) {
    $pair = @($scores | Where-Object pair_id -eq $pairId)
    $valueFor = {
        param([string] $ConditionId)
        $matches = @($pair | Where-Object condition_id -eq $ConditionId)
        if ($matches.Count -ne 1) { throw "Expected one row for $pairId/$ConditionId." }
        [double]$matches[0].requested_aligned_log_odds
    }
    $conflict = (
        ((& $valueFor 'core_request_even_reward_odd_current') - (& $valueFor 'core_request_even_reward_odd_archived')) +
        ((& $valueFor 'core_request_odd_reward_even_current') - (& $valueFor 'core_request_odd_reward_even_archived'))
    ) / 2.0
    $congruent = (
        ((& $valueFor 'core_request_even_reward_even_current') - (& $valueFor 'core_request_even_reward_even_archived')) +
        ((& $valueFor 'core_request_odd_reward_odd_current') - (& $valueFor 'core_request_odd_reward_odd_archived'))
    ) / 2.0
    $pairRows.Add([pscustomobject][ordered]@{
        pair_id = $pairId
        conflict_user_current_minus_archived = [double]$conflict
        congruent_user_current_minus_archived = [double]$congruent
        mean_user_boost = [double](($conflict + $congruent) / 2.0)
        conflict_minus_congruent = [double]($conflict - $congruent)
    })
}

$result = [pscustomobject][ordered]@{
    status = 'post_hoc_exploratory_decomposition'
    rationale = 'Re-express the preregistered reward-oriented DID in user-aligned coordinates after observing that its sign was negative.'
    input_score_sha256 = $actualScoreHash
    pair_count = $pairRows.Count
    conflict_user_current_minus_archived = [pscustomobject][ordered]@{
        mean = [double](($pairRows.conflict_user_current_minus_archived | Measure-Object -Average).Average)
        pair_bootstrap_95_percent = Get-BootstrapMeanInterval -Values @($pairRows.conflict_user_current_minus_archived) -Samples 10000 -Seed 20264001
    }
    congruent_user_current_minus_archived = [pscustomobject][ordered]@{
        mean = [double](($pairRows.congruent_user_current_minus_archived | Measure-Object -Average).Average)
        pair_bootstrap_95_percent = Get-BootstrapMeanInterval -Values @($pairRows.congruent_user_current_minus_archived) -Samples 10000 -Seed 20264002
    }
    overall_user_current_minus_archived = [pscustomobject][ordered]@{
        mean = [double](($pairRows.mean_user_boost | Measure-Object -Average).Average)
        pair_bootstrap_95_percent = Get-BootstrapMeanInterval -Values @($pairRows.mean_user_boost) -Samples 10000 -Seed 20264003
    }
    user_aligned_conflict_interaction = [pscustomobject][ordered]@{
        mean = [double](($pairRows.conflict_minus_congruent | Measure-Object -Average).Average)
        pair_bootstrap_95_percent = Get-BootstrapMeanInterval -Values @($pairRows.conflict_minus_congruent) -Samples 10000 -Seed 20264004
    }
    interpretation_limit = 'This decomposition was specified after seeing the preregistered primary result and is explanatory, not confirmatory.'
    pair_level = $pairRows.ToArray()
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($outputPath, ($result | ConvertTo-Json -Depth 20), $utf8NoBom)
$result | ConvertTo-Json -Depth 20
