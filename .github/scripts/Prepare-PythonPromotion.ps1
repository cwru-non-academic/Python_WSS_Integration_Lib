param(
    [Parameter(Mandatory)][ValidateSet('wrapper','cli')][string]$Role,
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [string]$CandidateJson='',
    [string]$ApprovalJson='',
    [string]$WrapperMergeSha='',
    [string]$WrapperPr='',
    [switch]$ValidateOnly
)
. "$PSScriptRoot/PythonPromotion.ps1"
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REF -cne 'refs/heads/dev') { throw 'Promotion preparation runs only in the trusted dev workflow.' }
if (Test-Path -LiteralPath $WorkRoot) { throw 'WorkRoot must be new.' }
New-Item -ItemType Directory -Path $WorkRoot | Out-Null
$config=Read-PythonConfig (Join-Path $RepositoryRoot '.github/python-ci.json')
if (!$config.baseline_ready -or $config.automated_execution -cne 'pythonnet') { throw 'Approved .NET promotion baseline required.' }
$source=(Invoke-PythonGit $RepositoryRoot @('rev-parse','HEAD')).Trim()
Assert-PythonSource $RepositoryRoot $source -IgnoreSubmodule
if ($source -cne $env:GITHUB_SHA) { throw 'Promotion checkout differs from trusted workflow source.' }
if ($Role -ceq 'wrapper') {
    if ($env:GITHUB_REPOSITORY -cne $PythonWrapperRepository -or !$CandidateJson -or $ApprovalJson) { throw 'Invalid wrapper promotion inputs/repository.' }
    $candidate=$CandidateJson | ConvertFrom-Json
    Assert-PythonProducer $candidate
    & "$PSScriptRoot/Resolve-WssRelease.ps1" -RunId $candidate.run_id -ExpectedArtifactId $candidate.artifact_id -ExpectedCommit $candidate.commit -ArchiveName $candidate.archive -ExpectedSha256 $candidate.sha256 -OutputRoot (Join-Path $WorkRoot 'resolved')
    $resolved=Get-Content -LiteralPath (Join-Path $WorkRoot 'resolved/candidate.json') -Raw | ConvertFrom-Json
    Assert-PythonSameCandidate $resolved $candidate
    $projection=New-PythonProjection (Join-Path $WorkRoot 'resolved/extracted/WSS-Universal') $RepositoryRoot (Join-Path $WorkRoot 'projection') $candidate
    $current=Get-Content -LiteralPath (Join-Path $RepositoryRoot '.github/python-candidate.json') -Raw | ConvertFrom-Json
    Assert-PythonProjection (Join-Path $RepositoryRoot $PythonPluginPath) $current
    if ($current.projection_sha256 -ceq $projection.projection_sha256) {
        @{no_op=$true;role=$Role;source_sha=$source} | ConvertTo-Json | Set-Content (Join-Path $WorkRoot 'prepared.json')
        'no_op=true' >> $env:GITHUB_OUTPUT
        Write-Output 'Verified identical payload: preserve committed provenance; no artificial PR.'
        exit 0
    }
    $cliSha=Get-PythonHead $PythonCliRepository
    if ((Get-PythonHead $PythonWrapperRepository) -cne $source) { throw 'Wrapper dev advanced before preflight.' }
    if ($ValidateOnly) {
        @{no_op=$false;role=$Role;source_sha=$source;cli_source_sha=$cliSha} | ConvertTo-Json | Set-Content (Join-Path $WorkRoot 'prepared.json')
        'no_op=false' >> $env:GITHUB_OUTPUT
        Write-Output 'Producer, archive, projection and source validated before preflight write credentials.'
        exit 0
    }
    $wrapperRun=Start-PythonPreflight $PythonWrapperRepository $candidate $source $cliSha
    $cliRun=Start-PythonPreflight $PythonCliRepository $candidate $source $cliSha
    $approval=[ordered]@{
        schema='wss-python-promotion/v1'; candidate=$candidate
        wrapper=@{source_sha=$source;preflight_run_id=[string]$wrapperRun.id}
        cli=@{source_sha=$cliSha;preflight_run_id=[string]$cliRun.id}
        fixture=@{commit=$config.fixture_commit;sha256=$config.fixture_sha256}
        projection_sha256=$projection.projection_sha256
    }
    $approval | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $WorkRoot 'approval.json')
    $approval=Read-PythonApproval (Join-Path $WorkRoot 'approval.json')
    Assert-PythonApproval $approval (Join-Path $WorkRoot 'evidence') $config
    $projection | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $WorkRoot 'projection.json')
} else {
    if ($env:GITHUB_REPOSITORY -cne $PythonCliRepository -or !$ApprovalJson -or $CandidateJson) { throw 'Invalid CLI promotion inputs/repository.' }
    [IO.File]::WriteAllText((Join-Path $WorkRoot 'approval.json'),$ApprovalJson)
    $approval=Read-PythonApproval (Join-Path $WorkRoot 'approval.json')
    $candidate=$approval.candidate
    Assert-PythonApproval $approval (Join-Path $WorkRoot 'evidence') $config
    Assert-PythonMergedWrapper $WrapperMergeSha $WrapperPr $approval
    $entry=(Invoke-PythonGit $RepositoryRoot @('ls-tree','HEAD','--',$PythonGitlink)) -join ''
    if ($entry -ceq "160000 commit $WrapperMergeSha`t$PythonGitlink") {
        @{no_op=$true;role=$Role;source_sha=$source} | ConvertTo-Json | Set-Content (Join-Path $WorkRoot 'prepared.json')
        'no_op=true' >> $env:GITHUB_OUTPUT
        Write-Output 'Verified existing accepted gitlink; no PR.'
        exit 0
    }
    if ((Get-PythonHead $PythonCliRepository) -cne $source) { throw 'CLI dev advanced before merged-wrapper preflight.' }
    if ($ValidateOnly) {
        @{no_op=$false;role=$Role;source_sha=$source;wrapper_merge_sha=$WrapperMergeSha;wrapper_pr=$WrapperPr} | ConvertTo-Json | Set-Content (Join-Path $WorkRoot 'prepared.json')
        'no_op=false' >> $env:GITHUB_OUTPUT
        Write-Output 'Existing approval and actual reviewed wrapper merge validated before CLI preflight write credentials.'
        exit 0
    }
    $postMerge=Start-PythonPreflight $PythonCliRepository $candidate $WrapperMergeSha $source
    $cliPreflightId=[string]$postMerge.id
    Assert-PythonMergedCliPreflight $approval $WrapperMergeSha $source $cliPreflightId (Join-Path $WorkRoot 'merged-cli-evidence') $config
}
$prepared=@{no_op=$false;role=$Role;source_sha=$source;wrapper_merge_sha=$WrapperMergeSha;wrapper_pr=$WrapperPr}
if ($Role -ceq 'cli') { $prepared.cli_preflight_run_id=$cliPreflightId }
$prepared | ConvertTo-Json | Set-Content (Join-Path $WorkRoot 'prepared.json')
'no_op=false' >> $env:GITHUB_OUTPUT
