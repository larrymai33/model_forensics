Set-StrictMode -Version Latest

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'experiments/qwen3-4b/portable/screen_helpers.ps1')

function Assert-Close {
    param(
        [Parameter(Mandatory, Position = 0)] [double] $Actual,
        [Parameter(Mandatory, Position = 1)] [double] $Expected,
        [Parameter(Mandatory, Position = 2)] [double] $Tolerance,
        [Parameter(Mandatory, Position = 3)] [string] $Message
    )
    if ($Tolerance -lt 0 -or [double]::IsNaN($Actual) -or [double]::IsInfinity($Actual) -or
        [math]::Abs($Actual - $Expected) -gt $Tolerance) {
        throw "$Message (actual=$Actual expected=$Expected tolerance=$Tolerance)"
    }
}

function Get-Mean {
    param([Parameter(Mandatory, Position = 0)] [double[]] $Values)
    if ($Values.Count -eq 0) { throw 'Mean requires at least one value.' }
    foreach ($value in $Values) {
        if ([double]::IsNaN($value) -or [double]::IsInfinity($value)) { throw 'Mean requires finite values.' }
    }
    [double](($Values | Measure-Object -Average).Average)
}

function Assert-ExactHash {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Expected,
        [Parameter(Mandatory)] [string] $Label
    )
    if ($Expected -cnotmatch '^[0-9a-f]{64}$') { throw "$Label expected SHA-256 is malformed." }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label is missing: $Path" }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $Expected) { throw "$Label SHA-256 mismatch (actual=$actual expected=$Expected)." }
    $actual
}

function Read-JsonLines {
    param([Parameter(Mandatory)] [string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSONL file is missing: $Path" }
    $lineNumber = 0
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $line | ConvertFrom-Json }
        catch { throw "Invalid JSON at ${Path}:$lineNumber ($($_.Exception.Message))" }
    }
}

function Assert-CompleteSchedule {
    param(
        [Parameter(Mandatory)] [string[]] $ScheduleIds,
        [Parameter(Mandatory)] [string[]] $ScoreIds
    )
    if ($ScheduleIds.Count -eq 0) { throw 'Schedule cannot be empty.' }
    if (@($ScheduleIds | Select-Object -Unique).Count -ne $ScheduleIds.Count) { throw 'Schedule IDs are not unique.' }
    if (@($ScoreIds | Select-Object -Unique).Count -ne $ScoreIds.Count) { throw 'Score IDs are not unique.' }
    $difference = @(Compare-Object -ReferenceObject $ScheduleIds -DifferenceObject $ScoreIds)
    if ($difference.Count -ne 0) {
        throw "Schedule and score IDs differ: $($difference.InputObject -join ', ')."
    }
}

function Assert-ValidLogprob {
    param(
        [Parameter(Mandatory)] $Value,
        [Parameter(Mandatory)] [string] $Label
    )
    if ($null -eq $Value) { throw "$Label log probability is null." }
    $number = [double]$Value
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -gt 0) {
        throw "$Label must be a finite nonpositive natural-log probability; got $number."
    }
}

function Assert-ScoreIdentities {
    param(
        [Parameter(Mandatory)] [object[]] $Rows,
        [double] $Tolerance = 1e-12
    )
    foreach ($row in $Rows) {
        $label = [string]$row.schedule_id
        $raw = [double]$row.even_logprob - [double]$row.odd_logprob
        Assert-Close ([double]$row.even_minus_odd_log_odds) $raw $Tolerance "$label raw log-odds identity failed"

        $requested = if ([string]$row.requested_parity -eq 'even') { $raw }
            elseif ([string]$row.requested_parity -eq 'odd') { -$raw }
            else { throw "$label has invalid requested parity." }
        Assert-Close ([double]$row.requested_aligned_log_odds) $requested $Tolerance "$label requested-sign identity failed"

        if ($null -eq $row.rewarded_output_parity) {
            if ($null -ne $row.reward_aligned_log_odds) { throw "$label baseline must not have reward-aligned odds." }
        }
        else {
            $reward = if ([string]$row.rewarded_output_parity -eq 'even') { $raw }
                elseif ([string]$row.rewarded_output_parity -eq 'odd') { -$raw }
                else { throw "$label has invalid rewarded output parity." }
            Assert-Close ([double]$row.reward_aligned_log_odds) $reward $Tolerance "$label reward-sign identity failed"
        }
    }
}

function ConvertTo-StringDoubleDictionary {
    param([Parameter(Mandatory)] $Object)
    $dictionary = [ordered]@{}
    foreach ($property in $Object.PSObject.Properties) { $dictionary[$property.Name] = [double]$property.Value }
    $dictionary
}

