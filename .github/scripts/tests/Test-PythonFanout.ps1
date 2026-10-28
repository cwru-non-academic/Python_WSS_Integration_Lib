param()
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../PythonPromotion.ps1"
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('wss-python-fanout-guards-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
$checks=0
function Assert-Test([bool]$Condition,[string]$Message) {
    if (!$Condition) { throw $Message }
    $script:checks++
}
function Assert-Rejected([scriptblock]$Action,[string]$Message) {
    $rejected=$false
    try { & $Action | Out-Null } catch { $rejected=$true }
    Assert-Test $rejected $Message
}
$candidate=@{repository='cwru-non-academic/WSSCore';commit=('a'*40);run_id='123';artifact_id='456';archive='WSS-Universal-ci.zip';sha256=('b'*64)}
$base=[ordered]@{
    schema='wss-python-promotion/v2';candidate=$candidate
    wrapper=@{source_sha=('c'*40);preflight_run_id='101'}
    cli=@{source_sha=('d'*40);preflight_run_id='102'}
    ros=@{source_sha=('e'*40);preflight_run_id='103'}
    fixture=@{commit=('f'*40);sha256=('1'*64)};projection_sha256=('2'*64)
}
function Read-TestApproval($Value,[string]$Name) {
    $path=Join-Path $temporary ($Name+'.json')
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path
    Read-PythonApproval $path
}
$v2=Read-TestApproval $base 'v2'
Assert-PythonFanoutApproval $v2
Assert-Test ((@(Get-PythonApprovalRoles $v2) -join ',') -ceq 'wrapper,cli,ros') 'V2 must require all three independent proofs.'
Assert-Test ((@(Get-PythonDispatchApplications $v2 | ForEach-Object role) -join ',') -ceq 'cli,ros') 'V2 must dispatch both applications.'
$marker=Get-PythonApprovalMarker $v2
Assert-Test ($marker.StartsWith('<!-- wss-python-approval:v2 ',[StringComparison]::Ordinal)) 'V2 marker must be explicit.'
$roundTrip=Read-PythonApprovalMarker $marker (Join-Path $temporary 'marker.json')
Assert-Test ((Get-PythonApprovalMarker $roundTrip) -ceq $marker) 'V2 marker normalization changed.'
Assert-Rejected { Read-PythonApprovalMarker ($marker+"`n"+$marker) (Join-Path $temporary 'duplicate.json') } 'Duplicate approval markers must fail.'
$bad=$base | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$bad.ros.source_sha='short'
Assert-Rejected { Read-TestApproval $bad 'short-ros' } 'ROS source SHA must be immutable/full.'
$bad=$base | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$bad.PSObject.Properties.Remove('ros')
Assert-Rejected { Read-TestApproval $bad 'missing-ros' } 'V2 cannot omit the ROS proof.'
$legacy=$base | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$legacy.schema='wss-python-promotion/v1'
$legacy.PSObject.Properties.Remove('ros')
$v1=Read-TestApproval $legacy 'legacy'
Assert-Test ((@(Get-PythonDispatchApplications $v1 | ForEach-Object role) -join ',') -ceq 'cli') 'Legacy requests must keep CLI-only dispatch.'
Assert-Rejected { Assert-PythonFanoutApproval $v1 } 'Legacy approval cannot authorize new wrapper/ROS publication.'
$legacyMarker=Get-PythonApprovalMarker $v1
Assert-Test ($legacyMarker.StartsWith('<!-- wss-python-approval:',[StringComparison]::Ordinal) -and !$legacyMarker.StartsWith('<!-- wss-python-approval:v2 ',[StringComparison]::Ordinal)) 'Legacy marker compatibility changed.'
Assert-Test ((Get-PythonApprovalMarker (Read-PythonApprovalMarker $legacyMarker (Join-Path $temporary 'legacy-marker.json'))) -ceq $legacyMarker) 'Legacy marker roundtrip changed.'
Assert-Test ((Get-PythonApplication 'cli').gitlink -ceq 'external/wss-py-wrapper') 'CLI gitlink compatibility changed.'
Assert-Test ((Get-PythonApplication 'ros').gitlink -ceq 'HFI_WSS_Python_Interface') 'ROS gitlink contract changed.'
Assert-Test ((Get-PythonApplication 'ros').acceptance -ceq 'ROS compatibility') 'ROS baseline acceptance name changed.'
Assert-Test (@(Get-PythonEvidenceFiles 'cli').Count -eq 4) 'CLI artifact inventory changed.'
Assert-Test (@(Get-PythonEvidenceFiles 'ros').Count -eq 7) 'ROS proof must include canonical, model and both native layout reports.'
Assert-Test (@(Get-PythonEvidenceJobs 'ros').Count -eq 3) 'ROS proof must require both real suites and aggregate acceptance.'
Assert-Rejected { Assert-PythonRosReports ([pscustomobject]@{native_ros_distribution='unknown'}) $temporary } 'Native ROS distribution must be explicit.'
Assert-Rejected { Assert-PythonRosReports ([pscustomobject]@{native_ros_distribution='humble';ros_model_sha256='invalid'}) $temporary } 'Missing/invalid supplemental ROS hashes must fail.'
$cliPreflight=Get-PythonCliPreflightMarker ('c'*40) ('d'*40) '104'
Assert-Test ($cliPreflight.StartsWith('<!-- wss-python-cli-preflight:v1 ',[StringComparison]::Ordinal)) 'CLI post-merge marker compatibility changed.'
Assert-Test ((Get-PythonApplicationPreflightMarker 'ros' ('c'*40) ('e'*40) '105').StartsWith('<!-- wss-python-ros-preflight:v1 ',[StringComparison]::Ordinal)) 'ROS post-merge marker missing.'
Assert-Rejected { Get-PythonApplication 'gui' } 'Unknown role must not widen publication scope.'
Assert-Rejected { Assert-PythonDiff @('src/unrelated.py') @((Get-PythonApplication 'ros').gitlink) } 'ROS publication must be gitlink-only.'
Assert-PythonDiff @('HFI_WSS_Python_Interface') @((Get-PythonApplication 'ros').gitlink)
$checks++
Assert-Rejected { Assert-PythonMergedApplicationPreflight $v1 'ros' ('c'*40) ('e'*40) '105' 'unused' $null } 'Legacy proof must fail before any ROS evidence lookup.'
Assert-Rejected { Get-PythonEvidence $PythonCliRepository '105' ('e'*40) 'ros' $candidate 'unused' $null } 'CLI repository evidence cannot be relabeled as ROS.'
# Resolve the actual repository record explicitly; no generated payload/evidence.
$repositoryRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$payloadRecord=Get-Content (Join-Path $repositoryRoot '.github/python-candidate.json') -Raw | ConvertFrom-Json
Assert-PythonProjection (Join-Path $repositoryRoot 'Cs_Libraries') $payloadRecord
$checks++
$badPayload=$payloadRecord | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$badPayload.files[0].sha256='0'*64
Assert-Rejected { Assert-PythonProjection (Join-Path $repositoryRoot 'Cs_Libraries') $badPayload } 'Wrong original payload hash must fail.'
$badPayload=$payloadRecord | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$badPayload.projection_sha256='0'*64
Assert-Rejected { Assert-PythonProjection (Join-Path $repositoryRoot 'Cs_Libraries') $badPayload } 'Wrong original payload digest must fail.'
$badCandidate=$candidate.Clone();$badCandidate.artifact_id='999'
Assert-Rejected { Assert-PythonSameCandidate $badCandidate $candidate } 'Exact producer artifact ID must remain bound.'

# Exercise the actual preflight request builder with queued-only API stubs.
# No remote command runs and no successful ROS runtime evidence is fabricated.
$script:posted=$null;$script:requestRole='cli';$script:ambiguous=$false;$script:wrongSource=$false
function Invoke-PythonGh([string[]]$Arguments) {
    if ($Arguments[-1] -notlike '*wss-preflight.yml/runs?*') { throw 'Unexpected unit API request.' }
    if (!$script:posted -and !$script:ambiguous) { return '[{"workflow_runs":[]}]' }
    $source=if ($script:requestRole -ceq 'wrapper') { 'c'*40 } elseif ($script:requestRole -ceq 'ros') { 'e'*40 } else { 'd'*40 }
    if ($script:wrongSource) { $source='f'*40 }
    $run=@{id='900';head_sha=$source;status='queued';display_title="WSS preflight 123 / wss-123-456-$('c'*40)-$(if ($script:requestRole -ceq 'ros') {'e'*40} else {'d'*40})"}
    $runs=@($run);if ($script:ambiguous) { $runs+=@($run) }
    ConvertTo-Json -InputObject @(@{workflow_runs=$runs}) -Depth 8 -Compress
}
function gh { $script:posted=($input -join "`n") | ConvertFrom-Json; $global:LASTEXITCODE=0 }
$savedPreflightToken=$env:PYTHON_PREFLIGHT_TOKEN
$env:PYTHON_PREFLIGHT_TOKEN='unit-only-no-credentials'
foreach ($role in @('wrapper','cli','ros')) {
    $script:requestRole=$role;$script:posted=$null
    $repo=if ($role -ceq 'wrapper') { $PythonWrapperRepository } else { (Get-PythonApplication $role).repository }
    $appSha=if ($role -ceq 'ros') { 'e'*40 } else { 'd'*40 }
    $queued=Start-PythonPreflight $repo $candidate ('c'*40) $appSha -NoWait
    Assert-Test ($queued.status -ceq 'queued') 'NoWait must not claim completed acceptance.'
    Assert-Test ($script:posted.ref -ceq 'dev') 'Preflights must target dev.'
    Assert-Test ($script:posted.inputs.wrapper_sha -ceq ('c'*40)) 'Preflight wrapper source changed.'
    $field=if ($role -ceq 'ros') {'ros_sha'} else {'cli_sha'}
    Assert-Test ($script:posted.inputs.$field -ceq $appSha) 'Preflight application source changed.'
    $unexpected=if ($role -ceq 'ros') {'cli_sha'} else {'ros_sha'}
    Assert-Test ($script:posted.inputs.PSObject.Properties.Name -cnotcontains $unexpected) 'Preflight inputs coupled independent applications or changed CLI contract.'
}
$script:posted=$null;$script:ambiguous=$true
Assert-Rejected { Start-PythonPreflight $PythonRosRepository $candidate ('c'*40) ('e'*40) -NoWait } 'Ambiguous preflight correlation must fail without redispatch.'
Assert-Test (!$script:posted) 'Ambiguous correlation must not dispatch.'
$script:ambiguous=$false;$script:wrongSource=$true;$script:requestRole='ros';$script:posted=$null
Assert-Rejected { Start-PythonPreflight $PythonRosRepository $candidate ('c'*40) ('e'*40) -NoWait } 'Source-raced correlated preflight must fail.'
$script:wrongSource=$false;$script:posted=$null
Assert-Rejected { Start-PythonPreflight 'cwru-non-academic/Unknown' $candidate ('c'*40) ('e'*40) -NoWait } 'Unknown dispatch repository must fail.'
Assert-Test (!$script:posted) 'Unknown repository must not dispatch.'
$env:PYTHON_PREFLIGHT_TOKEN=$null
Assert-Rejected { Start-PythonPreflight $PythonRosRepository $candidate ('c'*40) ('e'*40) -NoWait } 'Missing scoped token must fail before dispatch.'
Assert-Test (!$script:posted) 'Missing token must not dispatch.'
$env:PYTHON_PREFLIGHT_TOKEN=$savedPreflightToken

# Queue metadata below is a unit stub, never green conformance evidence. Every
# wait fails deliberately; no approval may be emitted and both apps are attempted.
$script:attempts=[Collections.Generic.List[string]]::new()
function Start-PythonPreflight($Repository,$Candidate,$WrapperSha,$ApplicationSha,[switch]$NoWait) {
    $script:attempts.Add($Repository)
    if ($Repository -ceq $PythonCliRepository) { throw 'Unit CLI dispatch failure.' }
    [pscustomobject]@{id='900';status='queued'}
}
function Wait-PythonRun($Repository,$RunId,$Sha,$Workflow,$Event) { throw 'Unit preflight has not passed.' }
Assert-Rejected { New-PythonFanoutApproval $candidate ('c'*40) ('d'*40) ('e'*40) ([pscustomobject]@{fixture_commit=('f'*40);fixture_sha256=('1'*64)}) } 'Failed/queued preflights cannot emit approval.'
Assert-Test ($script:attempts.Count -eq 3 -and $script:attempts[2] -ceq $PythonRosRepository) 'CLI failure must not prevent independent ROS dispatch.'
Write-Output "PASS: $checks Python fan-out contract/rejection checks; no ROS runtime acceptance fabricated."
