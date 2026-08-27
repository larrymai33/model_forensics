$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sanitizer = Join-Path $repoRoot 'scripts\sanitize_candidate_screen.ps1'
$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
$inputPath = Join-Path $temporaryDirectory 'candidate-input.jsonl'
$outputPath = Join-Path $temporaryDirectory 'candidate-output.jsonl'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

function Test-RecursiveProperty {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Value,
        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            if ($key -eq $PropertyName -or (Test-RecursiveProperty -Value $Value[$key] -PropertyName $PropertyName)) {
                return $true
            }
        }
    }
    elseif ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        foreach ($item in $Value) {
            if (Test-RecursiveProperty -Value $item -PropertyName $PropertyName) {
                return $true
            }
        }
    }

    return $false
}

try {
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
    $providerMetadata = 'provider' + '_metadata'
    $threadKey = 'thread' + '_id'
    $fixture = [ordered]@{
        response = 42
        nullable = $null
        $providerMetadata = [ordered]@{
            usage = [ordered]@{ tokens = 2 }
            nested = [ordered]@{
                $threadKey = 'fixture-thread'
            }
        }
    }
    $fixture | ConvertTo-Json -Depth 10 -Compress | Set-Content -LiteralPath $inputPath -Encoding utf8NoBOM

    & $sanitizer -InputPath $inputPath -OutputPath $outputPath

    $record = (Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -AsHashtable)
    Assert-True ($record.response -eq 42) 'response must be preserved'
    Assert-True ($record.ContainsKey('nullable') -and $null -eq $record.nullable) 'null fields must be preserved'
    Assert-True ($record[$providerMetadata].usage.tokens -eq 2) 'usage tokens must be preserved'
    Assert-True (-not (Test-RecursiveProperty -Value $record -PropertyName $threadKey)) 'provider thread IDs must be removed recursively'
}
finally {
    if (Test-Path -LiteralPath $temporaryDirectory) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
}

Write-Host 'PASS: candidate-screen sanitizer regression'
