$ErrorActionPreference='Stop'
. "$PSScriptRoot/../PythonContract.ps1"
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('wss-normalized-candidate-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temporary
$record=Get-Content (Join-Path $root '.github/python-candidate.json') -Raw | ConvertFrom-Json
# Binding-only unit metadata. This is never runtime evidence or an uploaded receipt.
$record | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $temporary 'projection.json')
@{candidate=$record.candidate;projection_sha256=$record.projection_sha256} | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $temporary 'evidence.json')
$json=$record.candidate | ConvertTo-Json -Depth 5 -Compress
$output=Join-Path $temporary 'normalized/candidate.json'
& "$PSScriptRoot/../Write-CandidateProvenance.ps1" -CandidateJson $json -EvidenceRoot $temporary -OutputPath $output | Out-Null
$normalized=Get-Content $output -Raw | ConvertFrom-Json
if ($normalized.PSObject.Properties.Name.Count -ne 6 -or $normalized.run_id -isnot [string] -or $normalized.artifact_id -isnot [string]) { throw 'Candidate must have exactly six string fields.' }
Assert-PythonSameCandidate $normalized $record.candidate
foreach ($case in @('candidate','extra','release','overwrite','projection')) {
    $bad=$record.candidate | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $out=Join-Path $temporary ($case+'/candidate.json')
    if ($case -ceq 'candidate') { $bad.artifact_id='999' }
    elseif ($case -ceq 'extra') { $bad | Add-Member -NotePropertyName unexpected -NotePropertyValue true }
    elseif ($case -ceq 'release') { $bad | Add-Member -NotePropertyName release_tag -NotePropertyValue v1 -Force }
    elseif ($case -ceq 'overwrite') { $out=$output }
    else { Add-Content (Join-Path $temporary 'projection.json') 'invalid' }
    $rejected=$false
    try { & "$PSScriptRoot/../Write-CandidateProvenance.ps1" -CandidateJson ($bad | ConvertTo-Json -Depth 5 -Compress) -EvidenceRoot $temporary -OutputPath $out | Out-Null } catch { $rejected=$true }
    if (!$rejected) { throw "Normalized provenance accepted invalid binding: $case" }
}
Write-Output 'PASS: six-field candidate binding/rejection unit checks; no preflight or acceptance proof fabricated.'
