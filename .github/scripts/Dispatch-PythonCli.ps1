param([ValidateSet('cli','ros')][string]$Role='cli',[Parameter(Mandatory)][string]$EventPath,[Parameter(Mandatory)][string]$WorkRoot,[switch]$ValidateOnly)
. "$PSScriptRoot/PythonPromotion.ps1"
$context=Get-WssCiChannelContext
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne $PythonWrapperRepository) { throw 'Trusted wrapper dispatcher required.' }
$application=Get-PythonApplication $Role
$event=Get-Content -LiteralPath $EventPath -Raw | ConvertFrom-Json
$pr=$event.pull_request
if (!$pr.merged -or $pr.base.ref -cne $context.branch -or $pr.head.repo.full_name -cne $PythonWrapperRepository -or $pr.user.type -cne 'Bot' -or $pr.head.ref -cnotlike 'automation/python-wss-*') { throw 'Not a reviewed Python dependency promotion.' }
if (Test-Path -LiteralPath $WorkRoot) { throw 'Dispatcher workspace must be new.' }
New-Item -ItemType Directory -Path $WorkRoot | Out-Null
try { Write-WssCiPhaseDiagnostic -Family 'python' -Role $Role -Operation 'validate-approval' -Status 'started' -ErrorCode 'none' } catch { } # wss-diag
$approval=Read-PythonApprovalMarker $pr.body (Join-Path $WorkRoot 'approval.json')
try { Write-WssCiPhaseDiagnostic -Family 'python' -Role $Role -Operation 'validate-approval' -Status 'completed' -ErrorCode 'none' } catch { } # wss-diag
if ($Role -ceq 'ros') { Assert-PythonFanoutApproval $approval }
if ($pr.head.ref -cne "automation/python-wss-$($approval.candidate.run_id)-$($approval.candidate.sha256)") { throw 'Promotion branch/candidate mismatch.' }
$config=Read-PythonConfig "$PSScriptRoot/../python-ci.json" -Channel $context.channel
if (!$config.baseline_ready -or $config.automated_execution -cne 'pythonnet') { throw 'Approved .NET promotion baseline required.' }
try { Write-WssCiPhaseDiagnostic -Family 'python' -Role $Role -Operation 'validate-family-evidence' -Status 'started' -ErrorCode 'none' } catch { } # wss-diag
Assert-PythonApproval $approval (Join-Path $WorkRoot 'evidence') $config
try { Write-WssCiPhaseDiagnostic -Family 'python' -Role $Role -Operation 'validate-family-evidence' -Status 'completed' -ErrorCode 'none' } catch { } # wss-diag
try { Write-WssCiPhaseDiagnostic -Family 'python' -Role $Role -Operation 'validate-reviewed-merge' -Status 'started' -ErrorCode 'none' } catch { } # wss-diag
Assert-PythonMergedWrapper $pr.merge_commit_sha ([string]$pr.number) $approval
try { Write-WssCiPhaseDiagnostic -Family 'python' -Role $Role -Operation 'validate-reviewed-merge' -Status 'completed' -ErrorCode 'none' } catch { } # wss-diag
$body=@{ref=$context.branch;inputs=@{wrapper_sha=$pr.merge_commit_sha;wrapper_pr=[string]$pr.number;approval_json=($approval | ConvertTo-Json -Depth 8 -Compress)}} | ConvertTo-Json -Depth 6 -Compress
try { Write-WssCiPhaseDiagnostic -Family 'python' -Role $Role -Operation 'inspect-reuse' -Status 'started' -ErrorCode 'none' } catch { } # wss-diag
$pages=Invoke-PythonGh -Arguments @('api','--paginate','--slurp',"repos/$($application.repository)/actions/workflows/promote-integration.yml/runs?event=workflow_dispatch&per_page=100") | ConvertFrom-Json
$existing=@($pages | ForEach-Object { $_.workflow_runs } | Where-Object { $_.display_title -ceq "Promote Integration $($pr.merge_commit_sha) / wss-$($approval.candidate.run_id)-$($approval.candidate.artifact_id)" })
. "$PSScriptRoot/wss-ci/DispatchProof.ps1"
$run=if($existing.Count -eq 1 -and [string]$existing[0].id -cmatch '^[1-9][0-9]*$'){Invoke-PythonGh -Arguments @('api',"repos/$($application.repository)/actions/runs/$($existing[0].id)")|ConvertFrom-Json}else{$null}
$reuse=Invoke-WssCiDispatchProof @{operation='reuse';runs=$existing;run=$run;expected=@{repository=$application.repository;source_sha=$approval.$Role.source_sha;title="Promote Integration $($pr.merge_commit_sha) / wss-$($approval.candidate.run_id)-$($approval.candidate.artifact_id)"}}
try { Write-WssCiPhaseDiagnostic -Family 'python' -Role $Role -Operation 'inspect-reuse' -Status 'completed' -ErrorCode 'none' } catch { } # wss-diag
if($reuse){'dispatch_needed=false' >> $env:GITHUB_OUTPUT; exit 0}
$intentName="python-$Role-dispatch-$($pr.merge_commit_sha)"
try { Write-WssCiPhaseDiagnostic -Family 'python' -Role $Role -Operation 'validate-intent' -Status 'started' -ErrorCode 'none' } catch { } # wss-diag
Assert-WssCiDispatchArtifacts $env:GITHUB_REPOSITORY $intentName
try { Write-WssCiPhaseDiagnostic -Family 'python' -Role $Role -Operation 'validate-intent' -Status 'completed' -ErrorCode 'none' } catch { } # wss-diag
try { Write-WssCiPhaseDiagnostic -Family 'python' -Role $Role -Operation 'write-intent' -Status 'started' -ErrorCode 'none' } catch { } # wss-diag
$sources=@{};$sources[$env:GITHUB_REPOSITORY]=$pr.merge_commit_sha;$sources[$application.repository]=$approval.$Role.source_sha
@{owner=$env:GITHUB_REPOSITORY;repository=$application.repository;name=$intentName;sources=$sources}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $WorkRoot 'dispatch-sources.json')
"intent_name=$intentName" >> $env:GITHUB_OUTPUT
[IO.File]::WriteAllText((Join-Path $WorkRoot ($Role+'-dispatch.json')),$body)
'dispatch_needed=true' >> $env:GITHUB_OUTPUT
try { Write-WssCiPhaseDiagnostic -Family 'python' -Role $Role -Operation 'write-intent' -Status 'completed' -ErrorCode 'none' } catch { } # wss-diag
if ($ValidateOnly) { exit 0 }
throw 'Dispatch must pass the shared durable-intent workflow gate; use ValidateOnly and the common sender.'
