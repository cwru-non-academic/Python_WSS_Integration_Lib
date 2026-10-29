$ErrorActionPreference='Stop'
. "$PSScriptRoot/../ReleaseReceiptContract.ps1"
function Reject([scriptblock]$Action) { $bad=$false;try { & $Action | Out-Null } catch {$bad=$true};if(!$bad){throw 'Receipt accepted invalid frozen source/application marker.'} }
# Unit-only source/marker data: never runtime, no-op equivalence or receipt proof.
$approval=[pscustomobject]@{wrapper=@{source_sha=('a'*40)};cli=@{source_sha=('b'*40)};ros=@{source_sha=('c'*40)}}
$plan=[pscustomobject]@{target_snapshots=@{'python-wrapper'=@{head_sha=('a'*40)};'python-cli'=@{head_sha=('b'*40)};'python-ros'=@{head_sha=('c'*40)}}}
Assert-PythonReceiptSnapshots $approval $plan
$wrong=$plan | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$wrong.target_snapshots.'python-ros'.head_sha='d'*40
Reject {Assert-PythonReceiptSnapshots $approval $wrong}
foreach($role in @('cli','ros')) {
    $marker=Get-PythonApplicationPreflightMarker $role ('d'*40) ('e'*40) '100'
    $fresh=Read-PythonReceiptApplicationMarker $marker $role
    if($fresh.wrapper_sha -cne ('d'*40)){throw 'Marker source changed.'}
    Reject {Read-PythonReceiptApplicationMarker ($marker+"`n"+$marker) $role}
    Reject {Read-PythonReceiptApplicationMarker ($marker+"`n<!-- wss-python-$role-preflight:v1 invalid_base64 -->") $role}
    $bad=$fresh | ConvertTo-Json | ConvertFrom-Json
    $bad | Add-Member -NotePropertyName unexpected -NotePropertyValue 'not-authority'
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($bad | ConvertTo-Json -Compress)))
    Reject {Read-PythonReceiptApplicationMarker "<!-- wss-python-$role-preflight:v1 $encoded -->" $role}
}
Write-Output 'PASS: frozen paired sources and canonical unambiguous merged-wrapper marker rejection checks.'
