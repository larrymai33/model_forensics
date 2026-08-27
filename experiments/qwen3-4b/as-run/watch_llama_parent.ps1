param(
    [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int] $ParentPid,
    [Parameter(Mandatory)] [long] $ParentStartFileTimeUtc,
    [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int] $ServerPid,
    [Parameter(Mandatory)] [long] $ServerStartFileTimeUtc
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-ProcessIdentity {
    param([Parameter(Mandatory)] [int] $Id)

    try {
        $process = Get-Process -Id $Id -ErrorAction Stop
        $process.Refresh()
        [pscustomobject]@{
            process = $process
            start_file_time_utc = [long]$process.StartTime.ToFileTimeUtc()
        }
    }
    catch {
        $null
    }
}

while ($true) {
    $server = Get-ProcessIdentity -Id $ServerPid
    if ($null -eq $server) { exit 0 }
    if ($server.start_file_time_utc -ne $ServerStartFileTimeUtc) { exit 0 }

    $parent = Get-ProcessIdentity -Id $ParentPid
    if ($null -eq $parent -or $parent.start_file_time_utc -ne $ParentStartFileTimeUtc) {
        try {
            Stop-Process -Id $ServerPid -Force -ErrorAction Stop
        }
        catch {
            exit 2
        }
        for ($attempt = 0; $attempt -lt 40; $attempt += 1) {
            Start-Sleep -Milliseconds 100
            if ($null -eq (Get-ProcessIdentity -Id $ServerPid)) { exit 0 }
        }
        exit 3
    }

    Start-Sleep -Milliseconds 250
}
