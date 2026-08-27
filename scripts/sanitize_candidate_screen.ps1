[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Remove-ProviderThreadIds {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Value
    )

    $threadKey = 'thread' + '_id'
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in @($Value.Keys)) {
            if ([string]$key -eq $threadKey) {
                $Value.Remove($key)
            }
            else {
                Remove-ProviderThreadIds -Value $Value[$key]
            }
        }
        return
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        foreach ($item in $Value) {
            Remove-ProviderThreadIds -Value $item
        }
    }
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory) {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$reader = [System.IO.File]::OpenText($InputPath)
$writer = [System.IO.StreamWriter]::new($OutputPath, $false, $utf8NoBom)

try {
    while (($line = $reader.ReadLine()) -ne $null) {
        if (-not $line.Trim()) {
            continue
        }

        $record = $line | ConvertFrom-Json -AsHashtable -Depth 100
        Remove-ProviderThreadIds -Value $record
        $writer.WriteLine(($record | ConvertTo-Json -Compress -Depth 100))
    }
}
finally {
    $reader.Dispose()
    $writer.Dispose()
}
