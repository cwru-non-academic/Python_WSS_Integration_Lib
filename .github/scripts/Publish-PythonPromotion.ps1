param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$WorkRoot)
. "$PSScriptRoot/PythonPromotion.ps1"
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REF -cne 'refs/heads/dev' -or !$env:PYTHON_PUSH_TOKEN) { throw 'Publication requires the trusted dev workflow and delayed scoped token.' }
$prepared=Get-Content -LiteralPath (Join-Path $WorkRoot 'prepared.json') -Raw | ConvertFrom-Json
if ($prepared.no_op) { throw 'No-op preparation must not mint a write token or publish.' }
$role=$prepared.role
if ($role -ceq 'wrapper') { $repo=$PythonWrapperRepository }
else { $application=Get-PythonApplication $role; $repo=$application.repository }
if ($repo -cne $env:GITHUB_REPOSITORY) { throw 'Wrong publication repository.' }
$config=Read-PythonConfig (Join-Path $RepositoryRoot '.github/python-ci.json')
if (!$config.baseline_ready -or $config.automated_execution -cne 'pythonnet') { throw 'Approved .NET promotion baseline required.' }
$approval=Read-PythonApproval (Join-Path $WorkRoot 'approval.json')
if ($role -cin @('wrapper','ros')) { Assert-PythonFanoutApproval $approval }
Assert-PythonApproval $approval (Join-Path $WorkRoot 'publication-evidence') $config
Assert-PythonSource $RepositoryRoot $prepared.source_sha -IgnoreSubmodule
if ((Get-PythonHead $repo) -cne $prepared.source_sha) { throw 'Target dev advanced; no stale PR.' }
$branch="automation/python-wss-$($approval.candidate.run_id)-$($approval.candidate.sha256)"
$marker=Get-PythonApprovalMarker $approval
if ($role -ceq 'wrapper') {
    if ($prepared.source_sha -cne $approval.wrapper.source_sha) { throw 'Untested wrapper source.' }
    $projection=Get-Content -LiteralPath (Join-Path $WorkRoot 'projection.json') -Raw | ConvertFrom-Json
    Assert-PythonSameCandidate $projection.candidate $approval.candidate
    Assert-PythonProjection (Join-Path $WorkRoot 'projection') $projection
    if ($projection.projection_sha256 -cne $approval.projection_sha256) { throw 'Staged projection differs from preflight.' }
    $payloadRoot=Join-Path $RepositoryRoot $PythonPluginPath
    # Both validated roots are exact full inventories; replace only allowlisted files.
    foreach ($source in $PythonProjectionFiles) {
        Copy-Item -LiteralPath (Join-Path $WorkRoot "projection/$source") -Destination (Join-Path $payloadRoot $source)
    }
    $projection | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $RepositoryRoot '.github/python-candidate.json')
    $allowed=Get-PythonAllowedWrapperPaths
    $null=Invoke-PythonGit $RepositoryRoot (@('add','--')+$allowed)
    Assert-PythonProjection (Join-Path $RepositoryRoot $PythonPluginPath) $projection
} else {
    Assert-PythonMergedWrapper $prepared.wrapper_merge_sha $prepared.wrapper_pr $approval
    $preflightId=if ($prepared.PSObject.Properties['application_preflight_run_id']) { $prepared.application_preflight_run_id } elseif ($role -ceq 'cli') { $prepared.cli_preflight_run_id } else { throw 'Application preflight ID missing.' }
    Assert-PythonMergedApplicationPreflight $approval $role $prepared.wrapper_merge_sha $prepared.source_sha $preflightId (Join-Path $WorkRoot ('publication-merged-'+$role+'-evidence')) $config
    $applicationMarker=Get-PythonApplicationPreflightMarker $role $prepared.wrapper_merge_sha $prepared.source_sha $preflightId
    $allowed=@($application.gitlink)
    $null=Invoke-PythonGit $RepositoryRoot @('update-index','--cacheinfo',"160000,$($prepared.wrapper_merge_sha),$($application.gitlink)")
    $entry=(Invoke-PythonGit $RepositoryRoot @('ls-files','--stage','--',$application.gitlink)) -join ''
    if ($entry -cne "160000 $($prepared.wrapper_merge_sha) 0`t$($application.gitlink)") { throw 'Staged application entry is not the accepted gitlink.' }

}
$changed=@(Invoke-PythonGit $RepositoryRoot @('diff','--cached','--name-only'))
Assert-PythonDiff $changed $allowed
if (@(Invoke-PythonGit $RepositoryRoot @('diff','--name-only','--ignore-submodules=all')).Count -ne 0) { throw 'Unstaged changes outside the intended promotion.' }
$tree=(Invoke-PythonGit $RepositoryRoot @('write-tree')).Trim()
$pulls=@(Invoke-PythonGh @('pr','list','--repo',$repo,'--state','all','--base','dev','--head',$branch,'--limit','2','--json','number,url,state,body,headRefOid') | ConvertFrom-Json)
if ($pulls.Count -gt 1 -or ($pulls.Count -eq 1 -and $pulls[0].state -cne 'OPEN')) { throw 'Ambiguous or already closed/merged candidate PR; no replacement or rollback.' }
$refs=@(Invoke-PythonGh @('api',"repos/$repo/git/matching-refs/heads/$branch") | ConvertFrom-Json | Where-Object { $_.ref -ceq "refs/heads/$branch" })
if ($pulls.Count -eq 1) {
    if ($refs.Count -ne 1 -or $pulls[0].headRefOid -cne $refs[0].object.sha -or !(($pulls[0].body -split "`r?`n") -ccontains $marker)) { throw 'Existing PR branch/metadata conflict.' }
    if ($role -cne 'wrapper' -and !(($pulls[0].body -split "`r?`n") -ccontains $applicationMarker)) { throw 'Existing application PR does not carry the exact merged-wrapper preflight.' }
    $remoteCommit=Invoke-PythonGh @('api',"repos/$repo/git/commits/$($refs[0].object.sha)") | ConvertFrom-Json
    if ($remoteCommit.tree.sha -cne $tree -or @($remoteCommit.parents).Count -ne 1 -or $remoteCommit.parents[0].sha -cne $prepared.source_sha) { throw 'Existing PR is not the exact intended tree/source.' }
    Write-Output "Reusing exact existing PR: $($pulls[0].url)"
    exit 0
}
if ($refs.Count -ne 0) { throw 'Orphan candidate branch exists; inspect rather than overwriting.' }
$null=Invoke-PythonGit $RepositoryRoot @('switch','-c',$branch)
$null=Invoke-PythonGit $RepositoryRoot @('-c','user.name=WSS Python automation','-c','user.email=wss-python-automation@users.noreply.github.com','commit','-m',"Promote verified Python WSS $($approval.candidate.run_id)")
# Per-command credentials only; never alter Git global/system trust or credential configuration.
$header=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('x-access-token:'+$env:PYTHON_PUSH_TOKEN))
Write-Output "::add-mask::$header"
$null=Invoke-PythonGit $RepositoryRoot @('-c',"http.https://github.com/.extraheader=AUTHORIZATION: basic $header",'push','origin',"HEAD:refs/heads/$branch")
$bodyPath=Join-Path $WorkRoot 'pr-body.md'
$body="Promotes the exact candidate accepted by its versioned Python approval. Manual review/merge required; no release.`n`n<!-- $($approval.schema.Replace('/','-')) -->`n$marker`n"
if ($role -cne 'wrapper') { $body+="`nActual merged-wrapper $($role.ToUpperInvariant()) preflight: https://github.com/$repo/actions/runs/$preflightId`n$applicationMarker`n" }
[IO.File]::WriteAllText($bodyPath,$body)
$readToken=$env:GH_TOKEN
$title="Promote universal WSS run $($approval.candidate.run_id)"
if ($role -cne 'wrapper') { $title+=" / Integration $($prepared.wrapper_merge_sha.Substring(0,12))" }
try {
    $env:GH_TOKEN=$env:PYTHON_PUSH_TOKEN
    $null=Invoke-PythonGh @('pr','create','--repo',$repo,'--base','dev','--head',$branch,'--title',$title,'--body-file',$bodyPath)
} finally { $env:GH_TOKEN=$readToken }
