$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'privacy_helpers.ps1')

$script:Failures = 0

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        $script:Failures++
        Write-Error "FAIL: $Message"
    }
}

Assert-True (Test-ForbiddenPublicationPath 'models/model.gguf') 'GGUF must be rejected'
Assert-True (Test-ForbiddenPublicationPath 'results/logs/server.stdout.txt') 'logs must be rejected'
Assert-True (-not (Test-ForbiddenPublicationPath 'results/logprob/analysis.json')) 'analysis must be allowed'
$providerMetadata = 'provider' + '_metadata'
$threadId = 'thread' + '_id'
$nestedThreadFixture = "{`"$providerMetadata`":{`"nested`":{},`"$threadId`":`"abc`"}}"
$windowsUserPath = ('C' + ':') + '\' + ('Us' + 'ers') + '\person\secret'
$crossDriveWindowsUserPath = ('D' + ':') + '\' + ('uS' + 'ErS') + '\person\secret'
$slashWindowsUserPath = ('e' + ':') + '/' + ('US' + 'ERS') + '/person/secret'
$apiKeyAssignment = ('OPENAI' + '_API' + '_KEY') + '=example-secret'
$genericPrivateKey = '-----BEGIN ' + 'PRIVATE KEY-----'
$bearerToken = 'authorization: ' + ('bEa' + 'ReR') + ' example-token-value'
$emailAddress = 'Release.Review' + '@' + 'EXAMPLE.ORG'

Assert-True (Test-SensitivePublicationText -Text $nestedThreadFixture) 'nested provider thread IDs must be rejected'
Assert-True (Test-SensitivePublicationText -Text $windowsUserPath) 'user profile paths must be rejected'
Assert-True (Test-SensitivePublicationText -Text $crossDriveWindowsUserPath) 'cross-drive mixed-case user profile paths must be rejected'
Assert-True (Test-SensitivePublicationText -Text $slashWindowsUserPath) 'slash-form mixed-case user profile paths must be rejected'
Assert-True (Test-SensitivePublicationText -Text $apiKeyAssignment) 'prefixed API-key assignments must be rejected'
Assert-True (Test-SensitivePublicationText -Text $genericPrivateKey) 'generic private-key blocks must be rejected'
Assert-True (Test-SensitivePublicationText -Text $bearerToken) 'mixed-case authorization material must be rejected'
Assert-True (Test-SensitivePublicationText -Text $emailAddress) 'email addresses must be rejected'
Assert-True (-not (Test-SensitivePublicationText 'E:\Temp\spar-odd-number-20260823')) 'as-run E path is allowed'
Assert-True (-not (Test-SensitivePublicationText 'The ratio A:B/Users/guide is documentation.')) 'relative prose containing Users must remain allowed'
Assert-True (-not (Test-SensitivePublicationText 'Contact handle release-review at example dot org.')) 'non-email prose must remain allowed'

@(
    'cache/item.bin',
    '.cache/item.bin',
    'models/model.bin',
    'artifacts/models/model.bin',
    'local-manifests/manifest.json',
    'manifest.local.json',
    'experiments/incomplete-32b/run.json',
    'experiments/qwen-32b-incomplete/run.json',
    'archives/runtime.zip',
    'archives/runtime.7z',
    'bin/runtime.dll',
    'bin/runtime.exe',
    'tmp-clone/file.txt',
    'temp-clone/file.txt',
    'publication-clone/file.txt',
    '.env.review',
    'notes/access-token.txt',
    'notes/credentials.json'
) | ForEach-Object {
    Assert-True (Test-ForbiddenPublicationPath $_) "forbidden path must be rejected: $_"
}

if ($script:Failures -gt 0) {
    exit 1
}

Write-Host 'PASS: privacy helper tests'
