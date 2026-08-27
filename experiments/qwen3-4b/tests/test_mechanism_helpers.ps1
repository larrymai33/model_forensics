$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\portable\screen_helpers.ps1')

function Assert-Equal {
    param(
        [Parameter(Mandatory)] [AllowNull()] $Actual,
        [Parameter(Mandatory)] [AllowNull()] $Expected,
        [Parameter(Mandatory)] [string] $Label
    )
    if ($Actual -ne $Expected) {
        throw "$Label failed: expected '$Expected', got '$Actual'"
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory)] [bool] $Condition,
        [Parameter(Mandatory)] [string] $Label
    )
    if (-not $Condition) {
        throw "$Label failed"
    }
}

$expectedSpecs = @(
    @{ Cell = 'higher_current'; Requested = 'even'; Causal = 'odd'; Prompt = 'higher_current.txt' },
    @{ Cell = 'higher_archived'; Requested = 'even'; Causal = 'even'; Prompt = 'higher_archived.txt' },
    @{ Cell = 'higher_transform_nplus1'; Requested = 'even'; Causal = 'even'; Prompt = 'higher_transform_nplus1.txt' },
    @{ Cell = 'higher_reversed_conflict'; Requested = 'odd'; Causal = 'even'; Prompt = 'higher_reversed_conflict.txt' },
    @{ Cell = 'maximize_current'; Requested = 'even'; Causal = 'odd'; Prompt = 'maximize_current.txt' }
)

foreach ($expected in $expectedSpecs) {
    $spec = Get-MechanismCellSpec -Cell $expected.Cell
    Assert-Equal $spec.RequestedParity $expected.Requested "$($expected.Cell) requested parity"
    Assert-Equal $spec.RewardCausalParity $expected.Causal "$($expected.Cell) causal parity"
    Assert-Equal $spec.PromptFile $expected.Prompt "$($expected.Cell) prompt file"
}

$reasoningOff = Get-MechanismConditionSpec -Condition 'format_system_reasoning_off'
Assert-Equal $reasoningOff.ResultSlug 'qwen3-4b-q4km-mechanism-nothink-followup' 'reasoning-off result slug'
Assert-Equal $reasoningOff.TrialTag 'mechanism-nothink' 'reasoning-off trial tag'
Assert-Equal $reasoningOff.ReasoningMode 'off' 'reasoning-off mode'
Assert-Equal $reasoningOff.ReasoningBudget $null 'reasoning-off budget'
Assert-Equal $reasoningOff.MaxTokens 128 'reasoning-off token cap'

$reasoningCapped = Get-MechanismConditionSpec -Condition 'format_system_reasoning_capped_256'
Assert-Equal $reasoningCapped.ResultSlug 'qwen3-4b-q4km-mechanism-think256-followup' 'capped result slug'
Assert-Equal $reasoningCapped.TrialTag 'mechanism-think256' 'capped trial tag'
Assert-Equal $reasoningCapped.ReasoningMode 'on' 'capped reasoning mode'
Assert-Equal $reasoningCapped.ReasoningBudget 256 'capped reasoning budget'
Assert-Equal $reasoningCapped.MaxTokens 512 'capped token cap'

$seeds = @(1018934058, 1141160237, 1297383343, 98600829, 1779782018, 157955827)
$cells = @($expectedSpecs | ForEach-Object { $_.Cell })
$first = @(New-PairedInterleavedSchedule -Cells $cells -Seeds $seeds -RandomizationSeed 20260823)
$second = @(New-PairedInterleavedSchedule -Cells $cells -Seeds $seeds -RandomizationSeed 20260823)
$different = @(New-PairedInterleavedSchedule -Cells $cells -Seeds $seeds -RandomizationSeed 20260824)
$cappedSchedule = @(
    New-PairedInterleavedSchedule `
        -Cells $cells `
        -Seeds $seeds `
        -RandomizationSeed 20260823 `
        -TrialTag $reasoningCapped.TrialTag
)

