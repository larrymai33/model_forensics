function Get-TrackedPublicationFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    Get-IndexPublicationEntries -RepoRoot $RepoRoot | ForEach-Object Path
}

function Invoke-GitByteCommand {
    param(
        [Parameter(Mandatory = $true)] [string] $RepoRoot,
        [Parameter(Mandatory = $true)] [string[]] $Arguments
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'git'
    $startInfo.WorkingDirectory = [System.IO.Path]::GetFullPath($RepoRoot)
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $null = $startInfo.ArgumentList.Add($argument) }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $output = [System.IO.MemoryStream]::new()
    try {
        if (-not $process.Start()) { throw 'Git process did not start.' }
        $outputTask = $process.StandardOutput.BaseStream.CopyToAsync($output)
        $errorTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $outputTask.GetAwaiter().GetResult() | Out-Null
        $errorText = $errorTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "git $($Arguments[0]) failed with exit code $($process.ExitCode): $($errorText.Trim())"
        }
        [pscustomobject]@{
            Bytes = $output.ToArray()
            ErrorText = $errorText
        }
    }
    finally {
        $output.Dispose()
        $process.Dispose()
    }
}

function ConvertFrom-StrictUtf8 {
    param(
        [Parameter(Mandatory = $true)] [byte[]] $Bytes,
        [Parameter(Mandatory = $true)] [string] $Label
    )
    try { [System.Text.UTF8Encoding]::new($false, $true).GetString($Bytes) }
    catch { throw "$Label is not valid UTF-8 text." }
}

function Get-IndexPublicationEntries {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $result = Invoke-GitByteCommand -RepoRoot $RepoRoot -Arguments @('ls-files', '--stage', '-z')
    $listing = ConvertFrom-StrictUtf8 -Bytes $result.Bytes -Label 'Git index listing'
    $seen = @{}
    foreach ($entry in ($listing -split "`0")) {
        if (-not $entry) { continue }
        $match = [regex]::Match($entry, '^(?<mode>\d+) (?<oid>[0-9a-fA-F]+) (?<stage>\d+)\t(?<path>[\s\S]+)$')
        if (-not $match.Success) { throw "Malformed Git index entry: $entry" }
        $stage = [int]$match.Groups['stage'].Value
        $path = $match.Groups['path'].Value
        if ($stage -ne 0) { throw "Unmerged Git index entry is not publishable: $path (stage $stage)." }
        if ($seen.ContainsKey($path)) { throw "Duplicate Git index path: $path" }
        $seen[$path] = $true
        [pscustomobject]@{
            Path = $path
            ObjectId = $match.Groups['oid'].Value.ToLowerInvariant()
            Mode = $match.Groups['mode'].Value
        }
    }
}

function Get-GitBlobSize {
    param(
        [Parameter(Mandatory = $true)] [string] $RepoRoot,
        [Parameter(Mandatory = $true)] [string] $ObjectId
    )
    $result = Invoke-GitByteCommand -RepoRoot $RepoRoot -Arguments @('cat-file', '-s', $ObjectId)
    $text = ConvertFrom-StrictUtf8 -Bytes $result.Bytes -Label "Git object size for $ObjectId"
    $size = 0L
    if (-not [long]::TryParse($text.Trim(), [ref]$size) -or $size -lt 0) {
        throw "Git returned an invalid blob size for $ObjectId."
    }
    $size
}

function Get-GitBlobText {
    param(
        [Parameter(Mandatory = $true)] [string] $RepoRoot,
        [Parameter(Mandatory = $true)] [string] $ObjectId,
        [Parameter(Mandatory = $true)] [string] $Label
    )
    $result = Invoke-GitByteCommand -RepoRoot $RepoRoot -Arguments @('cat-file', 'blob', $ObjectId)
    ConvertFrom-StrictUtf8 -Bytes $result.Bytes -Label $Label
}

function Test-ForbiddenPublicationPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $path = $RelativePath.Replace('\', '/').TrimStart('/')
    if ($path -match '(?i)\.(gguf|pyc|zip|7z|dll|exe)$') {
        return $true
    }

    return $path -match '(?i)(^|/)(runtime|downloads|process-cache|logs|__pycache__|\.serena|\.env(?:\.[^/]+)?|cache|\.cache|models?|local-manifests|tmp-clone|temp-clone|[^/]*-clone|[^/]*manifest\.local[^/]*|(?=[^/]*32b)(?=[^/]*incomplete)[^/]+|[^/]*(credential|token)[^/]*)(/|$)'
}

function Test-SensitivePublicationText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $threadId = [regex]::Escape(('thread' + '_id'))
    $patterns = @(
        ('(?i)["'']?' + $threadId + '["'']?\s*:'),
        '(?i)\b[A-Z]:[\\/]+Users(?:[\\/]|$)',
        '(?i)-----BEGIN(?: [A-Z0-9]+)* PRIVATE KEY-----',
        '(?i)\bBearer\s+\S+',
        '(?i)\b[A-Z0-9_]*(api[_-]?key|access[_-]?token|auth[_-]?token|secret[_-]?key|client[_-]?secret|password)\b\s*[:=]\s*["'']?\S+',
        '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'
    )

    foreach ($pattern in $patterns) {
        if ($Text -match $pattern) {
            return $true
        }
    }

    return $false
}
