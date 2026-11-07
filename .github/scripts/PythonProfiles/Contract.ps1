. "$PSScriptRoot/Profile.ps1"
function Get-PythonProfileContract([string]$Profile) {
    $single=@('AnalogStimulationThroughCSharpImplementationPassesCoreConformance','InitializationThroughCSharpImplementationPassesCoreConformance','normalized.minus-0.2','normalized.0.0','normalized.0.37','normalized.0.5','normalized.1.0','normalized.1.2','RuntimeEventEditThroughCSharpImplementationResumesConformantStreaming','StopStimulationThroughCSharpImplementationDoesNotResumeStreaming')
    $multi=@()
    if($Profile -ceq 'layered-v1') {
        $multi=$single+@('analog.multidevice-isolation','normalized.multidevice-isolation','modeled.p.pw.multi','modeled.p.pa.multi','modeled.pd.pw.multi','modeled.pd.pa.multi')
        $single+=@('analog.multichannel-isolation','normalized.multichannel-isolation','modeled.p.pw.single','modeled.p.pa.single','modeled.pd.pw.single','modeled.pd.pa.single')
    } elseif($Profile -cne 'legacy-v1'){throw 'Unknown Python capability profile.'}
    $fixture=Get-WssProfileFixture $Profile
    [pscustomobject]@{profile=$Profile;fixture_commit=$(if($Profile -ceq 'legacy-v1'){'02172a64c55becd5535204f46f10b4755bf3ee05'}else{'fc427c5b8bc6534a7d02f00283830072572aa03a'});fixture=$fixture;fixture_sha256=(Get-FileHash $fixture).Hash.ToLowerInvariant();assertion_expressions=$(if($Profile -ceq 'layered-v1'){20}else{18});single_cases=$single;multi_cases=$multi;dotnet_expected_cases=$single;multidevice_expected_cases=@($multi | Select-Object -Skip 10)}
}
function Read-PythonProfileProductConfig([string]$Path) {
    $c=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if($c.schema -cne 'wss-python-ci/v1' -or $c.branch -cne 'dev' -or $c.automated_execution -cne 'pythonnet' -or $c.dotnet_sdk -cne '9.0.316' -or $c.python_version -cne '3.12' -or $c.pythonnet_version -cne '3.0.5'){throw 'Unexpected product runtime contract.'}
    # Case counts/fixture configuration never select or weaken a capability profile.
    if($env:GITHUB_REF -ceq 'refs/heads/main' -and (!$c.PSObject.Properties['channels'] -or @($c.channels).Count -ne 2 -or @(Compare-Object @('dev','main') @($c.channels) -CaseSensitive).Count)){throw 'Main validation requires the existing dual-channel product contract.'}
    $c
}
function Resolve-PythonProfileTests([string]$WrapperRoot,[string]$WrapperSha,[string]$TestRoot,[string]$TestSha,[string]$TestRepository,[string]$TestSelectionId,$Contract) {
    $explicit=[bool]($TestRoot -or $TestSha -or $TestRepository -or $TestSelectionId)
    if($explicit){
        if(!$TestRoot -or !$TestSha -or !$TestRepository -or !$TestSelectionId){throw 'Complete immutable selected-test tuple required.'}
        Assert-PythonSha $TestSha
        if($TestRepository -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or $TestSelectionId -cnotmatch '^[a-f0-9]{64}$'){throw 'Invalid selected test binding.'}
    }else{$TestRoot=$WrapperRoot;$TestSha=$WrapperSha;$TestRepository=$PythonWrapperRepository}
    $tests=[pscustomobject]@{root=[IO.Path]::GetFullPath($TestRoot);sha=$TestSha;repository=$TestRepository;selection_id=$TestSelectionId;contract_sha256=''}
    Assert-PythonTestSource $tests
    if($explicit){
        $path=Join-Path $tests.root 'conformance/profile-contract.json'
        $value=Get-Content $path -Raw | ConvertFrom-Json
        if($value.schema -cne 'wss-python-profile-tests/v1' -or @(Compare-Object @('schema','profiles') @($value.PSObject.Properties.Name) -CaseSensitive).Count -or @($value.profiles.PSObject.Properties.Name).Count -ne 2 -or @(Compare-Object @('legacy-v1','layered-v1') @($value.profiles.PSObject.Properties.Name) -CaseSensitive).Count){throw 'Invalid test-only profile manifest; no product authority fields permitted.'}
        foreach($name in @('legacy-v1','layered-v1')) {
            $trusted=Get-PythonProfileContract $name;$declared=$value.profiles.$name
            if(@(Compare-Object @('fixture_sha256','assertion_expressions','single_cases','multi_cases') @($declared.PSObject.Properties.Name) -CaseSensitive).Count -or $declared.fixture_sha256 -cne $trusted.fixture_sha256 -or $declared.assertion_expressions -ne $trusted.assertion_expressions -or ($declared.single_cases -join "`n") -cne ($trusted.single_cases -join "`n") -or ($declared.multi_cases -join "`n") -cne ($trusted.multi_cases -join "`n")){throw 'Selected manifest cannot weaken a trusted canonical profile.'}
        }
        $tests.contract_sha256=(Get-FileHash $path).Hash.ToLowerInvariant()
    }
    $tests
}
function Assert-PythonProfileTestSource($Tests) {
    # Reuse strong source/ignored-file checks without interpreting the v1 manifest hash.
    $copy=[pscustomobject]@{root=$Tests.root;sha=$Tests.sha;contract_sha256=''}
    Assert-PythonTestSource $copy
    if($Tests.contract_sha256 -and (Get-FileHash (Join-Path $Tests.root 'conformance/profile-contract.json')).Hash.ToLowerInvariant() -cne $Tests.contract_sha256){throw 'Selected profile contract changed during execution.'}
}
function Assert-PythonProfileResults([string]$Path,$Contract,[string]$Stage) {
    if($Contract.profile -ceq 'layered-v1'){Assert-PythonResults $Path $Contract -DotNet -Stage $Stage;return}
    if($Stage -cne 'single'){throw 'Legacy profile has exactly its complete original single-stage suite.'}
    $settings=[Xml.XmlReaderSettings]::new();$settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null
    $reader=[Xml.XmlReader]::Create($Path,$settings)
    try{$xml=[Xml.XmlDocument]::new();$xml.XmlResolver=$null;$xml.Load($reader)}finally{$reader.Dispose()}
    $run=$xml.DocumentElement;$cases=@($xml.SelectNodes('//test-case'))
    if($run.get_Name() -cne 'test-run' -or $run.GetAttribute('result') -cne 'Passed' -or $run.GetAttribute('testcasecount') -cne '10' -or $run.GetAttribute('total') -cne '10' -or $run.GetAttribute('passed') -cne '10' -or $cases.Count -ne 10){throw 'All ten original legacy canonical cases must execute and pass.'}
    foreach($name in @('failed','skipped','inconclusive')){if($run.GetAttribute($name) -cne '0'){throw 'Legacy test failure/skip is forbidden.'}}
    if(@(Compare-Object @($Contract.single_cases) @($cases | ForEach-Object {$_.GetAttribute('name')}) -CaseSensitive).Count -or @($cases | Where-Object {$_.GetAttribute('result') -cne 'Passed'}).Count){throw 'Legacy case identity/result differs from trusted bootstrap inventory.'}
}
function Assert-PythonProfileEvidence([string]$Root,$Profile,$Projection,$Tooling=$null) {
    $contract=Get-PythonProfileContract $Profile.profile
    $stages=if($Profile.profile -ceq 'layered-v1'){@('single','multi')}else{@('single')}
    if($Profile.profile -ceq 'legacy-v1' -and (Test-Path (Join-Path $Root 'multi/evidence.json'))){throw 'Legacy proof cannot claim an invented multi stage.'}
    $single=$null
    foreach($stage in $stages){
        $directory=if($stage -ceq 'single'){$Root}else{Join-Path $Root 'multi'}
        $e=Get-Content (Join-Path $directory 'evidence.json') -Raw | ConvertFrom-Json
        $count=if($stage -ceq 'single'){$contract.single_cases.Count}else{$contract.multi_cases.Count}
        if($e.schema -cne 'wss-python-profile-evidence/v1' -or $e.profile -cne $Profile.profile -or $e.producer_commit -cne $Profile.producer.commit -or $e.core_dll_sha256 -cne $Profile.core_dll_sha256 -or $e.fixture_sha256 -cne $contract.fixture_sha256 -or $e.fixture_sha -cne $contract.fixture_commit -or $e.stage -cne $stage -or $e.discovered -ne $count -or $e.executed -ne $count -or $e.passed -ne $count -or $e.failed -ne 0 -or $e.skipped -ne 0 -or $e.assertion_expressions -ne $contract.assertion_expressions -or $e.projection_sha256 -cne $Projection.projection_sha256){throw 'Profile proof identity, coverage, fixture or payload mismatch.'}
        Assert-PythonSameCandidate $e.candidate $Profile.producer
        if($Tooling){foreach($field in @('tooling_root','tooling_sha','tooling_config_sha256')){if(!$e.PSObject.Properties[$field] -or $e.$field -cne $Tooling.$field){throw 'Ordinary evidence tooling/config binding differs.'}}}
        Assert-PythonTestEvidencePair $e $e
        foreach($pair in @(@('results.xml','results_sha256'),@('dotnet.log','log_sha256'))){if((Get-FileHash (Join-Path $directory $pair[0])).Hash.ToLowerInvariant() -cne $e.($pair[1])){throw 'Profile evidence content hash mismatch.'}}
        Assert-PythonProfileResults (Join-Path $directory 'results.xml') $contract $stage
        if($stage -ceq 'single'){$single=$e}else{Assert-PythonTestEvidencePair $single $e}
    }
    if($Profile.profile -ceq 'layered-v1'){Assert-PythonMultiStageEvidence $Root $single $contract}
}
