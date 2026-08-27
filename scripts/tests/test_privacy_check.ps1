$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:Passed = 0
$script:Failed = 0
$sourceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

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

function Assert-ExitCode {
    param([int] $Actual, [int] $Expected, [string] $Message)
    if ($Actual -ne $Expected) { throw "$Message (actual=$Actual expected=$Expected)" }
}

function New-PrivacyFixtureRepository {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "privacy-index-$PID-$([guid]::NewGuid().ToString('N'))"
    $scripts = Join-Path $root 'scripts'
    New-Item -ItemType Directory -Path $scripts -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'scripts/privacy-check.ps1') -Destination $scripts
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'scripts/privacy_helpers.ps1') -Destination $scripts
    & git -C $root init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize privacy fixture repository.' }
    [System.IO.File]::WriteAllText((Join-Path $root 'note.txt'), 'safe publication text', [System.Text.UTF8Encoding]::new($false))
    & git -C $root add note.txt
    if ($LASTEXITCODE -ne 0) { throw 'Unable to stage privacy fixture.' }
    $root
}

function Invoke-PrivacyFixture {
    param([string] $Root)
    & pwsh -NoProfile -File (Join-Path $Root 'scripts/privacy-check.ps1') *> $null
    $LASTEXITCODE
}

Test-Case 'privacy gate reads staged blob instead of dirty worktree bytes' {
    $root = New-PrivacyFixtureRepository
    try {
        $secret = 'Authorization: ' + ('Bear' + 'er') + ' dirty-worktree-secret'
        [System.IO.File]::WriteAllText((Join-Path $root 'note.txt'), $secret, [System.Text.UTF8Encoding]::new($false))
        Assert-ExitCode (Invoke-PrivacyFixture -Root $root) 0 'safe staged blob must pass despite dirty secret worktree bytes'

        & git -C $root add note.txt
        if ($LASTEXITCODE -ne 0) { throw 'Unable to stage secret fixture.' }
        Assert-ExitCode (Invoke-PrivacyFixture -Root $root) 1 'staged secret blob must fail'
    }
    finally {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}

Test-Case 'privacy gate reads staged blob size instead of dirty worktree size' {
    $root = New-PrivacyFixtureRepository
    try {
        [System.IO.File]::WriteAllBytes((Join-Path $root 'note.txt'), [byte[]]::new(11MB))
        Assert-ExitCode (Invoke-PrivacyFixture -Root $root) 0 'small staged blob must pass despite oversized dirty worktree bytes'

        & git -C $root add note.txt
        if ($LASTEXITCODE -ne 0) { throw 'Unable to stage oversized fixture.' }
        Assert-ExitCode (Invoke-PrivacyFixture -Root $root) 1 'oversized staged blob must fail'
    }
    finally {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}

Test-Case 'privacy gate preserves PNG and DOCX text-scan exemptions' {
    $root = New-PrivacyFixtureRepository
    try {
        $secret = [System.Text.Encoding]::UTF8.GetBytes('Authorization: ' + ('Bear' + 'er') + ' binary-fixture-secret')
        [System.IO.File]::WriteAllBytes((Join-Path $root 'figure.png'), $secret)
        [System.IO.File]::WriteAllBytes((Join-Path $root 'report.docx'), $secret)
        & git -C $root add figure.png report.docx
        if ($LASTEXITCODE -ne 0) { throw 'Unable to stage binary fixture.' }
        Assert-ExitCode (Invoke-PrivacyFixture -Root $root) 0 'PNG and DOCX blobs must remain exempt from text scanning'
    }
    finally {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}

Write-Host "RESULT passed=$script:Passed failed=$script:Failed"
if ($script:Failed -gt 0) { exit 1 }