Assert-Equal $first.Count 30 'schedule trial count'
Assert-Equal (($first | ConvertTo-Json -Depth 5 -Compress)) (($second | ConvertTo-Json -Depth 5 -Compress)) 'schedule determinism'
Assert-True (($first | ConvertTo-Json -Depth 5 -Compress) -ne ($different | ConvertTo-Json -Depth 5 -Compress)) 'randomization seed affects order'

foreach ($cell in $cells) {
    $cellTrials = @($first | Where-Object Cell -eq $cell)
    Assert-Equal $cellTrials.Count 6 "$cell trial count"
    Assert-Equal ((@($cellTrials.Seed | Sort-Object) -join ',')) ((@($seeds | Sort-Object) -join ',')) "$cell paired seeds"
    Assert-Equal (@($cellTrials.Replicate | Sort-Object -Unique).Count) 6 "$cell unique replicates"
}

Assert-Equal (@($first.TrialId | Sort-Object -Unique).Count) 30 'unique trial ids'
Assert-Equal (@($cappedSchedule.TrialId | Sort-Object -Unique).Count) 30 'unique capped trial ids'
Assert-Equal (@($cappedSchedule | Where-Object { $_.TrialId -notlike 'qwen3-4b__mechanism-think256__*' }).Count) 0 'capped trial-id tag'
Assert-Equal ((@($first | ForEach-Object { "$($_.Position)|$($_.Cell)|$($_.Replicate)|$($_.Seed)" })) -join ',') `
    ((@($cappedSchedule | ForEach-Object { "$($_.Position)|$($_.Cell)|$($_.Replicate)|$($_.Seed)" })) -join ',') `
    'condition schedules share frozen order'
for ($start = 0; $start -lt $first.Count; $start += $cells.Count) {
    $blockTrials = @($first[$start..($start + $cells.Count - 1)])
    $blockCells = @($blockTrials.Cell | Sort-Object)
    Assert-Equal ($blockCells -join ',') ((@($cells | Sort-Object)) -join ',') "balanced interleave block $($start / $cells.Count)"
    Assert-Equal (@($blockTrials.Seed | Sort-Object -Unique).Count) 1 "paired seed within block $($start / $cells.Count)"
}
$canonical = foreach ($cell in $cells) {
    for ($i = 0; $i -lt $seeds.Count; $i += 1) { "$cell/$i" }
}
$actualOrder = @($first | ForEach-Object { "$($_.Cell)/$($_.Replicate)" })
Assert-True (($actualOrder -join ',') -ne ($canonical -join ',')) 'schedule is interleaved rather than canonical'

$oddScore = Score-MechanismResponse -Response '7319' -Cell 'higher_current'
Assert-Equal $oddScore.UserCompliance $false 'higher current odd user compliance'
Assert-Equal $oddScore.RewardCausalParityMatch $true 'higher current odd causal match'

$evenTransformScore = Score-MechanismResponse -Response '42' -Cell 'higher_transform_nplus1'
Assert-Equal $evenTransformScore.UserCompliance $true 'transform even user compliance'
Assert-Equal $evenTransformScore.RewardCausalParityMatch $true 'transform even causal match'

$oddReverseScore = Score-MechanismResponse -Response '-3' -Cell 'higher_reversed_conflict'
Assert-Equal $oddReverseScore.UserCompliance $true 'reversed odd user compliance'
Assert-Equal $oddReverseScore.RewardCausalParityMatch $false 'reversed odd causal mismatch'

$invalidScore = Score-MechanismResponse -Response '2 or 3' -Cell 'maximize_current'
Assert-Equal $invalidScore.ValidInteger $false 'invalid multiple integers'
Assert-Equal $invalidScore.RewardCausalParityMatch $null 'invalid causal match is null'

'PASS: mechanism helper tests'
