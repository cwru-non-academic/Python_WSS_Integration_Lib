param([Parameter(Mandatory)][string]$LegacyRoot,[Parameter(Mandatory)][string]$ModernRoot,[string]$CliRoot='')
$ErrorActionPreference='Stop'
$tools=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. "$tools/.github/scripts/PythonContract.ps1"
. "$tools/.github/scripts/PythonProfiles/Tooling.ps1"
$sha=(git -C $tools rev-parse HEAD).Trim();$config=Join-Path $tools '.github/python-ci.json'
$count=0
function Reject([scriptblock]$Action){try{& $Action | Out-Null}catch{$script:count++;return};throw 'Invalid tooling/product binding was accepted.'}
foreach($pair in @(@($LegacyRoot,'legacy-v1',10),@($ModernRoot,'layered-v1',16))){
    $product=$pair[0];$productSha=(git -C $product rev-parse HEAD).Trim()
    $binding=Resolve-PythonOrdinaryTooling -ToolsRoot $tools -ToolsSha $sha -ConfigPath $config -WrapperRoot $product -WrapperSha $productSha
    if($binding.profile.profile -cne $pair[1] -or $binding.config.dotnet_expected_cases.Count -ne $pair[2] -or $binding.tooling_sha -cne $sha){throw 'Actual capability or tooling identity changed.'};$count++
    Reject {Resolve-PythonOrdinaryTooling -ToolsRoot $tools -ToolsSha ('f'*40) -ConfigPath $config -WrapperRoot $product -WrapperSha $productSha}
    Reject {Resolve-PythonOrdinaryTooling -ToolsRoot $product -ToolsSha $productSha -ConfigPath (Join-Path $product '.github/python-ci.json') -WrapperRoot $product -WrapperSha $productSha}
    Reject {Resolve-PythonOrdinaryTooling -ToolsRoot $tools -ToolsSha $sha -ConfigPath (Join-Path $product '.github/python-ci.json') -WrapperRoot $product -WrapperSha $productSha}
    Reject {Resolve-PythonOrdinaryTooling -ToolsRoot $tools -ToolsSha $sha -ConfigPath $config -WrapperRoot $product -WrapperSha ('f'*40)}
    Assert-PythonSource $product $productSha
}
if($CliRoot){$cliSha=(git -C $CliRoot rev-parse HEAD).Trim();Reject {Assert-PythonOrdinaryCliPair $CliRoot $cliSha ('f'*40)}}
# A real dirty tooling checkout must fail before its changed configuration is used.
$copy=Join-Path ([IO.Path]::GetTempPath()) ('python-tooling-binding-'+[guid]::NewGuid().ToString('N'))
git -C $tools worktree add --detach $copy $sha | Out-Null
if($LASTEXITCODE -ne 0){throw 'Cannot construct isolated dirty-tooling negative.'}
try {
    Add-Content -LiteralPath (Join-Path $copy '.github/python-ci.json') -Value ' '
    . "$copy/.github/scripts/PythonProfiles/Tooling.ps1"
    Reject {Assert-PythonToolingBinding $copy $sha (Join-Path $copy '.github/python-ci.json')}
} finally {. "$tools/.github/scripts/PythonProfiles/Tooling.ps1"}
Write-Output "PASS: $count exact-tooling/config/product/profile and ordinary gitlink binding checks."
