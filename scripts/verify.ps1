$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot

function Invoke-CheckedCommand {
    param([string] $Label, [string] $Executable, [string[]] $Arguments)
    Write-Host "VERIFY $Label"
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE." }
}

try {
    Invoke-CheckedCommand 'broad-screen Python tests' 'python' @('-m', 'unittest', 'discover', '-s', (Join-Path $repoRoot 'experiments/broad-screen/tests'), '-v')
    Invoke-CheckedCommand 'dependency-free report builder safety tests' 'python' @('-m', 'unittest', 'discover', '-s', (Join-Path $repoRoot 'report/tests'), '-p', 'test_build_report.py', '-v')
    Invoke-CheckedCommand 'broad-screen sanitizer tests' 'pwsh' @('-NoProfile', '-File', (Join-Path $repoRoot 'scripts/tests/test_sanitize_candidate_screen.ps1'))
    Invoke-CheckedCommand 'privacy helper tests' 'pwsh' @('-NoProfile', '-File', (Join-Path $repoRoot 'scripts/tests/test_privacy_helpers.ps1'))
    Invoke-CheckedCommand 'Git index privacy integration tests' 'pwsh' @('-NoProfile', '-File', (Join-Path $repoRoot 'scripts/tests/test_privacy_check.ps1'))
    Invoke-CheckedCommand 'release history privacy tests' 'pwsh' @('-NoProfile', '-File', (Join-Path $repoRoot 'scripts/tests/test_history_privacy_check.ps1'))
    Invoke-CheckedCommand 'Qwen screen helper tests' 'pwsh' @('-NoProfile', '-File', (Join-Path $repoRoot 'experiments/qwen3-4b/tests/test_screen_helpers.ps1'))
    Invoke-CheckedCommand 'Qwen mechanism helper tests' 'pwsh' @('-NoProfile', '-File', (Join-Path $repoRoot 'experiments/qwen3-4b/tests/test_mechanism_helpers.ps1'))
    Invoke-CheckedCommand 'Qwen logprob helper tests (15)' 'pwsh' @('-NoProfile', '-File', (Join-Path $repoRoot 'experiments/qwen3-4b/tests/test_logprob_helpers.ps1'))
    Invoke-CheckedCommand 'repository verifier helper tests' 'pwsh' @('-NoProfile', '-File', (Join-Path $repoRoot 'scripts/tests/test_verify_helpers.ps1'))

    . (Join-Path $PSScriptRoot 'verify_helpers.ps1')
    $summary = Invoke-RepositoryVerification -RepoRoot $repoRoot

    Invoke-CheckedCommand 'privacy and 10 MiB gate' 'pwsh' @('-NoProfile', '-File', (Join-Path $repoRoot 'scripts/privacy-check.ps1'))
    $summary | Add-Member -NotePropertyName privacy_gate -NotePropertyValue 'passed'
    Write-Host 'VERIFICATION_SUMMARY'
    $summary | ConvertTo-Json -Depth 10
    exit 0
}
catch {
    Write-Error "Repository verification failed: $($_.Exception.Message)"
    exit 1
}