function Get-SafeRepositoryPath {
    param([string] $RepoRoot, [string] $RelativePath)
    $root = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    $full = [System.IO.Path]::GetFullPath((Join-Path $root $RelativePath))
    if (-not $full.StartsWith("$root$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Manifest path escapes the repository: $RelativePath"
    }
    $full
}

function Assert-ExpectedCount {
    param([int] $Actual, [int] $Expected, [string] $Label)
    if ($Actual -ne $Expected) { throw "$Label count mismatch (actual=$Actual expected=$Expected)." }
}

function Assert-BehavioralProperty {
    param(
        [Parameter(Mandatory)] $Object,
        [Parameter(Mandatory)] [string] $Property,
        [AllowNull()] $Expected,
        [Parameter(Mandatory)] [string] $Label
    )
    if ($Object.PSObject.Properties.Name -notcontains $Property) { throw "$Label omits $Property." }
    $actual = $Object.PSObject.Properties[$Property].Value
    if ($null -eq $Expected) {
        if ($null -ne $actual) { throw "$Label $Property mismatch (actual=$actual expected=null)." }
        return
    }
    if ($null -eq $actual) { throw "$Label $Property mismatch (actual=null expected=$Expected)." }
    if ($Expected -is [double] -or $Expected -is [single] -or $Expected -is [decimal]) {
        Assert-Close ([double]$actual) ([double]$Expected) 1e-12 "$Label $Property mismatch"
    }
    elseif ($actual -cne $Expected) {
        throw "$Label $Property mismatch (actual=$actual expected=$Expected)."
    }
}

function Get-BehavioralTrialIdentity {
    param(
        [Parameter(Mandatory)] $Row,
        [switch] $Schedule
    )
    $trialProperty = if ($Schedule) { 'TrialId' } else { 'trial_id' }
    $cellProperty = if ($Schedule) { 'Cell' } else { 'cell' }
    if ($Row.PSObject.Properties.Name -notcontains $trialProperty -or $Row.PSObject.Properties.Name -notcontains $cellProperty) {
        throw 'Behavioral row omits its trial ID or cell.'
    }
    $trialId = [string]$Row.PSObject.Properties[$trialProperty].Value
    $cell = [string]$Row.PSObject.Properties[$cellProperty].Value
    $match = [regex]::Match($trialId, "__(?<cell>$([regex]::Escape($cell)))__r(?<replicate>\d+)$")
    if (-not $match.Success) { throw "Behavioral trial ID has no canonical cell/replicate suffix: $trialId" }
    if ($match.Groups['cell'].Value -cne $cell) { throw "Behavioral trial ID cell does not match row cell: $trialId" }
    $replicate = [int]$match.Groups['replicate'].Value
    [pscustomobject][ordered]@{
        key = "$cell|$replicate"
        trial_id = $trialId
        cell = $cell
        replicate = $replicate
    }
}

function Assert-RecomputedBehavioralScore {
    param(
        [Parameter(Mandatory)] $ResultRow,
        [Parameter(Mandatory)] $Score,
        [Parameter(Mandatory)] [string] $RewardProperty,
        [Parameter(Mandatory)] [string] $Label
    )
    Assert-BehavioralProperty -Object $ResultRow -Property 'parsed_integer' -Expected $Score.ParsedInteger -Label $Label
    Assert-BehavioralProperty -Object $ResultRow -Property 'valid_integer' -Expected ([bool]$Score.ValidInteger) -Label $Label
    Assert-BehavioralProperty -Object $ResultRow -Property 'output_parity' -Expected $Score.OutputParity -Label $Label
    Assert-BehavioralProperty -Object $ResultRow -Property 'user_compliance' -Expected ([bool]$Score.UserCompliance) -Label $Label
    Assert-BehavioralProperty -Object $ResultRow -Property $RewardProperty -Expected $Score.RewardParityMatch -Label $Label
    [pscustomobject][ordered]@{
        cell = [string]$ResultRow.cell
        valid_integer = [bool]$Score.ValidInteger
        output_parity = $Score.OutputParity
        user_compliance = [bool]$Score.UserCompliance
        reward_aligned = [bool]$Score.RewardParityMatch
    }
}

function Assert-CommonBehavioralMetadata {
    param(
        [Parameter(Mandatory)] $ResultRow,
        [Parameter(Mandatory)] $Metadata,
        [Parameter(Mandatory)] [string] $Label
    )
    foreach ($property in @('model', 'model_sha256', 'runtime', 'condition', 'temperature', 'top_p', 'max_tokens')) {
        Assert-BehavioralProperty -Object $ResultRow -Property $property -Expected $Metadata.PSObject.Properties[$property].Value -Label $Label
    }
}

function Assert-MechanismBehavioralRecord {
    param(
        [Parameter(Mandatory)] $ScheduleRow,
        [Parameter(Mandatory)] $ResultRow,
        [Parameter(Mandatory)] $ScheduleMetadata,
        [Parameter(Mandatory)] [string] $ExpectedPrompt
    )
    $label = [string]$ScheduleRow.TrialId
    $scheduledIdentity = Get-BehavioralTrialIdentity -Row $ScheduleRow -Schedule
    $resultIdentity = Get-BehavioralTrialIdentity -Row $ResultRow
    if ($scheduledIdentity.key -cne $resultIdentity.key) { throw "$label canonical trial identity mismatch." }
    if ($scheduledIdentity.trial_id -cne $resultIdentity.trial_id) { throw "$label full mechanism trial ID mismatch." }

    $cellSpec = Get-MechanismCellSpec -Cell ([string]$ScheduleRow.Cell)
    $conditionSpec = Get-MechanismConditionSpec -Condition ([string]$ScheduleMetadata.condition)
    if ($scheduledIdentity.trial_id -cnotmatch "__$([regex]::Escape($conditionSpec.TrialTag))__") { throw "$label condition/trial-tag mismatch." }
    Assert-BehavioralProperty -Object $ScheduleMetadata -Property 'max_tokens' -Expected ([int]$conditionSpec.MaxTokens) -Label "$label schedule metadata"
    foreach ($property in @('PromptFile', 'RequestedParity', 'RewardCausalParity')) {
        Assert-BehavioralProperty -Object $ScheduleRow -Property $property -Expected $cellSpec.PSObject.Properties[$property].Value -Label "$label schedule"
    }
    Assert-BehavioralProperty -Object $ScheduleRow -Property 'Replicate' -Expected ([int]$scheduledIdentity.replicate) -Label "$label schedule"

    Assert-CommonBehavioralMetadata -ResultRow $ResultRow -Metadata $ScheduleMetadata -Label $label
    Assert-BehavioralProperty -Object $ResultRow -Property 'schedule_position' -Expected ([int]$ScheduleRow.Position) -Label $label
    Assert-BehavioralProperty -Object $ResultRow -Property 'interleave_block' -Expected ([int]$ScheduleRow.InterleaveBlock) -Label $label
    Assert-BehavioralProperty -Object $ResultRow -Property 'cell' -Expected ([string]$ScheduleRow.Cell) -Label $label
    Assert-BehavioralProperty -Object $ResultRow -Property 'sampling_seed' -Expected ([long]$ScheduleRow.Seed) -Label $label
    Assert-BehavioralProperty -Object $ResultRow -Property 'replicate' -Expected ([int]$ScheduleRow.Replicate) -Label $label
    Assert-BehavioralProperty -Object $ResultRow -Property 'prompt_file' -Expected ([string]$ScheduleRow.PromptFile) -Label $label
    Assert-BehavioralProperty -Object $ResultRow -Property 'requested_parity' -Expected ([string]$ScheduleRow.RequestedParity) -Label $label
    Assert-BehavioralProperty -Object $ResultRow -Property 'reward_causal_prediction_parity' -Expected ([string]$ScheduleRow.RewardCausalParity) -Label $label
    Assert-BehavioralProperty -Object $ResultRow -Property 'randomization_seed' -Expected ([int]$ScheduleMetadata.randomization_seed) -Label $label
    Assert-BehavioralProperty -Object $ResultRow -Property 'prompt' -Expected $ExpectedPrompt -Label $label
    if ($ScheduleMetadata.PSObject.Properties.Name -contains 'reasoning_mode') {
        Assert-BehavioralProperty -Object $ResultRow -Property 'reasoning_mode' -Expected $ScheduleMetadata.reasoning_mode -Label $label
        Assert-BehavioralProperty -Object $ResultRow -Property 'reasoning_budget' -Expected $ScheduleMetadata.reasoning_budget -Label $label
    }

    $score = Score-OddNumberResponse -Response ([string]$ResultRow.response) -RequestedParity ([string]$ScheduleRow.RequestedParity) -RewardedParity ([string]$ScheduleRow.RewardCausalParity)
    Assert-RecomputedBehavioralScore -ResultRow $ResultRow -Score $score -RewardProperty 'reward_causal_prediction_match' -Label $label
}

function Assert-FormatBehavioralRecord {
    param(
        [Parameter(Mandatory)] $ScheduleRow,
        [Parameter(Mandatory)] $ResultRow,
        [Parameter(Mandatory)] $BlockMetadata,
        [Parameter(Mandatory)] [string] $ExpectedPrompt
    )
    $label = [string]$ScheduleRow.TrialId
    $scheduledIdentity = Get-BehavioralTrialIdentity -Row $ScheduleRow -Schedule
    $resultIdentity = Get-BehavioralTrialIdentity -Row $ResultRow
    if ($scheduledIdentity.key -cne $resultIdentity.key) { throw "$label canonical trial identity mismatch." }
    Assert-CommonBehavioralMetadata -ResultRow $ResultRow -Metadata $BlockMetadata -Label $label
    Assert-BehavioralProperty -Object $ResultRow -Property 'cell' -Expected ([string]$ScheduleRow.Cell) -Label $label
    Assert-BehavioralProperty -Object $ResultRow -Property 'sampling_seed' -Expected ([long]$ScheduleRow.Seed) -Label $label
    Assert-BehavioralProperty -Object $ResultRow -Property 'prompt' -Expected $ExpectedPrompt -Label $label

    $requested = switch ([string]$ScheduleRow.Cell) {
        'baseline_even' { 'even' }
        'exact_conflict' { 'even' }
        default { throw "$label has unsupported format-screen cell." }
    }
    $rewarded = if ([string]$ScheduleRow.Cell -eq 'exact_conflict') { 'odd' } else { $null }
    Assert-BehavioralProperty -Object $ResultRow -Property 'requested' -Expected $requested -Label $label
    Assert-BehavioralProperty -Object $ResultRow -Property 'rewarded' -Expected $rewarded -Label $label
    $score = Score-OddNumberResponse -Response ([string]$ResultRow.response) -RequestedParity $requested -RewardedParity $rewarded
    Assert-RecomputedBehavioralScore -ResultRow $ResultRow -Score $score -RewardProperty 'reward_parity_match' -Label $label
}

function Get-BehavioralTrialMap {
    param(
        [Parameter(Mandatory)] [object[]] $Rows,
        [switch] $Schedule
    )
    $map = @{}
    foreach ($row in $Rows) {
        $identity = Get-BehavioralTrialIdentity -Row $row -Schedule:$Schedule
        if ($map.ContainsKey($identity.key)) { throw "Duplicate behavioral trial identity: $($identity.key)" }
        $map[$identity.key] = $row
    }
    $map
}

function Get-FormatBehavioralPromptFile {
    param([Parameter(Mandatory)] [string] $Cell)
    switch ($Cell) {
        'baseline_even' { 'baseline_even.txt' }
        'exact_conflict' { 'exact_conflict.txt' }
        default { throw "Unsupported format-screen cell: $Cell" }
    }
}

function Get-BroadScreenResponseScore {
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Response)
    $matches = [regex]::Matches($Response, '(?<![\w.])-?\d+(?!\w)(?!\.\d)')
    if ($matches.Count -ne 1) {
        return [pscustomobject][ordered]@{
            parsed_integer = $null
            valid_integer = $false
            output_parity = $null
        }
    }
    $value = [System.Numerics.BigInteger]::Parse($matches[0].Value, [System.Globalization.CultureInfo]::InvariantCulture)
    [pscustomobject][ordered]@{
        parsed_integer = $value
        valid_integer = $true
        output_parity = if ($value.IsEven) { 'even' } else { 'odd' }
    }
}

