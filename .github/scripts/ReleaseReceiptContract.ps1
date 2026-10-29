. "$PSScriptRoot/PythonPromotion.ps1"
function Assert-PythonReceiptSnapshots($Approval,$Plan) {
    foreach ($role in @('wrapper','cli','ros')) {
        $targetId=if ($role -ceq 'wrapper') { 'python-wrapper' } else { 'python-'+$role }
        if ($Approval.$role.source_sha -cne $Plan.target_snapshots.$targetId.head_sha) { throw 'Approval source differs from frozen target snapshot.' }
    }
}
function Read-PythonReceiptApplicationMarker([string]$Body,[ValidateSet('cli','ros')][string]$Role) {
    $lines=@($Body -split "`r?`n" | Where-Object { $_.StartsWith('<!-- wss-python-',[StringComparison]::Ordinal) -and $_.Contains('-preflight:') })
    $pattern='^<!-- wss-python-'+$Role+'-preflight:v1 ([A-Za-z0-9+/=]+) -->$'
    if ($lines.Count -ne 1 -or $lines[0] -cnotmatch $pattern) { throw 'Expected one unambiguous actual merged-wrapper application marker.' }
    $fresh=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Matches[1])) | ConvertFrom-Json
    $source=$fresh.((Get-PythonApplication $Role).source_field)
    $canonical=Get-PythonApplicationPreflightMarker $Role $fresh.wrapper_sha $source ([string]$fresh.preflight_run_id)
    if ($lines[0] -cne $canonical) { throw 'Application marker is not the canonical existing proof contract.' }
    $fresh
}
