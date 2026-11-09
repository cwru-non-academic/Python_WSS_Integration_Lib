. "$PSScriptRoot/Contract.ps1"
function Assert-PythonToolingBinding([string]$ToolsRoot,[string]$ToolsSha,[string]$ConfigPath) {
    if(!$ToolsRoot -or !$ToolsSha -or !$ConfigPath){throw 'Complete immutable tooling/config binding required.'}
    $root=[IO.Path]::GetFullPath($ToolsRoot)
    $owner=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    if($root -cne $owner -or [IO.Path]::GetFullPath($ConfigPath) -cne (Join-Path $owner '.github/python-ci.json')){throw 'Tooling and configuration must belong to this exact reviewed bootstrap checkout.'}
    Assert-PythonSource $root $ToolsSha
    if([IO.Path]::GetFullPath((Invoke-PythonGit $root @('rev-parse','--show-toplevel')).Trim()) -cne $root){throw 'Tooling must identify the exact checkout root.'}
}
function Resolve-PythonOrdinaryTooling {
    param([Parameter(Mandatory)][string]$ToolsRoot,[Parameter(Mandatory)][string]$ToolsSha,[Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][string]$WrapperRoot,[Parameter(Mandatory)][string]$WrapperSha)
    Assert-PythonToolingBinding $ToolsRoot $ToolsSha $ConfigPath
    Assert-PythonSource $WrapperRoot $WrapperSha
    $config=Read-PythonProfileProductConfig $ConfigPath
    $productConfig=Read-PythonProfileProductConfig (Join-Path $WrapperRoot '.github/python-ci.json')
    foreach($key in @('schema','automated_execution','dotnet_sdk','python_version','pythonnet_version')){if($config.$key -cne $productConfig.$key){throw 'Product runtime differs from reviewed tooling configuration.'}}
    $config.baseline_ready=($config.baseline_ready -ceq $true -and $productConfig.baseline_ready -ceq $true)
    $projection=Get-Content -LiteralPath (Join-Path $WrapperRoot '.github/python-candidate.json') -Raw | ConvertFrom-Json
    $payload=Join-Path $WrapperRoot $PythonPluginPath
    Assert-PythonProjection $payload $projection
    $profile=Resolve-WssReviewedProfile $payload $projection.candidate
    $contract=Get-PythonProfileContract $profile.profile
    $config.fixture_commit=$contract.fixture_commit
    $config.fixture_sha256=if($profile.profile -ceq 'legacy-v1'){'1cdfb9448a1776011eadc9aef8356362216032013a4f268f50242746c50a0b44'}else{'14313786be4d5c6daea28e40d2f48567cbc1356feb0f0309e0a212339137923b'}
    $config.dotnet_expected_cases=@($contract.single_cases)
    $config.multidevice_expected_cases=@($contract.multi_cases | Select-Object -Skip 10)
    [pscustomobject]@{config=$config;profile=$profile;projection=$projection;fixture_commit=$contract.fixture_commit;tooling_root=[IO.Path]::GetFullPath($ToolsRoot);tooling_sha=$ToolsSha;tooling_config_sha256=(Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256).Hash.ToLowerInvariant()}
}
function Resolve-PythonCandidateTooling {
    param([Parameter(Mandatory)][string]$ToolsRoot,[Parameter(Mandatory)][string]$ToolsSha,[Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][string]$WrapperRoot,[Parameter(Mandatory)][string]$WrapperSha)
    Assert-PythonToolingBinding $ToolsRoot $ToolsSha $ConfigPath
    Assert-PythonSource $WrapperRoot $WrapperSha
    $toolConfig=Read-PythonConfig $ConfigPath
    $productConfigPath=Join-Path $WrapperRoot '.github/python-ci.json'
    $productConfig=Read-PythonConfig $productConfigPath
    foreach($key in @('schema','automated_execution','dotnet_sdk','python_version','pythonnet_version')){if($toolConfig.$key -cne $productConfig.$key){throw 'Product runtime differs from reviewed tooling configuration.'}}
    if($toolConfig.baseline_ready -cne $true -or $productConfig.baseline_ready -cne $true){throw 'Candidate promotion baseline approval remains pending.'}
    if($env:GITHUB_REF -ceq 'refs/heads/main'){
        foreach($config in @($toolConfig,$productConfig)){if(!$config.PSObject.Properties['channels'] -or @($config.channels) -cnotcontains 'main'){throw 'Main candidate capability has not been adopted.'}}
    }
    # Product and selected-test authority never comes from the tooling checkout.
    [pscustomobject]@{config=$productConfig;product_config_path=$productConfigPath;tooling_root=[IO.Path]::GetFullPath($ToolsRoot);tooling_sha=$ToolsSha;tooling_config_sha256=(Get-FileHash -LiteralPath $ConfigPath).Hash.ToLowerInvariant()}
}
