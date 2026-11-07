param(
    [Parameter(Mandatory)][string]$WrapperRoot,
    [Parameter(Mandatory)][string]$FixtureRoot,
    [Parameter(Mandatory)][string]$WrapperSha,
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$OutputRoot,
    [string]$ToolsRoot='', [string]$ToolsSha='',
    [string]$TestRoot='',
    [string]$TestSha='',
    [string]$TestRepository='',
    [string]$TestSelectionId='',
    [string]$CliRoot='',
    [string]$CliSha='',
    [ValidateSet('committed','candidate')][string]$Mode='committed',
    [ValidateSet('wrapper','cli')][string]$Role='wrapper',
    [ValidateSet('all','single','multi')][string]$Stage='all',
    [string]$ArtifactRoot='',
    [string]$CandidatePath='',
    [string]$PythonExe='python',
    [ValidateRange(30,1800)][int]$TimeoutSeconds=300
)
. "$PSScriptRoot/PythonContract.ps1"
# Ordinary runs select complete reviewed coverage from the exact installed payload.
# Candidate acceptance retains its established modern-only evidence contract.
if($Mode -ceq 'committed') {
    . "$PSScriptRoot/PythonProfiles/Contract.ps1"
    Assert-PythonSource $WrapperRoot $WrapperSha
    $ordinaryProjection=Get-Content -LiteralPath (Join-Path $WrapperRoot '.github/python-candidate.json') -Raw | ConvertFrom-Json
    $ordinaryPayload=Join-Path $WrapperRoot $PythonPluginPath
    Assert-PythonProjection $ordinaryPayload $ordinaryProjection
    $ordinaryProfile=Resolve-WssReviewedProfile $ordinaryPayload $ordinaryProjection.candidate
    $ordinaryContract=Get-PythonProfileContract $ordinaryProfile.profile
    if($ToolsRoot -or $ToolsSha){
        . "$PSScriptRoot/PythonProfiles/Tooling.ps1"
        $binding=Resolve-PythonOrdinaryTooling -ToolsRoot $ToolsRoot -ToolsSha $ToolsSha -ConfigPath $ConfigPath -WrapperRoot $WrapperRoot -WrapperSha $WrapperSha
        if($binding.profile.profile -cne $ordinaryProfile.profile){throw 'Tool/product profile mismatch.'}
    }
    Assert-PythonSource $FixtureRoot $ordinaryContract.fixture_commit
    $ordinary=@{}
    foreach($key in $PSBoundParameters.Keys){if($key -cne 'FixtureRoot'){$ordinary[$key]=$PSBoundParameters[$key]}}
    & "$PSScriptRoot/Invoke-ProfiledPythonConformance.ps1" @ordinary
    if(!$?){throw 'Ordinary capability-profile validation failed.'}
    return
}
if($ToolsRoot -or $ToolsSha){throw 'Candidate validation does not accept ordinary tooling overrides.'}
$previousStage = $env:WSS_CONFORMANCE_STAGE
try {
# Ordinary and candidate callers must execute both isolated stages by default.
# Explicit single/multi remain available for focused diagnosis only.
if ($Stage -ceq 'all') {
    $options = @{}
    foreach ($key in $PSBoundParameters.Keys) { $options[$key] = $PSBoundParameters[$key] }
    $options.Stage = 'single'
    & $PSCommandPath @options
    $options.Stage = 'multi'
    $options.OutputRoot = Join-Path $OutputRoot 'multi'
    & $PSCommandPath @options
    $single = Get-Content (Join-Path $OutputRoot 'evidence.json') -Raw | ConvertFrom-Json
    Assert-PythonMultiStageEvidence $OutputRoot $single (Resolve-PythonTestSource $WrapperRoot $WrapperSha $ConfigPath $TestRoot $TestSha $TestRepository $TestSelectionId).contract
    return
}

$env:WSS_CONFORMANCE_STAGE=$Stage
$productConfig=Read-PythonConfig $ConfigPath
$tests=Resolve-PythonTestSource $WrapperRoot $WrapperSha $ConfigPath $TestRoot $TestSha $TestRepository $TestSelectionId
$config=$tests.contract
# Runtime and release authority always come from the product, never selected tests.
foreach ($field in @('automated_execution','dotnet_sdk','python_version','pythonnet_version')) { $config | Add-Member -NotePropertyName $field -NotePropertyValue $productConfig.$field -Force }
if ($config.automated_execution -cne 'pythonnet' -or $config.dotnet_sdk -cne '9.0.316') { throw 'Unexpected automated execution contract.' }
if (Test-Path -LiteralPath $OutputRoot) { throw 'OutputRoot must be new.' }
Assert-PythonSource $WrapperRoot $WrapperSha
Assert-PythonSource $FixtureRoot $config.fixture_commit
if ($Role -ceq 'cli' -or $Mode -ceq 'candidate') {
    if (!$CliRoot -or !$CliSha) { throw 'CLI/candidate validation requires the exact CLI source.' }
    Assert-PythonSource $CliRoot $CliSha -IgnoreSubmodule
}
$fixturePath=Join-Path $FixtureRoot 'tests/Wss.CSharpImplementation.Tests/StimulationControllerConformanceTests.cs'
if ((Get-FileHash -LiteralPath $fixturePath).Hash.ToLowerInvariant() -cne $config.fixture_sha256) { throw 'Canonical fixture hash mismatch.' }
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
if ($Mode -ceq 'candidate') {
    if (!$ArtifactRoot -or !$CandidatePath) { throw 'Candidate mode requires the resolver output; no fallback.' }
    $candidate=Get-Content -LiteralPath $CandidatePath -Raw | ConvertFrom-Json
    $projectionRoot=Join-Path $OutputRoot 'projection'
    $projection=New-PythonProjection $ArtifactRoot $WrapperRoot $projectionRoot $candidate
} else {
    if ($ArtifactRoot -or $CandidatePath) { throw 'Committed mode cannot accept candidate overrides.' }
    $projection=Get-Content -LiteralPath (Join-Path $WrapperRoot '.github/python-candidate.json') -Raw | ConvertFrom-Json
    $projectionRoot=Join-Path $WrapperRoot $PythonPluginPath
    Assert-PythonProjection $projectionRoot $projection
    $candidate=$projection.candidate
}
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
& (Join-Path $tests.root 'conformance/Prepare-Harness.ps1') -CSharpIntegrationRoot $FixtureRoot -Destination $harness -ProjectionRoot $projectionRoot -Role $Role -CliRoot $CliRoot -PythonRuntimeAssembly $pythonInfo.assembly
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
Assert-PythonResults $xmlPath $config -DotNet -Stage $Stage
foreach ($name in @('WSS_Core_Interface.dll','Newtonsoft.Json.dll','System.Security.Permissions.dll')) {
    $binary=Join-Path $harness "bin/Debug/net9.0/$name"
    if ((Get-FileHash -LiteralPath $binary).Hash -cne (Get-FileHash -LiteralPath (Join-Path $projectionRoot $name)).Hash) { throw "Test output used a different payload assembly: $name" }
}
Assert-PythonProjection $projectionRoot $projection
Assert-PythonSource $WrapperRoot $WrapperSha
if ($CliRoot) { Assert-PythonSource $CliRoot $CliSha -IgnoreSubmodule }
Assert-PythonTestSource $tests
$inputs=Get-Content -LiteralPath (Join-Path $harness 'conformance-inputs.json') -Raw | ConvertFrom-Json
if ($inputs.assertion_expressions -ne 20 -or $inputs.canonical_fixture_sha256 -cne $config.fixture_sha256) { throw 'Harness provenance mismatch.' }
$evidence=[ordered]@{
    schema='wss-python-evidence/v1'; execution='pythonnet'; role=$Role; mode=$Mode; candidate=$candidate
    test_root=$tests.root; test_sha=$tests.sha; test_repository=$tests.repository; test_selection_id=$tests.selection_id; test_contract_sha256=$tests.contract_sha256
    wrapper_sha=$WrapperSha; cli_sha=$CliSha; fixture_sha=$config.fixture_commit; fixture_sha256=$config.fixture_sha256
    sdk=$sdk; target_framework='net9.0'; test_framework='NUnit 3.14.0'; python_executed=$true
    python=$pythonInfo.version; pythonnet=$netVersion
    run_repository=$env:GITHUB_REPOSITORY; run_id=$env:GITHUB_RUN_ID; run_sha=$env:GITHUB_SHA
    discovered=16; executed=16; passed=16; failed=0; skipped=0; assertion_expressions=20; stage=$Stage
    projection_sha256=$projection.projection_sha256
    results_sha256=(Get-FileHash -LiteralPath $xmlPath).Hash.ToLowerInvariant()
    log_sha256=(Get-FileHash -LiteralPath $logPath).Hash.ToLowerInvariant()
}
$evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'evidence.json')
$projection | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'projection.json')
Write-Output 'PASS: Python via pythonnet through shared production commands; sixteen canonical cases, twenty unchanged assertion expressions; Production Python executed; emulator only, no terminal input or physical hardware.'

} finally { $env:WSS_CONFORMANCE_STAGE = $previousStage }
