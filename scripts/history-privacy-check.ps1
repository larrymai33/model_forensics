[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [string] $ExpectedAuthorName,
    [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [string] $ExpectedAuthorEmail,
    [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [string[]] $Ref,
    [string] $RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'privacy_helpers.ps1')

$repo = [System.IO.Path]::GetFullPath($RepoRoot)
$violations = 0
$resolvedTips = [System.Collections.Generic.List[string]]::new()

try {
    foreach ($refName in $Ref) {
        $resolved = Invoke-GitByteCommand -RepoRoot $repo -Arguments @('rev-parse', '--verify', '--end-of-options', "${refName}^{commit}")
        $objectId = (ConvertFrom-StrictUtf8 -Bytes $resolved.Bytes -Label "Resolved ref $refName").Trim()
        if ($objectId -cnotmatch '^[0-9a-f]{40,64}$') { throw "Ref did not resolve to a commit: $refName" }
        $resolvedTips.Add($objectId)
    }

    $commitResult = Invoke-GitByteCommand -RepoRoot $repo -Arguments (@('rev-list') + $resolvedTips.ToArray() + @('--'))
    $commitIds = @((ConvertFrom-StrictUtf8 -Bytes $commitResult.Bytes -Label 'Reachable commit listing') -split '\r?\n' | Where-Object { $_ })
    if ($commitIds.Count -eq 0) { throw 'No commits are reachable from the intended push refs.' }

    $blobPaths = @{}
    foreach ($commitId in $commitIds) {
        $identityResult = Invoke-GitByteCommand -RepoRoot $repo -Arguments @('show', '-s', '--format=%an%x00%ae%x00%cn%x00%ce', $commitId)
        $identityText = (ConvertFrom-StrictUtf8 -Bytes $identityResult.Bytes -Label "Commit identity $commitId").TrimEnd("`r", "`n")
        $identity = @($identityText -split "`0", 4)
        if ($identity.Count -ne 4) { throw "Unable to parse author and committer identity for $commitId." }
        if ($identity[0] -cne $ExpectedAuthorName -or $identity[1] -cne $ExpectedAuthorEmail -or
            $identity[2] -cne $ExpectedAuthorName -or $identity[3] -cne $ExpectedAuthorEmail) {
            Write-Host "VIOLATION: Commit identity is not the approved release identity: $commitId"
            $violations++
        }

        $treeResult = Invoke-GitByteCommand -RepoRoot $repo -Arguments @('ls-tree', '-r', '-z', '--full-tree', $commitId)
        $treeText = ConvertFrom-StrictUtf8 -Bytes $treeResult.Bytes -Label "Tree listing $commitId"
        foreach ($treeEntry in ($treeText -split "`0")) {
            if (-not $treeEntry) { continue }
            $match = [regex]::Match($treeEntry, '^(?<mode>\d+) (?<type>\w+) (?<oid>[0-9a-f]+)\t(?<path>[\s\S]+)$')
            if (-not $match.Success) { throw "Malformed tree entry in $commitId." }
            if ($match.Groups['type'].Value -cne 'blob') { continue }
            $objectId = $match.Groups['oid'].Value
            $path = $match.Groups['path'].Value
            if (-not $blobPaths.ContainsKey($objectId)) {
                $blobPaths[$objectId] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            }
            $null = $blobPaths[$objectId].Add($path)
        }
    }

    $pathPairs = 0
    foreach ($objectId in @($blobPaths.Keys | Sort-Object)) {
        $paths = @($blobPaths[$objectId] | Sort-Object)
        foreach ($path in $paths) {
            $pathPairs++
            if (Test-ForbiddenPublicationPath -RelativePath $path) {
                Write-Host "VIOLATION: Forbidden reachable path: $path (blob $objectId)"
                $violations++
            }
        }

        $blobSize = Get-GitBlobSize -RepoRoot $repo -ObjectId $objectId
        if ($blobSize -gt 10MB) {
            Write-Host "VIOLATION: Reachable blob exceeds 10 MiB: $objectId ($blobSize bytes; paths: $($paths -join ', '))"
            $violations++
            continue
        }

        $textPaths = @($paths | Where-Object { [System.IO.Path]::GetExtension($_) -notin @('.png', '.docx') })
        if ($textPaths.Count -eq 0) { continue }
        try {
            $content = Get-GitBlobText -RepoRoot $repo -ObjectId $objectId -Label "Reachable blob $objectId"
            if (Test-SensitivePublicationText -Text $content) {
                Write-Host "VIOLATION: Sensitive reachable blob text: $objectId (paths: $($textPaths -join ', '))"
                $violations++
            }
        }
        catch {
            Write-Host "VIOLATION: Unable to scan reachable text blob: $objectId ($($_.Exception.Message))"
            $violations++
        }
    }

    Write-Host "History privacy check: $($commitIds.Count) commit(s), $($blobPaths.Count) unique blob(s), $pathPairs blob/path pair(s), $violations violation(s)."
    if ($violations -gt 0) { exit 1 }
    exit 0
}
catch {
    Write-Error "History privacy check failed: $($_.Exception.Message)"
    exit 1
}