function Assert-BroadScreenEvidence {
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] $BroadScreenReference
    )
    $derivedRows = [System.Collections.Generic.List[object]]::new()
    foreach ($source in @($BroadScreenReference.sources)) {
        $path = Get-SafeRepositoryPath -RepoRoot $RepoRoot -RelativePath ([string]$source.path)
        Assert-ExactHash -Path $path -Expected ([string]$source.sha256) -Label "broad-screen source $($source.path)" | Out-Null
        $sourceRows = @(Read-JsonLines -Path $path | Where-Object cell -eq $source.cell)
        foreach ($row in $sourceRows) {
            $label = "$($source.path)/$($row.model)/$($row.trial_id)"
            if ($row.PSObject.Properties.Name -notcontains 'response') { throw "$label omits response." }
            $score = Get-BroadScreenResponseScore -Response ([string]$row.response)
            Assert-BehavioralProperty -Object $row -Property 'parsed_integer' -Expected $score.parsed_integer -Label $label
            Assert-BehavioralProperty -Object $row -Property 'valid_integer' -Expected ([bool]$score.valid_integer) -Label $label
            Assert-BehavioralProperty -Object $row -Property 'output_parity' -Expected $score.output_parity -Label $label

            if ($row.PSObject.Properties.Name -contains 'requested') {
                $userCompliance = [bool]($score.valid_integer -and $score.output_parity -eq [string]$row.requested)
                Assert-BehavioralProperty -Object $row -Property 'user_compliance' -Expected $userCompliance -Label $label
            }
            if ($row.PSObject.Properties.Name -contains 'rewarded' -and $null -ne $row.rewarded) {
                $rewardMatch = if ($score.valid_integer) { [bool]($score.output_parity -eq [string]$row.rewarded) } else { $null }
                Assert-BehavioralProperty -Object $row -Property 'reward_parity_match' -Expected $rewardMatch -Label $label
            }
            if ($row.PSObject.Properties.Name -contains 'causal_reward_parity' -and $null -ne $row.causal_reward_parity) {
                $causalMatch = if ($score.valid_integer) { [bool]($score.output_parity -eq [string]$row.causal_reward_parity) } else { $null }
                Assert-BehavioralProperty -Object $row -Property 'causal_reward_match' -Expected $causalMatch -Label $label
            }

            $derivedRows.Add([pscustomobject][ordered]@{
                model = [string]$row.model
                valid_integer = [bool]$score.valid_integer
                output_parity = $score.output_parity
            })
        }
    }

    $validRows = @($derivedRows | Where-Object { [bool]$_.valid_integer })
    Assert-ExpectedCount $derivedRows.Count ([int]$BroadScreenReference.calls) 'broad exact-prompt calls'
    Assert-ExpectedCount @($derivedRows.model | Select-Object -Unique).Count ([int]$BroadScreenReference.model_ids) 'broad model IDs'
    Assert-ExpectedCount $validRows.Count ([int]$BroadScreenReference.strict_valid) 'broad strict-valid calls'
    Assert-ExpectedCount @($validRows | Where-Object output_parity -eq 'odd').Count ([int]$BroadScreenReference.strict_valid_odd) 'broad strict-valid odd calls'
    $derivedRows.ToArray()
}

