param()
$ErrorActionPreference='Stop'
# Execute the actual helper bodies with deterministic API/file fixtures, never native runtimes.
$family='Python'
$source=Get-Content "$PSScriptRoot/../PythonPromotion.ps1" -Raw
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Invalid PowerShell source.'}
foreach($name in @('Get-PythonEvidence','Assert-PythonApproval','Assert-PythonMergedApplicationPreflight')) {
    $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true)
    Invoke-Expression $fn.Extent.Text
}
$script:checks=0
function Check($ok,$message){if(!$ok){throw $message};$script:checks++}
function Reject([scriptblock]$action){$failed=$false;try{& $action|Out-Null}catch{$failed=$true};Check $failed 'Expected rejection.'}
$PythonWrapperRepository='owner/wrapper'
$MatlabProjectionFiles=@('one')
function Get-PythonApplication($Role){[pscustomobject]@{repository="owner/$Role";source_field=($Role+'_sha');acceptance='acceptance'}}
function Wait-PythonRun { [pscustomobject]@{run_attempt=2;head_branch='dev'} }
function Get-WssCiChannel {'dev'}
function Get-PythonProducerContract {'macos-ble-v1'}
function Get-PythonEvidenceJobs { @('acceptance') }
function Get-PythonEvidenceFiles { @('evidence.json') }
function Get-PythonProjectionFiles { @('one') }
function Get-WssUniversalContract {'macos-ble-v1'}
function Get-PythonProjectionDigest {'projection'}
function Assert-PythonSameCandidate {if($script:scenario -eq 'semantic'){throw 'Candidate mismatch'}}
function Assert-PythonProducer {}
function Assert-PythonFanoutApproval {}
function Assert-PythonSha {}
function Get-PythonApprovalRoles { $script:roles }
function Assert-PythonResults {}
function Assert-PythonMultiStageEvidence {}
function Assert-PythonRosReports {if($script:scenario -eq 'ros'){throw 'Invalid DDS evidence'}}
function Assert-PythonPlatformEvidence {if($script:scenario -eq 'platform'){throw 'Invalid platform evidence'}}
function Assert-WssMacOSPair {}
function Get-MatlabNativeTestContract { @{} }
function Assert-MatlabNativeTests {if($script:scenario -eq 'native'){throw 'Invalid native suite'}}
function Assert-MatlabNativeSummary {}
function Assert-MatlabMacCoverage {if($script:scenario -eq 'platform'){throw 'Invalid macOS evidence'}}
function Invoke-PythonGh {throw 'Receipt path must not use unbound downloads/jobs.'}
function Start-WssCiPreflightProof($Repository,$RunId,$SourceSha,$Root,$ExpectedAttempt){
 Check ($ExpectedAttempt -eq 2) 'Must capture the observed attempt.'
 if($script:scenario -eq 'start-drift'){throw 'Attempt moved'}
 $names=if($family -eq 'Python'){@('acceptance')}else{$p=if($script:role -eq 'wrapper'){'Preflight'}else{'CLI preflight'};@("$p behavioral tests","$p compatibility (Windows)","$p compatibility (Ubuntu)","$p compatibility (macOS)")}
 $jobs=@($names|ForEach-Object{[pscustomobject]@{id='1';name=$_;status='completed';conclusion='success'}})
 if($script:scenario -eq 'jobs'){$jobs=@()}
 [pscustomobject]@{Run=[pscustomobject]@{run_attempt=2;head_branch='dev'};Jobs=$jobs;repository=$Repository;run_id=$RunId;source_sha=$SourceSha}
}
function Read-WssCiPreflightArtifact($Proof,$Name,$Destination){
 if($script:scenario -in @('wrong-id','duplicate-artifact','deleted-artifact','replaced-artifact')){throw 'Artifact identity rejected'}
 $script:artifacts.Add($Name)
}
function Complete-WssCiPreflightProof($Proof){
 $script:completed++
 if($script:scenario -eq 'end-drift'){throw 'Attempt moved during semantics'}
 [pscustomobject]@{repository=$Proof.repository;run_id=$Proof.run_id;source_sha=$Proof.source_sha;workflow='.github/workflows/wss-preflight.yml';attempt=2;jobs=@($Proof.Jobs);artifacts=@($script:artifacts.ToArray());logs=@()}
}
function Test-Path { $false }
function Get-FileHash { [pscustomobject]@{Hash='hash'} }
function Get-ChildItem($LiteralPath,[switch]$Recurse,[switch]$File,[switch]$Force){
 if($LiteralPath -match 'normalized$'){[pscustomobject]@{Name='candidate.json';PSIsContainer=$false};return}
 if($LiteralPath -match 'packaged-macos$'){[pscustomobject]@{Name='compatibility.json';PSIsContainer=$false};return}
 $names=if($family -eq 'Python'){@('evidence.json')}else{@('evidence.json','summary.json','projection.json')}
 $names|ForEach-Object{[pscustomobject]@{FullName=(Join-Path $LiteralPath $_)}}
}
function Get-Content($LiteralPath,[switch]$Raw){
 if($LiteralPath -match 'candidate.json$'){return ($script:candidate|ConvertTo-Json)}
 if($LiteralPath -match 'projection.json$'){return (@{schema=('wss-'+$family.ToLower()+'-projection/v1');candidate=$script:candidate;files=@(@{source='one'});projection_sha256='projection';bootstrap_reference=$false}|ConvertTo-Json -Depth 8)}
 if($LiteralPath -match 'platform.json$'){return '{"python_smoke_sha256":"hash"}'}
 if($LiteralPath -notmatch 'evidence.json$'){return '{}'}
 $e=@{schema=('wss-'+$family.ToLower()+'-evidence/v1');execution='pythonnet';python_executed=$true;role=$script:role;mode='candidate';run_repository=$script:repo;run_id='10';run_sha='source';wrapper_sha='source';cli_sha='source';ros_sha='source';fixture_sha='fixture';fixture_sha256='fixturehash';python='3';pythonnet='3';sdk='9';target_framework='net9.0';test_framework='NUnit 3.14.0';discovered=16;executed=16;passed=16;failed=0;skipped=0;assertion_expressions=20;results_sha256='hash';log_sha256='hash';summary_sha256='hash';projection_sha256='projection';candidate=$script:candidate;matlab_release='R'}
 if($family -eq 'Matlab'){$e.execution='matlab-native'}
 if($script:scenario -eq 'source'){$e.run_sha='wrong'}
 $e|ConvertTo-Json -Depth 8
}
$script:candidate=@{repository='core';commit='sha';run_id='1';artifact_id='2';archive='a';sha256='hash'}
$config=@{fixture_commit='fixture';fixture_sha256='fixturehash';python_version='3';pythonnet_version='3';dotnet_sdk='9';matlab_release='R'}
$script:roles=if($family -eq 'Python'){@('wrapper','cli','ros')}else{@('wrapper','cli')}
foreach($script:role in $script:roles){
 $script:repo="owner/$role"
 foreach($script:scenario in @('ok','start-drift','end-drift','jobs','wrong-id','duplicate-artifact','deleted-artifact','replaced-artifact','semantic','source','platform',$(if($family -eq 'Matlab'){'native'}elseif($role -eq 'ros'){'ros'}else{'semantic'}))){
  $script:artifacts=[Collections.Generic.List[string]]::new();$script:completed=0;$snapshot=$null
  $action={Get-PythonEvidence $script:repo '10' 'source' $script:role $script:candidate (Join-Path ([IO.Path]::GetTempPath()) 'receipt-stub') $config -ReceiptSnapshot ([ref]$snapshot)}
  if($scenario -eq 'ok'){$e=& $action;Check ($snapshot.attempt -eq 2) 'Original attempt lost';Check ($e.role -eq $role) 'Legacy return changed';Check ($script:artifacts.Count -eq $(if($family -eq 'Python'){4}else{3})) 'Artifacts not bound'}
  else {Reject $action;Check ($null -eq $snapshot) 'Failed proof exposed descriptor'}
 }
}
$adapter=Microsoft.PowerShell.Management\Get-Content "$PSScriptRoot/../Verify-ReleaseAcceptance.ps1" -Raw
Check ($adapter -notmatch '\$preflights \+=') 'Hand-built receipt descriptor remains'
Check ($adapter -match '\-ReceiptSnapshots \$preflights') 'Adapter must require native proof'
Write-Output "$family native receipt binding: $script:checks source/stub checks passed."
# Exercise actual paired and merged assertions: publish captured proof only after source checks.
function Get-PythonEvidence($Repository,$RunId,$SourceSha,$Role,$Candidate,$Root,$Config,[ref]$ReceiptSnapshot){
 if($null -ne $ReceiptSnapshot){$ReceiptSnapshot.Value=[pscustomobject]@{repository=$Repository;run_id=$RunId;attempt=2;source_sha=$SourceSha}}
 [pscustomobject]@{wrapper_sha=$(if($script:badPair){'wrong'}else{'source'});cli_sha='source';ros_sha='source';projection_sha256='projection';fixture_sha='fixture';fixture_sha256='fixturehash'}
}
$approval=@{candidate=$candidate;wrapper=@{source_sha='source';preflight_run_id='10'};cli=@{source_sha='source';preflight_run_id='11'};ros=@{source_sha='source';preflight_run_id='12'};projection_sha256='projection';fixture=@{commit='fixture';sha256='fixturehash'}}
$script:badPair=$false
$list=[Collections.Generic.List[object]]::new()
Assert-PythonApproval $approval 'stub' $config -ReceiptSnapshots $list
Check ($list.Count -eq $script:roles.Count) 'Paired proof descriptors lost'
Check ($list[0].attempt -eq 2) 'Paired assertion replaced original attempt'
Assert-PythonApproval $approval 'stub' $config
$script:badPair=$true
$list=[Collections.Generic.List[object]]::new()
Reject {Assert-PythonApproval $approval 'stub' $config -ReceiptSnapshots $list}
Check ($list.Count -eq 0) 'Invalid paired semantics exposed descriptor'
foreach($role in @($script:roles|Where-Object{$_ -ne 'wrapper'})){
 $list=[Collections.Generic.List[object]]::new()
 Reject {Assert-PythonMergedApplicationPreflight $approval $role 'source' 'source' '13' 'stub' $config -ReceiptSnapshots $list}
 Check ($list.Count -eq 0) 'Invalid merged semantics exposed descriptor'
 $script:badPair=$false
 Assert-PythonMergedApplicationPreflight $approval $role 'source' 'source' '13' 'stub' $config -ReceiptSnapshots $list
 Check ($list.Count -eq 1 -and $list[0].attempt -eq 2) 'Merged proof descriptor lost'
 Assert-PythonMergedApplicationPreflight $approval $role 'source' 'source' '13' 'stub' $config
 $script:badPair=$true
}
Write-Output "$family total native receipt binding: $script:checks source/stub checks passed."