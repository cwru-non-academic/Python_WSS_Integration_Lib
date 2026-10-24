param(
    [Parameter(Mandatory)][string]$CSharpIntegrationRoot,
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$ProjectionRoot,
    [ValidateSet('wrapper','cli')][string]$Role='wrapper',
    [string]$CliRoot='',
    [Parameter(Mandatory)][string]$PythonRuntimeAssembly
)
$ErrorActionPreference='Stop'
$wrapper=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$target=[IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $target) { throw 'Harness destination must be new.' }
if ($target.StartsWith($wrapper+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
    ($CliRoot -and $target.StartsWith([IO.Path]::GetFullPath($CliRoot)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))) {
    throw 'Prepare the disposable harness outside source checkouts.'
}
$fixturePath=Join-Path $CSharpIntegrationRoot 'tests/Wss.CSharpImplementation.Tests/StimulationControllerConformanceTests.cs'
$fixtureHash=(Get-FileHash -LiteralPath $fixturePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($fixtureHash -cne '1cdfb9448a1776011eadc9aef8356362216032013a4f268f50242746c50a0b44') { throw 'Canonical fixture digest changed.' }
$canonical=[IO.File]::ReadAllText($fixturePath)
$factory='(?s)private static StimulationController CreateController\(string fixtureDirectory\) =>\s*new\(new StimulationOptions\s*\{\s*ConfigPath = fixtureDirectory,\s*Transport = StimulationTransportKind.Conformance,\s*MaxSetupTries = 1,\s*TickIntervalMs = 1\s*\}\);'
if ([regex]::Matches($canonical,$factory).Count -ne 1) { throw 'Canonical controller factory changed.' }
# The factory/alias is the only fixture adaptation. No serializer, case, delay,
# expected value, assertion, grouped failure reporting or evaluator is replaced.
$adapted="using StimulationController = DotNetConformanceAdapter;`n"+[regex]::Replace($canonical,$factory,'private static StimulationController CreateController(string fixtureDirectory) => new(fixtureDirectory);')
$assertions=@([regex]::Matches($canonical,'Assert\.That\(.*?;','Singleline').Value)
if ($assertions.Count -ne 18 -or ($assertions -join "`n") -cne (@([regex]::Matches($adapted,'Assert\.That\(.*?;','Singleline').Value) -join "`n")) { throw 'Canonical assertion expressions changed.' }
New-Item -ItemType Directory -Path $target | Out-Null
$sources=@((Join-Path $PSScriptRoot 'PythonConformanceAdapter.cs'))
foreach ($source in $sources) { Copy-Item -LiteralPath $source -Destination $target }
[IO.File]::WriteAllText((Join-Path $target 'StimulationControllerConformanceTests.cs'),$adapted)
New-Item -ItemType Directory -Path (Join-Path $target 'lib') | Out-Null
Copy-Item -Path (Join-Path $ProjectionRoot '*.dll') -Destination (Join-Path $target 'lib')
$project=@'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <IsTestProject>true</IsTestProject>
    <IsPackable>false</IsPackable>
    <DefineConstants>$(DefineConstants);ROLE_CONSTANT</DefineConstants>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.11.1" />
    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" ExcludeAssets="compile;runtime" />
    <PackageReference Include="NUnit" Version="3.14.0" />
    <PackageReference Include="NUnit3TestAdapter" Version="4.6.0" />
    <Reference Include="Python.Runtime"><HintPath>PYTHON_RUNTIME_ASSEMBLY</HintPath></Reference>
    <Reference Include="WSS_Core_Interface"><HintPath>lib/WSS_Core_Interface.dll</HintPath></Reference>
    <Reference Include="Newtonsoft.Json"><HintPath>lib/Newtonsoft.Json.dll</HintPath></Reference>
    <Reference Include="System.Security.Permissions"><HintPath>lib/System.Security.Permissions.dll</HintPath></Reference>
  </ItemGroup>
</Project>
'@
$constant=if ($Role -ceq 'cli') { 'CLI_CONFORMANCE' } else { 'WRAPPER_CONFORMANCE' }
[IO.File]::WriteAllText((Join-Path $target 'Wss.DotNet.Conformance.Tests.csproj'),$project.Replace('ROLE_CONSTANT',$constant).Replace('PYTHON_RUNTIME_ASSEMBLY',[Security.SecurityElement]::Escape($PythonRuntimeAssembly)))
@{sdk=@{version='9.0.316';rollForward='disable'}} | ConvertTo-Json | Set-Content (Join-Path $target 'global.json')
@{schema='wss-dotnet-inputs/v1';role=$Role;canonical_fixture_sha256=$fixtureHash;assertion_expressions=18;execution='Python via pythonnet; not Python';files=@($sources | ForEach-Object { @{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()} })} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $target 'conformance-inputs.json')
Write-Output "Prepared $Role .NET host from shared production source at $target"