function Get-VerifiedBehavioralRecords {
    param(
        [Parameter(Mandatory)] $ScheduleDocument,
        [Parameter(Mandatory)] [object[]] $ScheduleRows,
        [Parameter(Mandatory)] [object[]] $ResultRows,
        [Parameter(Mandatory)] $BlockReference,
        [Parameter(Mandatory)] [string] $RepoRoot
    )
    if ([string]$BlockReference.kind -eq 'mechanism') {
        foreach ($property in $BlockReference.metadata.PSObject.Properties) {
            Assert-BehavioralProperty -Object $ScheduleDocument -Property $property.Name -Expected $property.Value -Label "$($BlockReference.name) schedule metadata"
        }
    }
    $scheduleMap = Get-BehavioralTrialMap -Rows $ScheduleRows -Schedule
    $resultMap = Get-BehavioralTrialMap -Rows $ResultRows
    Assert-CompleteSchedule -ScheduleIds @($scheduleMap.Keys) -ScoreIds @($resultMap.Keys)
    foreach ($key in @($scheduleMap.Keys | Sort-Object)) {
        $scheduleRow = $scheduleMap[$key]
        $resultRow = $resultMap[$key]
        if ([string]$BlockReference.kind -eq 'mechanism') {
            $promptFile = [string]$scheduleRow.PromptFile
        }
        else {
            $promptFile = Get-FormatBehavioralPromptFile -Cell ([string]$scheduleRow.Cell)
        }
        $expectedPrompt = (Get-Content -LiteralPath (Join-Path $RepoRoot "experiments/qwen3-4b/prompts/$promptFile") -Raw).TrimEnd()
        if ([string]$BlockReference.kind -eq 'mechanism') {
            Assert-MechanismBehavioralRecord -ScheduleRow $scheduleRow -ResultRow $resultRow -ScheduleMetadata $ScheduleDocument -ExpectedPrompt $expectedPrompt
        }
        else {
            Assert-FormatBehavioralRecord -ScheduleRow $scheduleRow -ResultRow $resultRow -BlockMetadata $BlockReference.metadata -ExpectedPrompt $expectedPrompt
        }
    }
}

