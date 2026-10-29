param(
    [Parameter(Mandatory)][string]$CandidateJson,
    [Parameter(Mandatory)][string]$EvidenceRoot,
    [Parameter(Mandatory)][string]$OutputPath
)
. "$PSScriptRoot/PythonContract.ps1"
$candidate=$CandidateJson | ConvertFrom-Json
Assert-PythonCandidate $candidate
$keys=@('repository','commit','run_id','artifact_id','archive','sha256')
if (@($candidate.PSObject.Properties.Name | Where-Object { $_ -cnotin ($keys+@('release_tag')) }).Count -or
    ($candidate.PSObject.Properties['release_tag'] -and $candidate.release_tag -cne '') -or
    $candidate.archive -cne 'WSS-Universal-ci.zip') { throw 'Only the canonical six-field dev candidate may be normalized.' }
$e=Get-Content (Join-Path $EvidenceRoot 'evidence.json') -Raw | ConvertFrom-Json
$p=Get-Content (Join-Path $EvidenceRoot 'projection.json') -Raw | ConvertFrom-Json
Assert-PythonSameCandidate $e.candidate $candidate
Assert-PythonSameCandidate $p.candidate $candidate
$null=@(Get-PythonProjectionFiles $p)
if ($p.schema -cne 'wss-python-projection/v1' -or
    $p.projection_sha256 -cne $e.projection_sha256 -or
    (Get-PythonProjectionDigest $p.files) -cne $p.projection_sha256) { throw 'Rich canonical/projection evidence differs.' }
if (Test-Path -LiteralPath $OutputPath) { throw 'Normalized candidate output must be new.' }
$normalized=[ordered]@{}
foreach ($key in $keys) { $normalized[$key]=[string]$candidate.$key }
$null=New-Item -ItemType Directory -Force -Path (Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath)))
$normalized | ConvertTo-Json -Compress | Set-Content -LiteralPath $OutputPath
Write-Output 'Normalized the exact successful-preflight candidate; existing rich evidence is retained separately.'
