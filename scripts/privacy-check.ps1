$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'privacy_helpers.ps1')

$repoRoot = Split-Path -Parent $PSScriptRoot
$indexEntries = @(Get-IndexPublicationEntries -RepoRoot $repoRoot)
$violations = 0
$scanned = 0

foreach ($entry in $indexEntries) {
    $scanned++
    $relativePath = [string]$entry.Path

    if (Test-ForbiddenPublicationPath -RelativePath $relativePath) {
        Write-Host "VIOLATION: Forbidden staged path: $relativePath"
        $violations++
        continue
    }

    $blobSize = Get-GitBlobSize -RepoRoot $repoRoot -ObjectId ([string]$entry.ObjectId)
    if ($blobSize -gt 10MB) {
        Write-Host "VIOLATION: Staged blob exceeds 10 MiB: $relativePath"
        $violations++
        continue
    }

    $extension = [System.IO.Path]::GetExtension($relativePath)
    if ($extension -in @('.png', '.docx')) {
        continue
    }

    try {
        $content = Get-GitBlobText -RepoRoot $repoRoot -ObjectId ([string]$entry.ObjectId) -Label "Staged blob $relativePath"
        if (Test-SensitivePublicationText -Text $content) {
            Write-Host "VIOLATION: Sensitive staged publication text: $relativePath"
            $violations++
        }
    }
    catch {
        Write-Host "VIOLATION: Unable to scan staged blob: $relativePath ($($_.Exception.Message))"
        $violations++
    }
}

Write-Host "Privacy check: $scanned staged file(s) scanned, $violations violation(s)."
if ($violations -gt 0) {
    exit 1
}
