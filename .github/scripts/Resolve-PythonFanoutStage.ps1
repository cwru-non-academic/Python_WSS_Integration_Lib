param(
    [Parameter(Mandatory)][string]$EventPath,
    [Parameter(Mandatory)][string]$WorkRoot,
    [string]$CoreToolsRoot='',
    [string]$ProducerRunId='',
    [string]$BarrierRunId='',
    [string]$BarrierAttempt=''
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/PythonPromotion.ps1"
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne $PythonWrapperRepository) { throw 'Trusted Python wrapper workflow required.' }
if (Test-Path -LiteralPath $WorkRoot) { throw 'Staged fan-out workspace must be new.' }
New-Item -ItemType Directory -Path $WorkRoot | Out-Null
$event=Get-Content -LiteralPath $EventPath -Raw | ConvertFrom-Json
$resume=$env:GITHUB_EVENT_NAME -ceq 'workflow_dispatch'
if ($resume) {
    if ($env:GITHUB_REF -cne 'refs/heads/main' -or $env:GITHUB_WORKFLOW_REF -cne "$PythonWrapperRepository/.github/workflows/dispatch-cli-promotion.yml@refs/heads/main") { throw 'Barrier resumes require the registered trusted main workflow.' }
    foreach ($id in @($ProducerRunId,$BarrierRunId,$BarrierAttempt)) { if ($id -cnotmatch '^[1-9][0-9]*$') { throw 'Invalid staged producer/barrier identity.' } }
    $coreMain=(Invoke-PythonGh -Arguments @('api','repos/cwru-non-academic/WSSCore/branches/main') | ConvertFrom-Json).commit.sha
    $toolsSha=Invoke-PythonGit $CoreToolsRoot @('rev-parse','HEAD')
    if ($toolsSha -cne $coreMain) { throw 'Trusted Core main tooling moved; no application writes.' }
    $barrierJson=& node (Join-Path $CoreToolsRoot 'tools/ci/dev-propagation.mjs') verify-barrier $ProducerRunId $BarrierRunId $BarrierAttempt
    if ($LASTEXITCODE -ne 0) { throw 'Core integration barrier did not validate.' }
    $barrier=($barrierJson -join "`n") | ConvertFrom-Json
    $accepted=$barrier.integrations.python
    if ($barrier.schema -cnotin @('wss-integration-barrier/v1','wss-integration-barrier/v2') -or $accepted.repository -cne $PythonWrapperRepository -or [string]$barrier.candidate.run_id -cne $ProducerRunId) { throw 'Wrong barrier/receiver binding.' }
    Assert-PythonSha $accepted.head_sha
    if ([string]$accepted.pr_number -cnotmatch '^[1-9][0-9]*$') { throw 'Invalid barrier wrapper PR.' }
    $pr=Invoke-PythonGh -Arguments @('api',"repos/$PythonWrapperRepository/pulls/$($accepted.pr_number)") | ConvertFrom-Json
    if (!$pr.merged -or $pr.merge_commit_sha -cne $accepted.head_sha) { throw 'Barrier wrapper merge changed.' }
    $event=[pscustomobject]@{pull_request=$pr}
} elseif ($env:GITHUB_EVENT_NAME -cne 'pull_request_target') { throw 'Unsupported fan-out event.' }
$pr=$event.pull_request
if (!$pr.merged -or $pr.base.ref -cne 'dev' -or $pr.head.repo.full_name -cne $PythonWrapperRepository -or $pr.user.type -cne 'Bot' -or $pr.head.ref -cnotlike 'automation/python-wss-*') { throw 'Not a reviewed Python dependency promotion.' }
$approval=Read-PythonApprovalMarker $pr.body (Join-Path $WorkRoot 'approval.json')
Assert-PythonProducer $approval.candidate
if ($resume) { Assert-PythonSameCandidate $approval.candidate $barrier.candidate }
. "$PSScriptRoot/wss-ci/Staging.ps1"
$tree=Invoke-PythonGh -Arguments @('api',"repos/cwru-non-academic/WSSCore/git/trees/$($approval.candidate.commit)?recursive=1")|ConvertFrom-Json
$entries=@($tree.tree|Where-Object path -CEQ 'tools/ci/dev-propagation.json')
$file=if($entries.Count -eq 1){Invoke-PythonGh -Arguments @('api',"repos/cwru-non-academic/WSSCore/contents/tools/ci/dev-propagation.json?ref=$($approval.candidate.commit)")|ConvertFrom-Json}else{$null}
$receiver=Get-Content "$PSScriptRoot/../dev-propagation.json" -Raw|ConvertFrom-Json
$staged=Test-WssCiStagingPolicy $tree $file $receiver python
if($staged -and $resume){Assert-PythonFanoutApproval $approval}
if(!$staged -and $resume){throw 'A barrier resume requires a producer staging policy.'}
$roles=@(Get-PythonDispatchApplications $approval | ForEach-Object role)
$apps=@($roles | ForEach-Object { $app=Get-PythonApplication $_; @{role=$_;label=$_.ToUpperInvariant();repository=($app.repository -split '/')[1]} })
"applications=$($apps | ConvertTo-Json -Depth 4 -Compress -AsArray)" >> $env:GITHUB_OUTPUT
$allowed=!$staged -or $resume
"dispatch_allowed=$($allowed.ToString().ToLowerInvariant())" >> $env:GITHUB_OUTPUT
$event | ConvertTo-Json -Depth 100 | Set-Content (Join-Path $WorkRoot 'verified-event.json')
if (!$allowed) { Write-Output 'Staged producer: waiting for Core authorization of this integration and its exact committed CI; no application write token.' }
