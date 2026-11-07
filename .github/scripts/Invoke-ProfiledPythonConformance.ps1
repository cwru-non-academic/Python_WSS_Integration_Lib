# Additive profile-aware bootstrap. Existing historical runner/guards stay unchanged.
param(
    [Parameter(Mandatory)][string]$WrapperRoot,
    [Parameter(Mandatory)][string]$WrapperSha,
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$OutputRoot,
    [string]$ToolsRoot='', [string]$ToolsSha='',
    [string]$TestRoot='', [string]$TestSha='', [string]$TestRepository='', [string]$TestSelectionId='',
    [string]$CliRoot='', [string]$CliSha='',
    [ValidateSet('committed','candidate')][string]$Mode='committed',
    [ValidateSet('wrapper','cli')][string]$Role='wrapper',
    [ValidateSet('all','single','multi')][string]$Stage='all',
    [string]$ArtifactRoot='', [string]$CandidatePath='', [string]$PythonExe='python',
    [switch]$SelectionEnabledCampaign,
    [ValidateRange(30,1800)][int]$TimeoutSeconds=300
)
. "$PSScriptRoot/PythonContract.ps1"
. "$PSScriptRoot/PythonProfiles/Contract.ps1"
$toolBinding=$null
if($ToolsRoot -or $ToolsSha) {
    if($Mode -cne 'committed'){throw 'Explicit tooling binding currently supports ordinary committed validation only.'}
    . "$PSScriptRoot/PythonProfiles/Tooling.ps1"
    $toolBinding=Resolve-PythonOrdinaryTooling -ToolsRoot $ToolsRoot -ToolsSha $ToolsSha -ConfigPath $ConfigPath -WrapperRoot $WrapperRoot -WrapperSha $WrapperSha
    $config=$toolBinding.config
} else {
    if([IO.Path]::GetFullPath($ConfigPath) -cne [IO.Path]::GetFullPath((Join-Path $WrapperRoot '.github/python-ci.json'))){throw 'Runtime config must come from actual wrapper product.'}
    $config=Read-PythonProfileProductConfig $ConfigPath
}
Assert-PythonSource $WrapperRoot $WrapperSha
if($Mode -ceq 'committed' -and $CliRoot){Assert-PythonOrdinaryCliPair $CliRoot $CliSha $WrapperSha}
if($Role -ceq 'cli' -or $Mode -ceq 'candidate'){
    if(!$CliRoot -or !$CliSha){throw 'CLI/candidate validation requires exact paired CLI source.'}
    Assert-PythonSource $CliRoot $CliSha -IgnoreSubmodule
}
if(($Mode -ceq 'candidate' -or $TestRoot -or $TestSha -or $TestRepository -or $TestSelectionId) -and $config.baseline_ready -cne $true){throw 'Product baseline readiness cannot be overridden by test selection.'}
if(Test-Path -LiteralPath $OutputRoot){throw 'OutputRoot must be new.'}
$rootOutput=[IO.Path]::GetFullPath($OutputRoot)
foreach($source in @($WrapperRoot,$CliRoot,$TestRoot,$ToolsRoot) | Where-Object {$_}){
    $path=[IO.Path]::GetFullPath($source)
    if($rootOutput -eq $path -or $rootOutput.StartsWith($path+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Output must remain outside immutable source checkouts.'}
}
New-Item -ItemType Directory -Path $rootOutput | Out-Null
if($Mode -ceq 'candidate'){
    if(!$ArtifactRoot -or !$CandidatePath){throw 'Candidate mode requires authenticated resolver output; no fallback.'}
    $candidate=Get-Content -LiteralPath $CandidatePath -Raw | ConvertFrom-Json
    $projectionRoot=Join-Path $rootOutput 'projection'
    $projection=New-PythonProjection $ArtifactRoot $WrapperRoot $projectionRoot $candidate
}else{
    if($ArtifactRoot -or $CandidatePath){throw 'Committed mode cannot accept candidate overrides.'}
    $projection=Get-Content -LiteralPath (Join-Path $WrapperRoot '.github/python-candidate.json') -Raw | ConvertFrom-Json
    $projectionRoot=Join-Path $WrapperRoot $PythonPluginPath
    Assert-PythonProjection $projectionRoot $projection
    $candidate=$projection.candidate
}
# Metadata-only inspection happens only after exact universal inventory/hash verification.
$profile=Resolve-WssReviewedProfile $projectionRoot $candidate -SelectionEnabledCampaign:$SelectionEnabledCampaign
$contract=Get-PythonProfileContract $profile.profile
$tests=Resolve-PythonProfileTests $WrapperRoot $WrapperSha $TestRoot $TestSha $TestRepository $TestSelectionId $contract
$stages=if($Stage -ceq 'all'){if($profile.profile -ceq 'layered-v1'){@('single','multi')}else{@('single')}}else{@($Stage)}
if($profile.profile -ceq 'legacy-v1' -and $Stage -ceq 'multi'){throw 'Legacy has only its original complete single-stage suite.'}
$previousStage=$env:WSS_CONFORMANCE_STAGE
try {
foreach($currentStage in $stages){
    $Stage=$currentStage;$env:WSS_CONFORMANCE_STAGE=$Stage
    $OutputRoot=if($Stage -ceq 'multi'){Join-Path $rootOutput 'multi'}else{$rootOutput}
    if($Stage -ceq 'multi'){New-Item -ItemType Directory -Path $OutputRoot | Out-Null}
    $caseCount=if($Stage -ceq 'multi'){$contract.multi_cases.Count}else{$contract.single_cases.Count}
$harness=Join-Path $OutputRoot 'harness'
$pythonInfo = (& $PythonExe -c 'import json,sys,sysconfig,pythonnet,pathlib; print(json.dumps(dict(version=".".join(map(str,sys.version_info[:2])),home=sys.base_prefix,dll=str(pathlib.Path(sys.base_prefix)/("python"+str(sys.version_info.major)+str(sys.version_info.minor)+".dll")),assembly=str(pathlib.Path(pythonnet.__file__).parent/"runtime"/"Python.Runtime.dll"))))') | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $pythonInfo.version -cne $config.python_version) { throw 'Pinned Python/pythonnet runtime required.' }
$netVersion=(& $PythonExe -c 'from importlib.metadata import version; print(version("pythonnet"))').Trim()
if ($netVersion -cne $config.pythonnet_version) { throw 'Wrong pythonnet version.' }
$env:PYTHON_DLL=$pythonInfo.dll
$env:PYTHON_HOME=$pythonInfo.home
$env:PYTHONNET_RUNTIME='coreclr'
$env:PYTHONPATH=(& $PythonExe -c 'import site,os; print(os.pathsep.join(site.getsitepackages()))').Trim()
$env:PYTHONDONTWRITEBYTECODE='1'
$env:WSS_PYTHON_SOURCE=Join-Path $WrapperRoot 'src'
$env:WSS_CLI_SOURCE=if ($CliRoot) { Join-Path $CliRoot 'src' } else { '' }
$env:WSS_PYTHON_PAYLOAD=$projectionRoot
& (Join-Path $PSScriptRoot 'PythonProfiles/Prepare-Harness.ps1') -CanonicalFixturePath $contract.fixture -TestRoot $tests.root -ExpectedFixtureHash $contract.fixture_sha256 -ExpectedAssertions $contract.assertion_expressions -Destination $harness -ProjectionRoot $projectionRoot -Role $Role -CliRoot $CliRoot -PythonRuntimeAssembly $pythonInfo.assembly
if (!$?) { throw 'Portable harness preparation failed.' }
Push-Location $harness
try { $sdk=(& dotnet --version).Trim(); if ($LASTEXITCODE -ne 0 -or $sdk -cne $config.dotnet_sdk) { throw 'Wrong .NET SDK.' } } finally { Pop-Location }
$logPath=Join-Path $OutputRoot 'dotnet.log'
$errorPath=Join-Path $OutputRoot 'dotnet-stderr.log'
$nunit=Join-Path $OutputRoot 'nunit'
$arguments=@('test','Wss.DotNet.Conformance.Tests.csproj','--logger','"trx;LogFileName=results.trx"','--results-directory',('"'+(Join-Path $OutputRoot 'test-results')+'"'),'--blame-hang-timeout','2m','--',('NUnit.TestOutputXml="'+$nunit+'"'))
$process=Start-Process -FilePath (Get-Command dotnet).Source -WorkingDirectory $harness -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $logPath -RedirectStandardError $errorPath -PassThru
if (!$process.WaitForExit($TimeoutSeconds*1000)) { $process.Kill($true); $process.WaitForExit(); throw 'Disposable .NET conformance timed out; no acceptance evidence emitted.' }
if ((Get-Item -LiteralPath $errorPath).Length) { [IO.File]::AppendAllText($logPath,[IO.File]::ReadAllText($errorPath)) }
Get-Content -LiteralPath $logPath | Write-Output
if ($process.ExitCode -ne 0) { throw ".NET test exit $($process.ExitCode). Inspect dotnet.log." }
$results=@(Get-ChildItem -LiteralPath $nunit -Filter '*.xml' -File)
if ($results.Count -ne 1) { throw 'Expected exactly one real NUnit result file.' }
$xmlPath=Join-Path $OutputRoot 'results.xml'
Copy-Item -LiteralPath $results[0].FullName -Destination $xmlPath
Assert-PythonProfileResults $xmlPath $contract $Stage
foreach ($name in @('WSS_Core_Interface.dll','Newtonsoft.Json.dll','System.Security.Permissions.dll')) {
    $binary=Join-Path $harness "bin/Debug/net9.0/$name"
    if ((Get-FileHash -LiteralPath $binary).Hash -cne (Get-FileHash -LiteralPath (Join-Path $projectionRoot $name)).Hash) { throw "Test output used a different payload assembly: $name" }
}
Assert-PythonProjection $projectionRoot $projection
Assert-PythonSource $WrapperRoot $WrapperSha
if($Mode -ceq 'committed' -and $CliRoot){Assert-PythonOrdinaryCliPair $CliRoot $CliSha $WrapperSha}
if ($CliRoot) { Assert-PythonSource $CliRoot $CliSha -IgnoreSubmodule }
Assert-PythonProfileTestSource $tests
$inputs=Get-Content -LiteralPath (Join-Path $harness 'conformance-inputs.json') -Raw | ConvertFrom-Json
if ($inputs.assertion_expressions -ne $contract.assertion_expressions -or $inputs.canonical_fixture_sha256 -cne $contract.fixture_sha256) { throw 'Harness provenance mismatch.' }
$evidence=[ordered]@{
    schema='wss-python-profile-evidence/v1'; profile=$profile.profile; producer_commit=$candidate.commit; core_dll_sha256=$profile.core_dll_sha256; execution='pythonnet'; role=$Role; mode=$Mode; candidate=$candidate
    test_root=$tests.root; test_sha=$tests.sha; test_repository=$tests.repository; test_selection_id=$tests.selection_id; test_contract_sha256=$tests.contract_sha256
    wrapper_sha=$WrapperSha; cli_sha=$CliSha; fixture_sha=$contract.fixture_commit; fixture_sha256=$contract.fixture_sha256
    sdk=$sdk; target_framework='net9.0'; test_framework='NUnit 3.14.0'; python_executed=$true
    python=$pythonInfo.version; pythonnet=$netVersion
    run_repository=$env:GITHUB_REPOSITORY; run_id=$env:GITHUB_RUN_ID; run_sha=$env:GITHUB_SHA
    discovered=$caseCount; executed=$caseCount; passed=$caseCount; failed=0; skipped=0; assertion_expressions=$contract.assertion_expressions; stage=$Stage
    projection_sha256=$projection.projection_sha256
    results_sha256=(Get-FileHash -LiteralPath $xmlPath).Hash.ToLowerInvariant()
    log_sha256=(Get-FileHash -LiteralPath $logPath).Hash.ToLowerInvariant()
}
if($toolBinding){
    $evidence.tooling_root=$toolBinding.tooling_root
    $evidence.tooling_sha=$toolBinding.tooling_sha
    $evidence.tooling_config_sha256=$toolBinding.tooling_config_sha256
}
$evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'evidence.json')
$projection | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'projection.json')

    Write-Output "PASS: $($profile.profile) ${Stage}: $caseCount canonical cases; $($contract.assertion_expressions) preserved assertions; exact product Python executed."
}
if($profile.profile -ceq 'layered-v1' -and @($stages).Count -eq 2){
    $single=Get-Content (Join-Path $rootOutput 'evidence.json') -Raw | ConvertFrom-Json
    Assert-PythonMultiStageEvidence $rootOutput $single $contract
    $multi=Get-Content (Join-Path $rootOutput 'multi/evidence.json') -Raw | ConvertFrom-Json
    foreach($field in @('profile','producer_commit','core_dll_sha256')){if($single.$field -cne $multi.$field){throw 'Profile identity differs between mandatory stages.'}}
}
if(@($stages).Count -eq 2 -or $profile.profile -ceq 'legacy-v1'){Assert-PythonProfileEvidence $rootOutput $profile $projection $toolBinding}
if($toolBinding){Assert-PythonToolingBinding $ToolsRoot $ToolsSha $ConfigPath}
$recheck=Resolve-WssReviewedProfile $projectionRoot $candidate -SelectionEnabledCampaign:$SelectionEnabledCampaign
if($recheck.profile -cne $profile.profile -or $recheck.core_dll_sha256 -cne $profile.core_dll_sha256){throw 'Verified product capability changed during execution.'}
} finally {$env:WSS_CONFORMANCE_STAGE=$previousStage}
