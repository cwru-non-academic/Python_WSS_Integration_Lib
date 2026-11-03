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
    $coreMain=(Invoke-PythonGh @('api','repos/cwru-non-academic/WSSCore/branches/main') | ConvertFrom-Json).commit.sha
    $toolsSha=Invoke-PythonGit $CoreToolsRoot @('rev-parse','HEAD')
    if ($toolsSha -cne $coreMain) { throw 'Trusted Core main tooling moved; no application writes.' }
    $barrierJson=& node (Join-Path $CoreToolsRoot 'tools/ci/dev-propagation.mjs') verify-barrier $ProducerRunId $BarrierRunId $BarrierAttempt
    if ($LASTEXITCODE -ne 0) { throw 'Core integration barrier did not validate.' }
    $barrier=($barrierJson -join "`n") | ConvertFrom-Json
    $accepted=$barrier.integrations.python
    if ($barrier.schema -cne 'wss-integration-barrier/v1' -or $accepted.repository -cne $PythonWrapperRepository -or [string]$barrier.candidate.run_id -cne $ProducerRunId) { throw 'Wrong barrier/receiver binding.' }
    Assert-PythonSha $accepted.head_sha
    if ([string]$accepted.pr_number -cnotmatch '^[1-9][0-9]*$') { throw 'Invalid barrier wrapper PR.' }
    $pr=Invoke-PythonGh @('api',"repos/$PythonWrapperRepository/pulls/$($accepted.pr_number)") | ConvertFrom-Json
    if (!$pr.merged -or $pr.merge_commit_sha -cne $accepted.head_sha) { throw 'Barrier wrapper merge changed.' }
    $event=[pscustomobject]@{pull_request=$pr}
} elseif ($env:GITHUB_EVENT_NAME -cne 'pull_request_target') { throw 'Unsupported fan-out event.' }
$pr=$event.pull_request
if (!$pr.merged -or $pr.base.ref -cne 'dev' -or $pr.head.repo.full_name -cne $PythonWrapperRepository -or $pr.user.type -cne 'Bot' -or $pr.head.ref -cnotlike 'automation/python-wss-*') { throw 'Not a reviewed Python dependency promotion.' }
$approval=Read-PythonApprovalMarker $pr.body (Join-Path $WorkRoot 'approval.json')
Assert-PythonProducer $approval.candidate
if ($resume) { Assert-PythonSameCandidate $approval.candidate $barrier.candidate }
# Establish absence from the complete tree at the VERIFIED producer commit.
# A failed contents request or a changed Core HEAD must never enable legacy fan-out.
$tree=Invoke-PythonGh @('api',"repos/cwru-non-academic/WSSCore/git/trees/$($approval.candidate.commit)?recursive=1") | ConvertFrom-Json
if ($tree.truncated -isnot [bool] -or $tree.truncated -or $tree.tree -isnot [array] -or $tree.sha -cnotmatch '^[0-9a-f]{40}$') { throw 'Cannot establish producer staging policy from an incomplete tree.' }
$policyFile=@($tree.tree | Where-Object { $_.path -ceq 'tools/ci/dev-propagation.json' })
if ($policyFile.Count -gt 1) { throw 'Ambiguous producer policy.' }
$staged=$policyFile.Count -eq 1
if ($staged) {
    $content=Invoke-PythonGh @('api',"repos/cwru-non-academic/WSSCore/contents/tools/ci/dev-propagation.json?ref=$($approval.candidate.commit)") | ConvertFrom-Json
    if ($content.type -cne 'file' -or $content.encoding -cne 'base64' -or $content.sha -cne $policyFile[0].sha) { throw 'Producer policy identity mismatch.' }
    $policy=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($content.content)) | ConvertFrom-Json
    $python=@($policy.libraries | Where-Object { $_.id -ceq 'python' })
    $receiver=Get-Content "$PSScriptRoot/../dev-propagation.json" -Raw | ConvertFrom-Json
    if ($receiver.schema -cne 'wss-dev-stage-receiver/v1' -or $receiver.core_workflow -cne '.github/workflows/dev-propagation.yml' -or $receiver.fanout_workflow -cne 'dispatch-cli-promotion.yml' -or $receiver.staged_applications -ne $true) { throw 'Invalid staged receiver declaration.' }
    if ($policy.schema -cne 'wss-dev-stage/v1' -or $policy.channel -cne 'dev' -or $python.Count -ne 1 -or $python[0].repository -cne $PythonWrapperRepository -or $python[0].fanout -cne $receiver.fanout_workflow -or
        (($python[0].applications | Sort-Object) -join ',') -cne (($receiver.applications | Sort-Object) -join ',')) { throw 'Unsupported or mismatched producer staging policy.' }
    if ($resume) { Assert-PythonFanoutApproval $approval }
} elseif ($resume) { throw 'A barrier resume requires a producer staging policy.' }
$roles=@(Get-PythonDispatchApplications $approval | ForEach-Object role)
$apps=@($roles | ForEach-Object { $app=Get-PythonApplication $_; @{role=$_;label=$_.ToUpperInvariant();repository=($app.repository -split '/')[1]} })
"applications=$($apps | ConvertTo-Json -Depth 4 -Compress -AsArray)" >> $env:GITHUB_OUTPUT
$allowed=!$staged -or $resume
"dispatch_allowed=$($allowed.ToString().ToLowerInvariant())" >> $env:GITHUB_OUTPUT
$event | ConvertTo-Json -Depth 100 | Set-Content (Join-Path $WorkRoot 'verified-event.json')
if (!$allowed) { Write-Output 'Staged producer: waiting for the complete Core integration barrier; no application write token.' }
