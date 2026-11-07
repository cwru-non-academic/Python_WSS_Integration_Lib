$ErrorActionPreference='Stop'
. "$PSScriptRoot/../PythonSelectedContext.ps1"
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$temp=Join-Path ([IO.Path]::GetTempPath()) ('python-context-contract-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$rootsPath=Join-Path $temp 'roots.json'
$roots=@{selection_id=('a'*64);test_root=(Join-Path $temp 'tests');products=@(@{repository='cwru-non-academic/Python_WSS_Integration_Lib';commit=('b'*40);path=(Join-Path $temp 'wrapper')},@{repository='cwru-non-academic/CSharp_WSS_Integration_Lib';commit=('c'*40);path=(Join-Path $temp 'fixture')},@{repository='cwru-non-academic/CLI_Python_WSS_Application';commit=('d'*40);path=(Join-Path $temp 'cli')})}
$roots | ConvertTo-Json -Depth 8 | Set-Content $rootsPath
'{"scope":"run"}' | Set-Content (Join-Path $temp 'context.json')
$script:events=[Collections.Generic.List[string]]::new()
$script:runnerOptions=[Collections.Generic.List[hashtable]]::new()
$script:failure=''
# Mock orchestration only. No synthetic output is acceptance evidence.
function Invoke-ReviewedSelectionCore($CoreRoot,$Operation,$TargetId,$ContextPath,$RootsPath,$EvidencePath='') {
    $script:events.Add($Operation)
    if($TargetId -cne 'python-wrapper'){throw 'Wrong authenticated target.'}
    if($Operation -ceq $script:failure){throw "Injected $Operation failure"}
    if($Operation -ceq 'inspect'){return [pscustomobject]@{selection_id=('a'*64);test_repository='cwru-non-academic/Python_WSS_Integration_Lib';test_commit=('e'*40)}}
}
function Invoke-SelectedPythonRunner($Options) {
    $kind=if($Options.ContainsKey('TestRoot')){'selected'}else{'baseline'}
    $script:events.Add($kind);$script:runnerOptions.Add($Options.Clone())
    if($kind -ceq $script:failure){throw "Injected $kind failure"}
    if($kind -ceq 'baseline') {
        $null=New-Item -ItemType Directory -Path $Options.OutputRoot -Force
        '{"profile":"legacy-v1"}' | Set-Content (Join-Path $Options.OutputRoot 'evidence.json')
        foreach($file in @('results.xml','dotnet.log','projection.json')){'baseline proof' | Set-Content (Join-Path $Options.OutputRoot $file)}
    } elseif($script:failure -ceq 'mutate-baseline') {
        $probe=Join-Path $temp 'mutate-baseline.ps1'
        'param([string]$EvidencePath); "tampered" | Set-Content -LiteralPath $EvidencePath' | Set-Content $probe
        Invoke-CredentialFreeSelectedPowerShell $probe @{EvidencePath=(Join-Path (Join-Path (Split-Path $Options.OutputRoot -Parent) 'baseline') 'results.xml')}
    }
}
function Invoke-PythonContextTest {
    param($CoreRoot,$ContextPath,$RootsPath,$WorkRoot,$Mode='committed',$ArtifactRoot='',$CandidatePath='')
    $arguments=@{CoreRoot=$CoreRoot;ContextPath=$ContextPath;RootsPath=$RootsPath;WorkRoot=($WorkRoot+'-'+[guid]::NewGuid().ToString('N'));Mode=$Mode;ArtifactRoot=$ArtifactRoot;CandidatePath=$CandidatePath}
    Invoke-PythonSelectedWithContext @arguments
}
$options=@{CoreRoot=(Join-Path $temp 'core');ContextPath=(Join-Path $temp 'context.json');RootsPath=$rootsPath;WorkRoot=(Join-Path $temp 'work')}
Invoke-PythonContextTest @options
if(($events -join ',') -cne 'inspect,baseline,selected,evidence'){throw 'Baseline/selected/authentication ordering changed.'}
$baseline=$runnerOptions[0];$selected=$runnerOptions[1]
if($baseline.SelectionEnabledCampaign -or $selected.SelectionEnabledCampaign){throw 'Run-level context forced modern profile.'}
foreach($key in @('WrapperRoot','WrapperSha','ConfigPath','Mode','Role','PythonExe','Stage')){if($baseline[$key] -cne $selected[$key]){throw "Product/runtime input changed: $key"}}
if($baseline.ContainsKey('TestRoot') -or $selected.TestSha -cne ('e'*40) -or $selected.TestSelectionId -cne ('a'*64) -or $selected.Stage -cne 'all'){throw 'Selected tuple or mandatory default coverage changed.'}
foreach($failure in @('inspect','baseline','selected','mutate-baseline')) {
    $script:failure=$failure;$events.Clear();$runnerOptions.Clear();$rejected=$false
    try { Invoke-PythonContextTest @options } catch { $rejected=$true }
    if(!$rejected -or $events.Contains('evidence')){throw "Failure emitted selection evidence: $failure"}
}
$script:failure='';$events.Clear();$runnerOptions.Clear()
Invoke-PythonContextTest @options -Mode candidate -ArtifactRoot (Join-Path $temp 'payload') -CandidatePath (Join-Path $temp 'candidate.json')
foreach($key in @('CliRoot','CliSha','ArtifactRoot','CandidatePath')){if(!$runnerOptions[0][$key] -or $runnerOptions[0][$key] -cne $runnerOptions[1][$key]){throw "Candidate input changed: $key"}}
$rejected=$false
try { Invoke-PythonContextTest @options -Mode candidate } catch { $rejected=$true }
if(!$rejected){throw 'Candidate accepted missing resolver output.'}
$nested=$options.Clone();$nested.WorkRoot=Join-Path $roots.test_root 'output'
$rejected=$false
try { Invoke-PythonSelectedWithContext @nested } catch { $rejected=$true }
if(!$rejected){throw 'Selected source allowed nested output.'}
'{"scope":"campaign"}' | Set-Content (Join-Path $temp 'context.json')
$runnerOptions.Clear();Invoke-PythonContextTest @options
if(!$runnerOptions[0].SelectionEnabledCampaign -or !$runnerOptions[1].SelectionEnabledCampaign){throw 'Authenticated campaign omitted required modern profile.'}
# Real process boundary; saved values must not be inherited through dynamic scope.
$isolated=Join-Path $temp 'isolated';$null=New-Item -ItemType Directory -Path $isolated
Copy-Item (Join-Path $repo '.github/scripts/PythonSelectedContext.ps1') $isolated
Copy-Item (Join-Path $repo '.github/scripts/SelectedTestContext.ps1') $isolated
Copy-Item (Join-Path $repo '.github/scripts/SelectedProcessIsolation.ps1') $isolated
$child=@('param([string]$WrapperRoot)', 'foreach($name in @("GH_TOKEN","GITHUB_TOKEN","WSS_TEST_VARIABLE_READ_TOKEN","SAMPLE_SECRET","GITHUB_OUTPUT")){if([Environment]::GetEnvironmentVariable($name)){throw "Authentication token leaked into test child."}}','if(Get-Variable saved -ErrorAction SilentlyContinue){throw "Parent saved credential scope leaked."}','Write-Output "PASS: test child has no authentication token or saved parent scope."')
$child | Set-Content (Join-Path $isolated 'Invoke-ProfiledPythonConformance.ps1')
. (Join-Path $isolated 'PythonSelectedContext.ps1')
$names=@('GH_TOKEN','GITHUB_TOKEN','WSS_TEST_VARIABLE_READ_TOKEN','SAMPLE_SECRET','GITHUB_OUTPUT');$prior=@{}
try {
    foreach($name in $names){$prior[$name]=[Environment]::GetEnvironmentVariable($name);[Environment]::SetEnvironmentVariable($name,'unit-test-sentinel')}
    Invoke-SelectedPythonRunner @{WrapperRoot='unused'}
    foreach($name in $names){if([Environment]::GetEnvironmentVariable($name) -cne 'unit-test-sentinel'){throw 'Bootstrap token not restored after child.'}}
    'exit 7' | Add-Content (Join-Path $isolated 'Invoke-ProfiledPythonConformance.ps1')
    $rejected=$false;try {Invoke-SelectedPythonRunner @{WrapperRoot='unused'}} catch {$rejected=$true}
    if(!$rejected){throw 'Child failure was ignored.'}
    foreach($name in $names){if([Environment]::GetEnvironmentVariable($name) -cne 'unit-test-sentinel'){throw 'Bootstrap credentials/handles not restored after child failure.'}}
} finally {foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$prior[$name])}}
Write-Output 'PASS: authenticated inspect/default baseline/additive selected/evidence ordering; failure gates, immutable product/projection inputs, and token-free child process.'
