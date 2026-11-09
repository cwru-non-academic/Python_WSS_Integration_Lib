param([string]$CommonRoot=(Join-Path $PSScriptRoot '../wss-ci'),[ValidateSet('dev','main')][string]$Channel='dev')
# Synthetic external GitHub data only. No native binaries or runtime acceptance claims.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../PythonPromotion.ps1"
. (Join-Path $CommonRoot 'Preflight.ps1')
. (Join-Path $CommonRoot 'Evidence.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('python-real-bridge-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($fixture)
$oldNode=$env:NODE_OPTIONS;$oldRoutes=$env:WSS_TEST_GH_RESPONSES;$oldChannel=$env:WSS_CI_CHANNEL
$env:WSS_CI_CHANNEL=$Channel
$env:NODE_OPTIONS='--import '+([uri](Join-Path $CommonRoot 'tests/receipt-gh-preload.mjs')).AbsoluteUri
$env:WSS_TEST_GH_RESPONSES=Join-Path $fixture 'routes.json'
$script:routes=[Collections.Generic.List[object]]::new()
$script:nativeCalls=[Collections.Generic.List[object]]::new()
$script:unexpectedNativeCalls=0
function Add-Route([string[]]$Arguments,$Json){$script:routes.Add(@{args=$Arguments;json=$Json})}
function Invoke-PythonGh([string[]]$Arguments){
 $script:nativeCalls.Add(@($Arguments))
 $key=ConvertTo-Json -InputObject $Arguments -Compress
 $match=@($script:routes|Where-Object {(ConvertTo-Json -InputObject $_.args -Compress) -ceq $key})
 if($match.Count -ne 1){$script:unexpectedNativeCalls++;throw "Unexpected native GitHub request: $key"}
 ConvertTo-Json -InputObject $match[0].json -Depth 100 -Compress
}
function Save-Json($Path,$Object){$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,(ConvertTo-Json -InputObject $Object -Depth 100 -Compress),[Text.UTF8Encoding]::new($false))}
function Hash($Path){(Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant()}
function Add-Archive($Repository,$RunId,$Sha,$Id,$Name,$Directory){
 $zip=Join-Path $fixture "$Id.zip"
 $archive=[IO.Compression.ZipFile]::Open($zip,[IO.Compression.ZipArchiveMode]::Create)
 try{foreach($file in Get-ChildItem -LiteralPath $Directory -File -Recurse){$relative=[IO.Path]::GetRelativePath($Directory,$file.FullName).Replace('\','/');$null=[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$relative)}}finally{$archive.Dispose()}
 $metadata=@{id=$Id;name=$Name;expired=$false;digest=('sha256:'+(Hash $zip));workflow_run=@{id=$RunId;head_sha=$Sha}}
 Add-Route @('api',"repos/$Repository/actions/artifacts/$Id") $metadata
 $script:routes.Add(@{args=@('api',"repos/$Repository/actions/artifacts/$Id/zip");file=$zip})
 $metadata
}
function Save-Routes {Save-Json $env:WSS_TEST_GH_RESPONSES @{routes=$script:routes.ToArray();calls_file=(Join-Path $fixture 'calls.jsonl')}}
function Check($Condition,$Message){if(!$Condition){throw $Message}}
function Assert-TransportCalls {
 # The common preload records every gh attempt before matching a route, including
 # rejected calls. Validate independently of any expected-error catch.
 Check ($script:unexpectedNativeCalls -eq 0) 'Unexpected native GitHub operation attempted.'
 $calls=@($script:nativeCalls.ToArray())
 $callsPath=Join-Path $fixture 'calls.jsonl'
 if(Test-Path -LiteralPath $callsPath){foreach($line in [IO.File]::ReadAllLines($callsPath)){if($line){$calls+=,@($line|ConvertFrom-Json)}}}
 foreach($call in $calls){
  $key=ConvertTo-Json -InputObject @($call) -Compress
  $matches=@($script:routes|Where-Object {(ConvertTo-Json -InputObject $_.args -Compress) -ceq $key})
  Check ($matches.Count -eq 1) "Unexpected/ambiguous recorded GitHub attempt: $key"
 }
}
function Reset-TransportCalls {
 Assert-TransportCalls
 $script:nativeCalls.Clear()
 [IO.File]::WriteAllText((Join-Path $fixture 'calls.jsonl'),'')
}
function Assert-Rejected([scriptblock]$Action,[string]$Message,[string]$NodeMessage=''){
 # Fixture setup is complete before this function. Only the real action is caught.
 $routesBefore=[IO.File]::ReadAllText($env:WSS_TEST_GH_RESPONSES)
 $stderrPath=Join-Path $fixture ([guid]::NewGuid().ToString('N')+'.synthetic.stderr')
 $failure=$null;$output=[Collections.Generic.List[object]]::new();$global:LASTEXITCODE=0
 try{& $Action 2>$stderrPath|ForEach-Object{$output.Add($_)}}catch{$failure=$_}
 $exitCode=$global:LASTEXITCODE
 Assert-TransportCalls
 Check ([IO.File]::ReadAllText($env:WSS_TEST_GH_RESPONSES) -ceq $routesBefore) 'Rejected action changed fixture routes.'
 Check ($output.Count -eq 0) 'Rejected action exposed a proof.'
 Check ($null -ne $failure) "Expected rejection: $Message"
 Check ($failure.Exception.Message -ceq $Message) "Wrong rejection: expected '$Message', got '$($failure.Exception.Message)'"
 $stderr=if(Test-Path -LiteralPath $stderrPath){[IO.File]::ReadAllText($stderrPath)}else{''}
 if($NodeMessage){
  $errors=@([regex]::Matches($stderr,'(?m)^[A-Za-z]*Error: (.+)\r?$'))
  Check ($exitCode -eq 1 -and $errors.Count -eq 1 -and $errors[0].Groups[1].Value.TrimEnd([char]13) -ceq $NodeMessage) "Wrong synthetic proof failure: expected '$NodeMessage' (exit 1), got exit $exitCode and $stderr"
 }else{Check ($exitCode -eq 0 -and [string]::IsNullOrWhiteSpace($stderr)) 'Semantic rejection was caused by a subprocess error.'}
}
function Assert-CollectionCalls([string]$Repository,[string]$RunId,[string]$Change,[string]$ArtifactId,$Bindings){
 Check ($script:nativeCalls.Count -eq 0) 'Collection attempted native transport.'
 $paths=@("repos/$Repository/actions/runs/$RunId")
 if($Change -cne 'attempt'){$paths+="repos/$Repository/actions/runs/$RunId/attempts/2/jobs?per_page=100&page=1"}
 if($Change -cnotin @('attempt','jobs')){
  foreach($binding in $Bindings){
   $listPath="repos/$Repository/actions/runs/$RunId/artifacts?per_page=100&page=1"
   $paths+=$listPath
   if($Change -ceq 'deleted-artifact'){break}
   if($binding.id -ceq ($RunId+'1')){
    if($Change -cne 'duplicate-artifact'){$paths+="repos/$Repository/actions/artifacts/$ArtifactId"}
    break
   }
   $metadataPath="repos/$Repository/actions/artifacts/$($binding.id)"
   $paths+=@($metadataPath,"$metadataPath/zip",$listPath,$metadataPath)
  }
 }
 $actual=@([IO.File]::ReadAllLines((Join-Path $fixture 'calls.jsonl'))|Where-Object {$_}|ForEach-Object {$a=@($_|ConvertFrom-Json);Check ($a.Count -eq 2 -and $a[0] -ceq 'api') 'Unexpected collection call shape.';$a[1]})
 Check (($actual|ConvertTo-Json -Compress) -ceq ($paths|ConvertTo-Json -Compress)) "Wrong collection phase/calls for $Change"
}
try {
 $config=Get-Content "$PSScriptRoot/../../python-ci.json" -Raw|ConvertFrom-Json
 $sha='a'*40;$candidate=@{repository='cwru-non-academic/WSSCore';commit=('b'*40);run_id='900';artifact_id='901';archive='WSS-Universal-ci.zip';sha256=('c'*64)}
 $files=@($WssMacOSUniversalFiles|ForEach-Object{@{source=$_;sha256=('d'*64)}})
 $projection=@{schema='wss-python-projection/v1';candidate=$candidate;universal_contract='macos-ble-v1';files=$files;projection_sha256=(Get-PythonProjectionDigest $files)}
 Add-Route @('api',"repos/cwru-non-academic/WSSCore/contents/tools/ArtifactBuild/manifests/universal.json?ref=$($candidate.commit)") @{encoding='base64';content=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((@{files=$WssMacOSUniversalFiles}|ConvertTo-Json -Compress)))}
 $approval=[pscustomobject]@{schema='wss-python-promotion/v2';candidate=$candidate;wrapper=@{source_sha=$sha;preflight_run_id='101'};cli=@{source_sha=$sha;preflight_run_id='102'};ros=@{source_sha=$sha;preflight_run_id='103'};fixture=@{commit=$config.fixture_commit;sha256=$config.fixture_sha256};projection_sha256=$projection.projection_sha256}
 foreach($role in @('wrapper','cli','ros')){
  $repo=if($role -eq 'wrapper'){$PythonWrapperRepository}else{(Get-PythonApplication $role).repository};$runId=[string]$approval.$role.preflight_run_id
  $run=@{id=$runId;run_attempt=2;repository=@{full_name=$repo};head_repository=@{full_name=$repo};path='.github/workflows/wss-preflight.yml';head_sha=$sha;head_branch=$Channel;event='workflow_dispatch';status='completed';conclusion='success'}
  Add-Route @('api',"repos/$repo/actions/runs/$runId") $run
  $j=0;$jobs=@((Get-PythonEvidenceJobs $role 'macos-ble-v1')|ForEach-Object{$j++;@{id=([int]$runId*10+$j);name=$_;status='completed';conclusion='success'}})
  Add-Route @('api',"repos/$repo/actions/runs/$runId/attempts/2/jobs?per_page=100&page=1") @{jobs=$jobs;total_count=$jobs.Count}
  $rich=Join-Path $fixture "$role-rich"
  foreach($stage in @('single','multi')){
   $dir=if($stage -eq 'single'){$rich}else{Join-Path $rich 'multi'};$null=[IO.Directory]::CreateDirectory($dir)
   Save-Json (Join-Path $dir 'projection.json') $projection
   $cases=if($stage -eq 'single'){@($config.dotnet_expected_cases)}else{@($config.dotnet_expected_cases|Select-Object -First 10)+@($config.multidevice_expected_cases)}
   $xml='<test-run result="Passed" testcasecount="16" total="16" passed="16" failed="0" skipped="0" inconclusive="0">'+(($cases|ForEach-Object{'<test-case name="'+[Security.SecurityElement]::Escape($_)+'" result="Passed" />'}) -join '')+'</test-run>'
   [IO.File]::WriteAllText((Join-Path $dir 'results.xml'),$xml);[IO.File]::WriteAllText((Join-Path $dir 'dotnet.log'),'synthetic contract fixture, not runtime proof')
   $e=@{schema='wss-python-evidence/v1';candidate=$candidate;execution='pythonnet';python_executed=$true;role=$role;stage=$stage;mode='candidate';run_repository=$repo;run_id=$runId;run_sha=$sha;wrapper_sha=$sha;cli_sha=$sha;ros_sha=$sha;fixture_sha=$config.fixture_commit;fixture_sha256=$config.fixture_sha256;python=$config.python_version;pythonnet=$config.pythonnet_version;sdk=$config.dotnet_sdk;target_framework='net9.0';test_framework='NUnit 3.14.0';discovered=16;executed=16;passed=16;failed=0;skipped=0;assertion_expressions=20;results_sha256=(Hash (Join-Path $dir 'results.xml'));log_sha256=(Hash (Join-Path $dir 'dotnet.log'));projection_sha256=$projection.projection_sha256}
   if($role -eq 'ros'){
    $observations=@(foreach($scenario in @(@('P','PW','H03'),@('PD','PW','H03'),@('P','PA','H03'),@('PD','PA','H03'),@('P','PW','J03'))){foreach($devices in 1..3){@{mode=$scenario[0];amplitude_mode=$scenario[1];firmware=$scenario[2];devices=$devices;initialization_conformant=$true;protocol_errors=0;model_path_drive=@(1..($devices*3))}}})
    Save-Json (Join-Path $rich 'ros-model.json') @{schema='wss-ros-emulator/v1';tests=5;failed=0;skipped=0;observations=$observations}
    foreach($layout in @('symlink','copy')){Save-Json (Join-Path $rich "ros-native-$layout.json") @{schema='wss-ros-native/v1';passed=$true;channels=@(1..9)}}
    $e.native_ros_distribution='humble';$e.ros_model_sha256=Hash (Join-Path $rich 'ros-model.json');$e.ros_native_symlink_sha256=Hash (Join-Path $rich 'ros-native-symlink.json');$e.ros_native_copy_sha256=Hash (Join-Path $rich 'ros-native-copy.json')
   }
   Save-Json (Join-Path $dir 'evidence.json') $e
  }
  $artifacts=[Collections.Generic.List[object]]::new();$artifacts.Add((Add-Archive $repo $runId $sha ($runId+'1') 'python-preflight-evidence' $rich));$n=1
  foreach($platform in @('Windows','Ubuntu','macOS')){
   $n++;$platformRoot=Join-Path $fixture "$role-$platform"
   $architectures=if($platform -eq 'macOS'){@('x64','arm64')}else{@('x64')}
   foreach($arch in $architectures){
    $dir=if($platform -eq 'macOS'){Join-Path $platformRoot $arch}else{$platformRoot};$null=[IO.Directory]::CreateDirectory($dir)
    $smoke=@{schema='wss-python-smoke/v2';os='darwin';architecture=$arch;dotnet_process_architecture=$arch;os_architecture=$arch;runner_architecture=$arch;translated=$false;execution='native';physical_io=$false;contract='macos-ble-v1';macos_ble_declared=$true;cli_routing=($role -eq 'cli');ble='passed:synthetic'}
    Save-Json (Join-Path $dir 'python-smoke.json') $smoke
    [IO.File]::WriteAllText((Join-Path $dir 'platform.trx'),'<TestRun><UnitTestResult testName="FacadeLoadsCurrentPlatformBackendAndDependencies" outcome="Passed" /></TestRun>')
    $proof=@{schema='wss-python-platform/v2';candidate=$candidate;mode='candidate';wrapper_sha=$sha;cli_sha=$(if($role -eq 'cli'){$sha}else{''});fixture_sha=$config.fixture_commit;projection_sha256=$projection.projection_sha256;universal_contract='macos-ble-v1';run_repository=$repo;run_id=$runId;run_sha=$sha;ble='passed:synthetic';os='macOS fixture';architecture=$arch;execution='native';python_smoke_sha256=(Hash (Join-Path $dir 'python-smoke.json'));platform_trx_sha256=(Hash (Join-Path $dir 'platform.trx'))}
    Save-Json (Join-Path $dir 'platform.json') $proof
    Save-Json (Join-Path $dir 'outcome.json') @{schema='wss-macos-worker/v1';architecture=$arch;conclusion='success';repository=$repo;run_id=$runId;source_sha=$sha;ci=(New-WssCiEvidenceIdentity $repo $runId '2' $sha $arch)}
   }
   if($platform -eq 'macOS'){Save-Json (Join-Path $platformRoot 'macos.json') (Get-WssMacOSPair $platformRoot $repo $runId $sha '2')}
   $artifacts.Add((Add-Archive $repo $runId $sha ($runId+[string]$n) "python-preflight-platform-$platform" $platformRoot))
  }
  Add-Route @('api',"repos/$repo/actions/runs/$runId/artifacts?per_page=100&page=1") @{artifacts=$artifacts.ToArray();total_count=$artifacts.Count}
  Save-Routes
  $snapshot=$null
  $e=Get-PythonEvidence $repo $runId $sha $role $candidate (Join-Path $fixture "$role-accepted") $config -ReceiptSnapshot ([ref]$snapshot)
  Check ($e.role -ceq $role -and $snapshot.attempt -eq 2 -and $snapshot.artifacts.Count -eq 4 -and $snapshot.jobs.Count -eq $jobs.Count) 'Real native/bridge descriptor mismatch'
  Check (@($snapshot.artifacts|Where-Object digest -notmatch '^sha256:[a-f0-9]{64}$').Count -eq 0) 'Actual ZIP digests absent'
  Assert-TransportCalls
  # Authenticated bytes can still be semantically invalid: keep real ZIP verification,
  # change source identity inside the rich artifact, and require the native validator to reject.
  $evidencePath=Join-Path $rich 'evidence.json';$originalEvidence=[IO.File]::ReadAllText($evidencePath)
  $badEvidence=$originalEvidence|ConvertFrom-Json;$badEvidence.run_sha='f'*40;Save-Json $evidencePath $badEvidence
  $richZip=Join-Path $fixture ($runId+'1.zip');$originalZip=[IO.File]::ReadAllBytes($richZip);$originalDigest=$artifacts[0].digest
  [IO.File]::Delete($richZip)
  $archive=[IO.Compression.ZipFile]::Open($richZip,[IO.Compression.ZipArchiveMode]::Create)
  try{foreach($file in Get-ChildItem -LiteralPath $rich -File -Recurse){$relative=[IO.Path]::GetRelativePath($rich,$file.FullName).Replace('\','/');$null=[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$relative)}}finally{$archive.Dispose()}
  $artifacts[0].digest='sha256:'+(Hash $richZip);Save-Routes
  Check (($badEvidence.run_sha -ceq ('f'*40)) -and $artifacts[0].digest -ceq ('sha256:'+(Hash $richZip))) 'Invalid authenticated-source fixture was not installed.'
  $badRoot=Join-Path $fixture "$role-invalid-native"
  Check (!(Test-Path -LiteralPath $badRoot)) 'Semantic fixture destination already exists.'
  Reset-TransportCalls
  $badSnapshot=$null
  Assert-Rejected {Get-PythonEvidence $repo $runId $sha $role $candidate $badRoot $config -ReceiptSnapshot ([ref]$badSnapshot)} 'Invalid runtime/source/fixture evidence.'
  Check ($null -eq $badSnapshot) 'Authenticated semantic failure exposed a receipt proof'
  Check ((Get-Content (Join-Path $badRoot 'evidence.json') -Raw|ConvertFrom-Json).run_sha -ceq ('f'*40)) 'Semantic rejection did not reach the authenticated invalid evidence.'
  $zipCalls=@([IO.File]::ReadAllLines((Join-Path $fixture 'calls.jsonl'))|Where-Object {$_}|ForEach-Object {,@($_|ConvertFrom-Json)}|Where-Object {$_[-1] -like '*/zip'})
  Check ($zipCalls.Count -eq 1 -and $zipCalls[0][-1] -ceq "repos/$repo/actions/artifacts/$($runId+'1')/zip") 'Semantic rejection did not follow exactly one rich artifact download.'
  [IO.File]::WriteAllText($evidencePath,$originalEvidence);[IO.File]::WriteAllBytes($richZip,$originalZip);$artifacts[0].digest=$originalDigest;Save-Routes
  # Recollect the actual returned descriptor through the real bridge after external state moves.
  $captured=$snapshot|ConvertTo-Json -Depth 100 -Compress
  $proof=[pscustomobject]@{Root=$fixture;State=@{descriptor=$snapshot}}
  foreach($change in @('attempt','jobs','artifact-digest','deleted-artifact','duplicate-artifact','wrong-id','replaced-artifact')){
   Assert-TransportCalls
   $originalDigest=$artifacts[0].digest;$originalJobName=$jobs[0].name
   $artifactRoutes=@($script:routes|Where-Object {$_.args[-1] -ceq "repos/$repo/actions/runs/$runId/artifacts?per_page=100&page=1"})
   Check ($artifactRoutes.Count -eq 1) 'Missing/ambiguous artifact-list fixture.'
   $artifactRoute=$artifactRoutes[0];$originalArtifacts=$artifactRoute.json.artifacts
   $metadataRoutes=@($script:routes|Where-Object {$_.args[-1] -ceq "repos/$repo/actions/artifacts/$($artifacts[0].id)"})
   Check ($metadataRoutes.Count -eq 1) 'Missing/ambiguous artifact metadata fixture.'
   $metadataRoute=$metadataRoutes[0];$originalMetadata=$metadataRoute.json;$replacementRoute=$null
   $expectedArtifactId=[string]$artifacts[0].id
   switch($change){
    attempt {$run.run_attempt=3;$expectedError='Preflight proved run/attempt changed';Check ($run.run_attempt -eq 3) 'Attempt fixture unchanged.'}
    jobs {$jobs[0].name='changed after rich proof';$expectedError='Native proved attempt job snapshot changed';Check ($jobs[0].name -cne $originalJobName) 'Jobs fixture unchanged.'}
    'artifact-digest' {$artifacts[0].digest='sha256:'+('0'*64);$expectedError='Native artifact replaced since rich validation';Check ($artifacts[0].digest -cne $originalDigest) 'Digest fixture unchanged.'}
    'deleted-artifact' {$artifactRoute.json.artifacts=@();$artifactRoute.json.total_count=0;$expectedError='Missing/duplicate/expired native artifact';Check ($artifactRoute.json.artifacts.Count -eq 0) 'Deleted artifact fixture unchanged.'}
    'duplicate-artifact' {$artifactRoute.json.artifacts=@($originalArtifacts)+@($originalArtifacts[0]);$artifactRoute.json.total_count=$originalArtifacts.Count+1;$expectedError='Missing/duplicate/expired native artifact';Check ($artifactRoute.json.artifacts.Count -eq ($originalArtifacts.Count+1)) 'Duplicate artifact fixture unchanged.'}
    'wrong-id' {
     $wrong=$originalMetadata|ConvertTo-Json -Depth 20|ConvertFrom-Json;$wrong.id='9991';$metadataRoute.json=$wrong
     $expectedError='Native artifact owner/source/digest mismatch'
     Check ([string]$metadataRoute.json.id -cne [string]$originalArtifacts[0].id) 'Wrong-ID fixture unchanged.'
    }
    'replaced-artifact' {
     $replacement=$originalMetadata|ConvertTo-Json -Depth 20|ConvertFrom-Json;$replacement.id='9992'
     $artifactRoute.json.artifacts=@($replacement)+@($originalArtifacts|Select-Object -Skip 1)
     $replacementRoute=@{args=@('api',"repos/$repo/actions/artifacts/9992");json=$replacement};$script:routes.Add($replacementRoute)
     $expectedArtifactId='9992';$expectedError='Native artifact replaced since rich validation'
     Check ([string]$artifactRoute.json.artifacts[0].id -ceq '9992' -and $replacement.name -ceq $originalMetadata.name -and $replacement.digest -ceq $originalDigest) 'Replacement fixture identity/content mismatch.'
    }
   }
   Save-Routes
   Reset-TransportCalls
   Assert-Rejected {Complete-WssCiPreflightProof -Proof $proof} 'Authenticated native proof transport failed.' $expectedError
   Assert-CollectionCalls $repo $runId $change $expectedArtifactId $snapshot.artifacts
   Check (($snapshot|ConvertTo-Json -Depth 100 -Compress) -ceq $captured) 'Returned proof was replaced with fresh state'
   # Clear audited calls before restoring routes, whose only temporary member is
   # the replacement metadata endpoint. No expected-rejection catch covers setup.
   Reset-TransportCalls
   $run.run_attempt=2;$jobs[0].name=$originalJobName;$artifacts[0].digest=$originalDigest
   $artifactRoute.json.artifacts=$originalArtifacts;$artifactRoute.json.total_count=$originalArtifacts.Count
   $metadataRoute.json=$originalMetadata
   if($null -ne $replacementRoute){$null=$script:routes.Remove($replacementRoute)}
   Save-Routes
  }
  if($role -ne 'wrapper'){$list=[Collections.Generic.List[object]]::new();Assert-PythonMergedApplicationPreflight $approval $role $sha $sha $runId (Join-Path $fixture "merged-$role") $config -ReceiptSnapshots $list;Check ($list.Count -eq 1 -and $list[0].artifacts.Count -eq 4) 'Merged application lost native proof'}
 }
 Assert-TransportCalls
 Write-Output "Python real helper/bridge rich composition passed ($Channel), wrapper+CLI+ROS and merged CLI/ROS; synthetic data only."
} finally {$env:NODE_OPTIONS=$oldNode;$env:WSS_TEST_GH_RESPONSES=$oldRoutes;$env:WSS_CI_CHANNEL=$oldChannel}