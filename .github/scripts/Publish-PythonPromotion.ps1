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
    foreach ($source in @(Get-PythonProjectionFiles $projection)) {
        $target = Join-Path $payloadRoot $source
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath (Join-Path $WorkRoot "projection/$source") -Destination $target
    }
    $projection | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $RepositoryRoot '.github/python-candidate.json')
    $allowed=Get-PythonAllowedWrapperPaths $projection
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
# The adapter has verified/staged exact payload or gitlink bytes. One engine publishes.
$bodyPath=Join-Path $WorkRoot 'pr-body.md'
$body="Promotes the exact candidate accepted by reviewed Python evidence. Manual review/merge required.`n`n$marker`n"
$markers=@($marker)
$parents=@{}; $gitlinks=@{}
if($role -cne 'wrapper') {
    $body+="`n$applicationMarker`n"
    $markers+=$applicationMarker
    $parents['cwru-non-academic/Python_WSS_Integration_Lib']=$prepared.wrapper_merge_sha
    $gitlinks[$allowed[0]]=$prepared.wrapper_merge_sha
}
if($role -ceq 'wrapper' -and 'python' -ceq 'unity'){$body="<!-- wss-unity-promotion:v1 -->`n"+$body}
[IO.File]::WriteAllText($bodyPath,$body)
$descriptor=@{target_id="python-$role";repository_root=[IO.Path]::GetFullPath($RepositoryRoot);source_sha=$prepared.source_sha;candidate=$approval.candidate;branch=$branch;allowed_paths=@($allowed);markers=$markers;gitlinks=$gitlinks;parent_heads=$parents;body_path=[IO.Path]::GetFullPath($bodyPath);title="Promote verified Python WSS $($approval.candidate.run_id)";commit_message="Promote verified Python WSS $($approval.candidate.run_id)"}
$descriptorPath=Join-Path $WorkRoot 'publication.json'
$descriptor|ConvertTo-Json -Depth 16|Set-Content -LiteralPath $descriptorPath
$saved=$env:WSS_PUSH_TOKEN
try {
    $env:WSS_PUSH_TOKEN=$env:PYTHON_PUSH_TOKEN
    & node (Join-Path $PSScriptRoot 'wss-ci/promotion.mjs') $descriptorPath
    if($LASTEXITCODE -ne 0){throw 'Common promotion publication failed or is uncertain; inspect before retry.'}
} finally {$env:WSS_PUSH_TOKEN=$saved}
