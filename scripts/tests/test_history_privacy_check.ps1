$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:Passed = 0
$script:Failed = 0
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$historyScript = Join-Path $repoRoot 'scripts/history-privacy-check.ps1'
$approvedName = 'Sanitized Release'
$approvedEmail = 'release' + '@example.invalid'

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

function Assert-Equal {
    param($Actual, $Expected, [string] $Message)
    if ($Actual -ne $Expected) { throw "$Message (actual=$Actual expected=$Expected)" }
}

function New-HistoryFixtureRepository {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "privacy-history-$PID-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    & git -C $root init --quiet --initial-branch=main
    if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize history fixture repository.' }
    & git -C $root config user.name $approvedName
    & git -C $root config user.email $approvedEmail
    $root
}

function Add-HistoryFixtureCommit {
    param([string] $Root, [string] $Message)
    & git -C $Root add --all
    if ($LASTEXITCODE -ne 0) { throw 'Unable to stage history fixture.' }
    & git -C $Root commit --quiet -m $Message
    if ($LASTEXITCODE -ne 0) { throw 'Unable to commit history fixture.' }
}

function Invoke-HistoryFixture {
    param([string] $Root)
    $output = @(& pwsh -NoProfile -File $historyScript -RepoRoot $Root -Ref refs/heads/main -ExpectedAuthorName $approvedName -ExpectedAuthorEmail $approvedEmail 2>&1)
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
}

Test-Case 'history gate accepts reachable blobs and commits with approved release identity' {
    $root = New-HistoryFixtureRepository
    try {
        [System.IO.File]::WriteAllText((Join-Path $root 'README.md'), 'safe release', [System.Text.UTF8Encoding]::new($false))
        Add-HistoryFixtureCommit -Root $root -Message 'safe root'
        $result = Invoke-HistoryFixture -Root $root
        Assert-Equal $result.ExitCode 0 "safe release history must pass: $($result.Output)"
    }
    finally {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}

Test-Case 'history gate rejects a reachable commit with unapproved identity' {
    $root = New-HistoryFixtureRepository
    try {
        & git -C $root config user.email ('personal' + '@example.com')
        [System.IO.File]::WriteAllText((Join-Path $root 'README.md'), 'safe release', [System.Text.UTF8Encoding]::new($false))
        Add-HistoryFixtureCommit -Root $root -Message 'personal root'
        $result = Invoke-HistoryFixture -Root $root
        Assert-Equal $result.ExitCode 1 'unapproved reachable identity must fail'
    }
    finally {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}

Test-Case 'history gate rejects sensitive text removed from the current tree' {
    $root = New-HistoryFixtureRepository
    try {
        $secret = 'Authorization: ' + ('Bear' + 'er') + ' historical-secret'
        [System.IO.File]::WriteAllText((Join-Path $root 'note.txt'), $secret, [System.Text.UTF8Encoding]::new($false))
        Add-HistoryFixtureCommit -Root $root -Message 'historical secret'
        [System.IO.File]::WriteAllText((Join-Path $root 'note.txt'), 'safe now', [System.Text.UTF8Encoding]::new($false))
        Add-HistoryFixtureCommit -Root $root -Message 'sanitize tip'
        $result = Invoke-HistoryFixture -Root $root
        Assert-Equal $result.ExitCode 1 'reachable historical secret must fail'
    }
    finally {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}

Test-Case 'history gate applies forbidden-path rules to removed paths' {
    $root = New-HistoryFixtureRepository
    try {
        $models = Join-Path $root 'models'
        New-Item -ItemType Directory -Path $models -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $models 'fixture.gguf'), 'small model fixture', [System.Text.UTF8Encoding]::new($false))
        Add-HistoryFixtureCommit -Root $root -Message 'historical forbidden path'
        Remove-Item -LiteralPath $models -Recurse -Force
        [System.IO.File]::WriteAllText((Join-Path $root 'README.md'), 'safe now', [System.Text.UTF8Encoding]::new($false))
        Add-HistoryFixtureCommit -Root $root -Message 'remove forbidden path'
        $result = Invoke-HistoryFixture -Root $root
        Assert-Equal $result.ExitCode 1 'reachable forbidden historical path must fail'
    }
    finally {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}

Test-Case 'history gate applies size limit to removed blobs' {
    $root = New-HistoryFixtureRepository
    try {
        [System.IO.File]::WriteAllBytes((Join-Path $root 'large.bin'), [byte[]]::new(11MB))
        Add-HistoryFixtureCommit -Root $root -Message 'historical oversized blob'
        Remove-Item -LiteralPath (Join-Path $root 'large.bin') -Force
        [System.IO.File]::WriteAllText((Join-Path $root 'README.md'), 'safe now', [System.Text.UTF8Encoding]::new($false))
        Add-HistoryFixtureCommit -Root $root -Message 'remove oversized blob'
        $result = Invoke-HistoryFixture -Root $root
        Assert-Equal $result.ExitCode 1 'reachable oversized historical blob must fail'
    }
    finally {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}

Write-Host "RESULT passed=$script:Passed failed=$script:Failed"
if ($script:Failed -gt 0) { exit 1 }