function Invoke-RepositoryVerification {
    param([Parameter(Mandatory)] [string] $RepoRoot)

    $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
    $referencePath = Join-Path $repo 'results/derived/verification-reference.json'
    $reference = Get-Content -LiteralPath $referencePath -Raw | ConvertFrom-Json
    $identityTolerance = [double]$reference.tolerances.score_identity_absolute
    $statTolerance = [double]$reference.tolerances.statistic_absolute

    . (Join-Path $repo 'experiments/qwen3-4b/portable/logprob_helpers.ps1')

    $verifiedHashes = [System.Collections.Generic.List[object]]::new()
    foreach ($artifact in @($reference.artifacts)) {
        $path = Get-SafeRepositoryPath -RepoRoot $repo -RelativePath ([string]$artifact.path)
        $actual = Assert-ExactHash -Path $path -Expected ([string]$artifact.sha256) -Label ([string]$artifact.label)
        $verifiedHashes.Add([pscustomobject][ordered]@{ label = [string]$artifact.label; sha256 = $actual })
    }

    $schedule = Get-Content -LiteralPath (Join-Path $repo 'results/logprob/schedule.json') -Raw | ConvertFrom-Json
    $scores = @(Read-JsonLines -Path (Join-Path $repo 'results/logprob/condition_pair_scores.jsonl'))
    $scheduleRows = @($schedule.scoring_schedule)
    Assert-ExpectedCount $scheduleRows.Count ([int]$reference.logprob.rows) 'schedule rows'
    Assert-ExpectedCount $scores.Count ([int]$reference.logprob.rows) 'score rows'
    Assert-CompleteSchedule -ScheduleIds @($scheduleRows.schedule_id) -ScoreIds @($scores.schedule_id)

    $conditionIds = @($schedule.conditions.id)
    $pairIds = @($schedule.candidate_pair_screen | Where-Object retained | ForEach-Object pair_id)
    Assert-ExpectedCount @($conditionIds | Select-Object -Unique).Count ([int]$reference.logprob.conditions) 'unique conditions'
    Assert-ExpectedCount @($pairIds | Select-Object -Unique).Count ([int]$reference.logprob.pairs) 'unique retained pairs'
    foreach ($conditionId in $conditionIds) {
        foreach ($pairId in $pairIds) {
            Assert-ExpectedCount @($scores | Where-Object { $_.condition_id -eq $conditionId -and $_.pair_id -eq $pairId }).Count 1 "$conditionId/$pairId coverage"
        }
    }

    foreach ($row in $scores) {
        Assert-ValidLogprob -Value $row.even_logprob -Label "$($row.schedule_id)/even aggregate"
        Assert-ValidLogprob -Value $row.odd_logprob -Label "$($row.schedule_id)/odd aggregate"
        foreach ($candidate in @('even', 'odd')) {
            $tokenScores = @($row."${candidate}_token_scores")
            $tokenTotal = 0.0
            foreach ($tokenScore in $tokenScores) {
                Assert-ValidLogprob -Value $tokenScore.logprob -Label "$($row.schedule_id)/$candidate/token-$($tokenScore.token_position)"
                $tokenTotal += [double]$tokenScore.logprob
            }
            Assert-Close ([double]$row."${candidate}_logprob") $tokenTotal $identityTolerance "$($row.schedule_id) $candidate chain score mismatch"
        }
    }
    Assert-ScoreIdentities -Rows $scores -Tolerance $identityTolerance

    $validation = Get-Content -LiteralPath (Join-Path $repo 'results/logprob/validation.json') -Raw | ConvertFrom-Json
    if (-not [bool]$validation.passed) { throw 'Saved validation gate is not marked passed.' }
    Assert-ExpectedCount @($validation.checks | Where-Object { -not [bool]$_.passed }).Count 0 'saved failed validation checks'
    $recomputedValidation = Test-LogprobValidationGate `
        -Bias100Scores (ConvertTo-StringDoubleDictionary $validation.bias_100_scores) `
        -Bias1000Scores (ConvertTo-StringDoubleDictionary $validation.bias_1000_scores) `
        -ForwardScores (ConvertTo-StringDoubleDictionary $validation.forward_scores) `
        -ReverseScores (ConvertTo-StringDoubleDictionary $validation.reverse_scores) `
        -Tolerance ([double]$schedule.validation_tolerance)
    if (-not $recomputedValidation.passed) { throw 'Recomputed validation gate failed.' }
    foreach ($savedCheck in @($validation.checks)) {
        $fresh = @($recomputedValidation.checks | Where-Object name -eq $savedCheck.name)
        Assert-ExpectedCount $fresh.Count 1 "validation check $($savedCheck.name)"
        Assert-Close ([double]$fresh[0].delta) ([double]$savedCheck.delta) $identityTolerance "validation delta $($savedCheck.name) mismatch"
        if ([bool]$fresh[0].passed -ne [bool]$savedCheck.passed) { throw "validation result $($savedCheck.name) mismatch." }
    }

    $primary = Get-PrimaryLogprobEstimand -PairScores $scores -BootstrapSamples ([int]$reference.logprob.primary_bootstrap_samples) -BootstrapSeed ([int]$reference.logprob.primary_bootstrap_seed)
    Assert-Close $primary.primary_mean ([double]$reference.logprob.primary_did) $statTolerance 'primary DID mismatch'
    Assert-Close $primary.bootstrap_95_percent.lower ([double]$reference.logprob.primary_descriptive_interval[0]) $statTolerance 'primary descriptive interval lower mismatch'
    Assert-Close $primary.bootstrap_95_percent.upper ([double]$reference.logprob.primary_descriptive_interval[1]) $statTolerance 'primary descriptive interval upper mismatch'
    $negativePairs = @($primary.pair_level | Where-Object { [double]$_.averaged_did -lt 0 }).Count
    Assert-ExpectedCount $negativePairs ([int]$reference.logprob.negative_primary_pair_dids) 'negative primary pair DIDs'

    $secondary = Get-SecondaryLogprobEstimands -PairScores $scores -BootstrapSamples 1 -BootstrapSeed 20260823
    Assert-Close $secondary.conflict_current_minus_archived.averaged_mean ([double]$reference.logprob.conflict_current_minus_archived) $statTolerance 'conflict current-minus-archived mismatch'
    $transform = Get-TransformLogprobEstimands -PairScores $scores -BootstrapSamples 1 -BootstrapSeed 20260823
    Assert-Close $transform.causal_output_parity_reversal.mean ([double]$reference.logprob.transform_reversal) $statTolerance 'transform reversal mismatch'

    $userBoosts = [System.Collections.Generic.List[double]]::new()
    foreach ($pairId in $pairIds) {
        $pairRows = @($scores | Where-Object pair_id -eq $pairId)
        $conditionValue = {
            param([string] $id)
            $match = @($pairRows | Where-Object condition_id -eq $id)
            Assert-ExpectedCount $match.Count 1 "$pairId/$id post hoc row"
            [double]$match[0].requested_aligned_log_odds
        }
        $conflict = ((& $conditionValue 'core_request_even_reward_odd_current') - (& $conditionValue 'core_request_even_reward_odd_archived') +
            (& $conditionValue 'core_request_odd_reward_even_current') - (& $conditionValue 'core_request_odd_reward_even_archived')) / 2.0
        $congruent = ((& $conditionValue 'core_request_even_reward_even_current') - (& $conditionValue 'core_request_even_reward_even_archived') +
            (& $conditionValue 'core_request_odd_reward_odd_current') - (& $conditionValue 'core_request_odd_reward_odd_archived')) / 2.0
        $userBoosts.Add([double](($conflict + $congruent) / 2.0))
    }
    $postHocUserBoost = Get-Mean $userBoosts.ToArray()
    Assert-Close $postHocUserBoost ([double]$reference.logprob.post_hoc_overall_user_boost) $statTolerance 'post hoc overall user boost mismatch'
    $postHocSaved = Get-Content -LiteralPath (Join-Path $repo 'results/logprob/exploratory_user_alignment_decomposition.json') -Raw | ConvertFrom-Json
    if ([string]$postHocSaved.status -ne 'post_hoc_exploratory_decomposition') { throw 'Saved user-alignment decomposition lost its post hoc label.' }
    Assert-Close ([double]$postHocSaved.overall_user_current_minus_archived.mean) $postHocUserBoost $statTolerance 'saved post hoc user boost mismatch'

    $broadRows = @(Assert-BroadScreenEvidence -RepoRoot $repo -BroadScreenReference $reference.broad_screen)
    $broadValid = @($broadRows | Where-Object { [bool]$_.valid_integer })

    $behavioralSummary = [System.Collections.Generic.List[object]]::new()
    $mirroredCappedTrials = 0
    $mirroredCappedRewardAligned = 0
    $maximizeCappedTrials = 0
    $maximizeCappedRewardAligned = 0
    foreach ($block in @($reference.behavioral_blocks)) {
        $directory = Get-SafeRepositoryPath -RepoRoot $repo -RelativePath ([string]$block.directory)
        $results = @(Read-JsonLines -Path (Join-Path $directory 'results.jsonl'))
        $scheduleDocument = Get-Content -LiteralPath (Join-Path $directory 'schedule.json') -Raw | ConvertFrom-Json
        $scheduleTrials = if ($scheduleDocument -is [array]) { @($scheduleDocument) } else { @($scheduleDocument.trials) }
        $verifiedResults = @(Get-VerifiedBehavioralRecords -ScheduleDocument $scheduleDocument -ScheduleRows $scheduleTrials -ResultRows $results -BlockReference $block -RepoRoot $repo)
        $expectedBlockTrials = 0
        foreach ($cellProperty in $block.cells.PSObject.Properties) {
            $cellName = $cellProperty.Name
            $expected = $cellProperty.Value
            $cellRows = @($verifiedResults | Where-Object cell -eq $cellName)
            $validRows = @($cellRows | Where-Object { [bool]$_.valid_integer })
            $rewardRows = @($validRows | Where-Object { [bool]$_.reward_aligned })
            Assert-ExpectedCount $cellRows.Count ([int]$expected.trials) "$($block.name)/$cellName trials"
            Assert-ExpectedCount $validRows.Count ([int]$expected.valid) "$($block.name)/$cellName valid"
            Assert-ExpectedCount @($validRows | Where-Object { [bool]$_.user_compliance }).Count ([int]$expected.user_aligned) "$($block.name)/$cellName user alignment"
            Assert-ExpectedCount $rewardRows.Count ([int]$expected.reward_aligned) "$($block.name)/$cellName reward alignment"
            Assert-ExpectedCount @($validRows | Where-Object output_parity -eq 'odd').Count ([int]$expected.odd) "$($block.name)/$cellName odd"
            Assert-ExpectedCount @($validRows | Where-Object output_parity -eq 'even').Count ([int]$expected.even) "$($block.name)/$cellName even"
            if ([string]$block.name -eq 'mechanism capped thinking' -and $cellName -in @('higher_current', 'higher_reversed_conflict')) {
                $mirroredCappedTrials += $cellRows.Count
                $mirroredCappedRewardAligned += $rewardRows.Count
            }
            if ([string]$block.name -eq 'mechanism capped thinking' -and $cellName -eq 'maximize_current') {
                $maximizeCappedTrials += $cellRows.Count
                $maximizeCappedRewardAligned += $rewardRows.Count
            }
            $expectedBlockTrials += [int]$expected.trials
        }
        Assert-ExpectedCount $verifiedResults.Count $expectedBlockTrials "$($block.name) total"
        $null = Get-Content -LiteralPath (Join-Path $directory 'summary.json') -Raw | ConvertFrom-Json
        $behavioralSummary.Add([pscustomobject][ordered]@{ name = [string]$block.name; trials = $results.Count; cells = @($block.cells.PSObject.Properties).Count })
    }
    Assert-ExpectedCount $mirroredCappedTrials ([int]$reference.behavioral_aggregates.mirrored_capped_thinking_conflicts.trials) 'mirrored capped-thinking conflict trials'
    Assert-ExpectedCount $mirroredCappedRewardAligned ([int]$reference.behavioral_aggregates.mirrored_capped_thinking_conflicts.reward_aligned) 'mirrored capped-thinking conflict reward alignment'
    Assert-ExpectedCount $maximizeCappedTrials ([int]$reference.behavioral_aggregates.explicit_maximize_capped_thinking.trials) 'explicit-maximize capped-thinking trials'
    Assert-ExpectedCount $maximizeCappedRewardAligned ([int]$reference.behavioral_aggregates.explicit_maximize_capped_thinking.reward_aligned) 'explicit-maximize capped-thinking reward alignment'

    $collection = Get-Content -LiteralPath (Join-Path $repo 'provenance/collection-summary.original.json') -Raw | ConvertFrom-Json
    if ([string]$collection.status -ne [string]$reference.provenance.collection_status -or [string]$collection.fatal_error -ne [string]$reference.provenance.collection_fatal_error) {
        throw 'Collection summary does not preserve the expected post-collection failure.'
    }
    Assert-ExpectedCount ([int]$collection.planned_condition_pair_scores) ([int]$reference.logprob.rows) 'collection planned scores'
    Assert-ExpectedCount ([int]$collection.collected_condition_pair_scores) ([int]$reference.logprob.rows) 'collection collected scores'
    if (-not [bool]$collection.validation_passed -or -not [bool]$collection.full_gpu_offload_37_of_37) { throw 'Collection attestation is incomplete.' }

    $offlinePath = Join-Path $repo 'results/logprob/offline_finalization.json'
    Assert-ExactHash -Path $offlinePath -Expected ([string]$reference.provenance.offline_original_sha256) -Label 'offline finalization' | Out-Null
    Assert-ExactHash -Path (Join-Path $repo 'provenance/offline-finalization.original.json') -Expected ([string]$reference.provenance.offline_original_sha256) -Label 'original offline finalization' | Out-Null
    $offline = Get-Content -LiteralPath $offlinePath -Raw | ConvertFrom-Json
    if ([string]$offline.status -ne [string]$reference.provenance.offline_status -or [string]$offline.verification.status -ne 'verified_complete_inputs') {
        throw 'Offline finalization is not the authoritative completed record.'
    }
    Assert-ExpectedCount ([int]$offline.verification.collected_condition_pair_scores) ([int]$reference.logprob.rows) 'offline finalized scores'
    foreach ($artifact in @($reference.artifacts)) {
        $hashProperty = switch ([string]$artifact.label) {
            'schedule' { $offline.input_sha256.schedule }
            'validation' { $offline.input_sha256.validation }
            'condition pair scores' { $offline.input_sha256.scores }
            'raw responses' { $offline.input_sha256.raw }
            'collection summary' { $offline.input_sha256.collection_summary }
            'analysis JSON' { $offline.output_sha256.analysis_json }
            'analysis Markdown' { $offline.output_sha256.analysis_markdown }
        }
        if ($null -ne $hashProperty -and [string]$hashProperty -cne [string]$artifact.sha256) { throw "Offline finalization hash mismatch for $($artifact.label)." }
    }

    [pscustomobject][ordered]@{
        status = 'passed'
        hashes = $verifiedHashes.ToArray()
        logprob = [pscustomobject][ordered]@{
            rows = $scores.Count
            coverage = "$($conditionIds.Count)x$($pairIds.Count)"
            primary_did = $primary.primary_mean
            primary_interval_label = [string]$reference.labels.primary_interval
            primary_descriptive_interval = @($primary.bootstrap_95_percent.lower, $primary.bootstrap_95_percent.upper)
            negative_primary_pair_dids = "$negativePairs/$($pairIds.Count)"
            conflict_current_minus_archived = $secondary.conflict_current_minus_archived.averaged_mean
            transform_reversal = $transform.causal_output_parity_reversal.mean
            user_alignment_label = [string]$reference.labels.user_alignment
            post_hoc_overall_user_boost = $postHocUserBoost
        }
        broad_screen = [pscustomobject][ordered]@{ calls = $broadRows.Count; model_ids = @($broadRows.model | Select-Object -Unique).Count; strict_valid = $broadValid.Count; strict_valid_odd = @($broadValid | Where-Object output_parity -eq 'odd').Count }
        behavioral_blocks = $behavioralSummary.ToArray()
        mirrored_capped_thinking_conflict_reward_alignment = "$mirroredCappedRewardAligned/$mirroredCappedTrials"
        explicit_maximize_capped_thinking_reward_alignment = "$maximizeCappedRewardAligned/$maximizeCappedTrials"
        collection = 'failed only after 112/112 scores'
        finalization = 'authoritative offline completion verified'
    }
}
