param([string]$PythonExe='python',[string]$CliRoot='')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
if(!$CliRoot){$CliRoot=Join-Path (Split-Path $root) 'CLI_Python_WSS_Application'}
$tempParent=[IO.Path]::GetTempPath()
if(!$IsWindows){Push-Location $tempParent;try{$tempParent=(& /bin/pwd -P).Trim();if($LASTEXITCODE -ne 0 -or !$tempParent){throw 'Cannot resolve physical fixture parent.'}}finally{Pop-Location}}
$tempParent=[IO.Path]::GetFullPath($tempParent).TrimEnd([IO.Path]::DirectorySeparatorChar)
$temp=Join-Path $tempParent ('python-candidate-binding-'+[guid]::NewGuid().ToString('N'))
$count=0
function Check($Ok,$Message){if(!$Ok){throw $Message};$script:count++}
function Reject([scriptblock]$Action){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Check $failed 'Invalid candidate/tooling source accepted.'}
function Put($Path,$Text){$null=New-Item -ItemType Directory (Split-Path $Path) -Force;[IO.File]::WriteAllText($Path,$Text)}
function Commit($Path){git -C $Path add .|Out-Null;git -C $Path -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm fixture;if($LASTEXITCODE){throw 'Synthetic commit failed'};(& git -C $Path rev-parse HEAD).Trim()}
function Init($Path){$null=New-Item -ItemType Directory $Path -Force;git -C $Path init -q;if($LASTEXITCODE){throw 'Synthetic init failed'}}
$names=@('GITHUB_WORKSPACE','GITHUB_SHA','GITHUB_REPOSITORY','TOOLS_SHA','GITHUB_REF','MODE','ROLE','CLI_SHA','WRAPPER_SHA','GITHUB_OUTPUT');$saved=@{};foreach($n in $names){$saved[$n]=[Environment]::GetEnvironmentVariable($n)}
try {
    $tools=Join-Path $temp 'tools';Init $tools
    foreach($file in @('PythonContract.ps1','PythonTestSource.ps1','Universal-WssFiles.ps1','PythonProfiles/Tooling.ps1','PythonProfiles/Contract.ps1','PythonProfiles/Profile.ps1')){Put (Join-Path $tools ".github/scripts/$file") ([IO.File]::ReadAllText((Join-Path $root ".github/scripts/$file")))}
    Put (Join-Path $tools '.github/python-ci.json') ([IO.File]::ReadAllText((Join-Path $root '.github/python-ci.json')))
    $sha=Commit $tools;$config=Join-Path $tools '.github/python-ci.json'
    . "$tools/.github/scripts/PythonContract.ps1"
    . "$tools/.github/scripts/PythonProfiles/Tooling.ps1"
    # Both current and previously eligible product configurations retain their exact fixture authority.
    $configs=@([IO.File]::ReadAllText((Join-Path $root '.github/python-ci.json')))
    $historical=& git -C $root show '12822b0567c918daa04bf486afca951adde9fca0:.github/python-ci.json';if($LASTEXITCODE){throw 'Historical eligible product config unavailable'};$configs+=($historical -join "`n")
    $json=& $PythonExe -c 'import json,sys,yaml; print(json.dumps(yaml.load(open(sys.argv[1],encoding="utf-8-sig"),Loader=yaml.BaseLoader)))' (Join-Path $root '.github/workflows/_python-validation.yml')
    if($LASTEXITCODE){throw 'Workflow parse failed'};$sourceWorkflow=$json|ConvertFrom-Json -AsHashtable
    $sourceCode=@($sourceWorkflow.jobs.prerequisites.steps|Where-Object {$_.ContainsKey('name') -and $_.name -ceq 'Validate exact source and execution contract'})[0].run
    foreach($index in 0..1){
        $product=Join-Path $temp "product-$index";Init $product;Put (Join-Path $product '.github/python-ci.json') $configs[$index]
        Put (Join-Path $product '.github/scripts/Invoke-PlatformCompatibility.ps1') "throw 'PRODUCT TOOLING EXECUTED'"
        $productSha=Commit $product;$expected=$configs[$index]|ConvertFrom-Json
        foreach($channel in @('dev','main')){
            $env:GITHUB_REF="refs/heads/$channel"
            $binding=Resolve-PythonCandidateTooling $tools $sha $config $product $productSha
            Check ($binding.config.fixture_commit -ceq $expected.fixture_commit -and $binding.product_config_path -ceq (Join-Path $product '.github/python-ci.json')) 'Product fixture/config authority changed.'
            Put (Join-Path $temp 'caller/.github/python-ci.json') $configs[0]
            Put (Join-Path $temp 'candidate-contract/.github/python-ci.json') $configs[$index]
            $env:MODE='candidate';$env:ROLE='cli';$env:CLI_SHA='b'*40;$env:WRAPPER_SHA=$productSha;$env:GITHUB_SHA=$env:CLI_SHA;$env:GITHUB_OUTPUT=Join-Path $temp 'workflow-output'
            Push-Location $temp
            try {
                & ([scriptblock]::Create($sourceCode));$count++
                $notReady=$configs[$index]|ConvertFrom-Json;$notReady.baseline_ready=$false
                Put (Join-Path $temp 'candidate-contract/.github/python-ci.json') ($notReady|ConvertTo-Json -Depth 40)
                Reject {& ([scriptblock]::Create($sourceCode))}
            } finally {Pop-Location}
            Reject {Resolve-PythonCandidateTooling $tools 'dev' $config $product $productSha}
            Reject {Resolve-PythonCandidateTooling $tools ('f'*40) $config $product $productSha}
            Reject {Resolve-PythonCandidateTooling $tools $sha (Join-Path $product '.github/python-ci.json') $product $productSha}
            Reject {Resolve-PythonCandidateTooling $product $productSha (Join-Path $product '.github/python-ci.json') $product $productSha}
            Reject {Resolve-PythonCandidateTooling $tools $sha $config $product ('f'*40)}
        }
        $denied=$configs[$index]|ConvertFrom-Json;$denied.baseline_ready=$false;Put (Join-Path $product '.github/python-ci.json') ($denied|ConvertTo-Json -Depth 40);$deniedSha=Commit $product
        Reject {Resolve-PythonCandidateTooling $tools $sha $config $product $deniedSha}
    }
    # Execute the actual YAML checkout admission block with real clean Git identities.
    $json=& $PythonExe -c 'import json,sys,yaml; print(json.dumps(yaml.load(open(sys.argv[1],encoding="utf-8-sig"),Loader=yaml.BaseLoader)))' (Join-Path $root '.github/workflows/_python-platform-validation.yml')
    if($LASTEXITCODE){throw 'Workflow parse failed'};$workflow=$json|ConvertFrom-Json -AsHashtable
    $code=@($workflow.jobs.compatibility.steps|Where-Object {$_.ContainsKey('name') -and $_.name -ceq 'Verify immutable tooling before importing validators'})[0].run
    $caller=Join-Path $temp 'caller';Init $caller
    Put (Join-Path $caller '.github/scripts/Read-OrdinaryPythonTooling.ps1') ([IO.File]::ReadAllText((Join-Path $CliRoot '.github/scripts/Read-OrdinaryPythonTooling.ps1')))
    Put (Join-Path $caller '.github/workflows/cli-ci.yml') "repository: cwru-non-academic/Python_WSS_Integration_Lib`nref: $sha`npath: tools`n"
    $callerSha=Commit $caller;$env:GITHUB_WORKSPACE=$temp;$env:GITHUB_SHA=$callerSha;$env:GITHUB_REPOSITORY='cwru-non-academic/CLI_Python_WSS_Application';$env:TOOLS_SHA=$sha
    Push-Location $temp
    try {
        & ([scriptblock]::Create($code));$count++
        $env:TOOLS_SHA='f'*40;Reject {& ([scriptblock]::Create($code))};$env:TOOLS_SHA=$sha
        $env:GITHUB_SHA='e'*40;Reject {& ([scriptblock]::Create($code))};$env:GITHUB_SHA=$callerSha
        Add-Content -LiteralPath $config -Value ' ';Reject {& ([scriptblock]::Create($code))}
        Put $config $configs[0]
        Add-Content -LiteralPath (Join-Path $caller '.github/workflows/cli-ci.yml') -Value '# dirty';Reject {& ([scriptblock]::Create($code))}
    } finally {Pop-Location}
} finally {
    foreach($n in $names){[Environment]::SetEnvironmentVariable($n,$saved[$n])}
    $full=[IO.Path]::GetFullPath($temp);$parent=$tempParent
    if((Split-Path $full -Parent) -cne $parent -or (Split-Path $full -Leaf) -cnotmatch '^python-candidate-binding-[a-f0-9]{32}$'){throw 'Unsafe fixture cleanup root'}
    Remove-Item -LiteralPath $full -Recurse -Force
}
"PASS: $count actual candidate product/tooling binding and workflow checkout admission checks."