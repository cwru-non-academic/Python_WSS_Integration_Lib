param([string]$PythonExe='python')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$count=0
function Check($Ok,$Message){if(!$Ok){throw $Message};$script:count++}
function Reject([scriptblock]$Action){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Check $failed 'Invalid admission accepted.'}
function Read-Workflow($Path){$json=& $PythonExe -c 'import json,sys,yaml; print(json.dumps(yaml.load(open(sys.argv[1],encoding="utf-8-sig"),Loader=yaml.BaseLoader)))' $Path;if($LASTEXITCODE){throw 'Workflow parse failed'};$json|ConvertFrom-Json -AsHashtable}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('python-reusable-tooling-'+[guid]::NewGuid().ToString('N'))
$names=@('ROLE','WRAPPER_SHA','CLI_SHA','TOOLS_SHA','GITHUB_REPOSITORY','GITHUB_EVENT_NAME','GITHUB_REF','GITHUB_REF_NAME','WSS_CI_CHANNEL','GITHUB_WORKFLOW_REF','GITHUB_WORKFLOW_SHA','GITHUB_SHA','GITHUB_WORKSPACE','RUNNER_TEMP','MODE','CANDIDATE_JSON')
$saved=@{};foreach($n in $names){$saved[$n]=[Environment]::GetEnvironmentVariable($n)}
try {
    foreach($where in @('tools','wrapper')){
        $dir=Join-Path $temp "$where/.github/scripts";$null=New-Item -ItemType Directory $dir -Force
        foreach($file in @('Invoke-PlatformCompatibility.ps1','Invoke-DotNetConformance.ps1')){
            $text=if($where -ceq 'wrapper'){"throw 'PRODUCT TOOLING EXECUTED'"}else{'param($ToolsRoot,$ToolsSha,$WrapperRoot,$WrapperSha,$FixtureRoot,$OutputRoot,$ConfigPath,$Mode,$ArtifactRoot,$CandidatePath,$CliRoot,$CliSha,$Stage,$PythonExe)
$global:ReusableCapture=@{};foreach($key in $PSBoundParameters.Keys){$global:ReusableCapture[$key]=$PSBoundParameters[$key]}'}
            [IO.File]::WriteAllText((Join-Path $dir $file),$text)
        }
    }
    $scripts=Join-Path $temp 'tools/.github/scripts'
    [IO.File]::WriteAllText((Join-Path $scripts 'PythonPromotion.ps1'),'function Assert-PythonProducer($Candidate){$global:ReusableProducer=$Candidate}')
    [IO.File]::WriteAllText((Join-Path $scripts 'Resolve-WssRelease.ps1'),'param($RunId,$ExpectedArtifactId,$ExpectedCommit,$ArchiveName,$ExpectedSha256,$OutputRoot) $global:ReusableRelease=$PSBoundParameters')
    [IO.File]::WriteAllText((Join-Path $scripts 'Complete-MacOSConsumer.ps1'),'param($InputRoot,$OutputRoot,$ArtifactPrefix,$EvidenceSubdirectory,$WorkerResult) $global:ReusableMacOS=$PSBoundParameters')
    $null=New-Item -ItemType Directory (Join-Path $scripts 'wss-ci') -Force
    [IO.File]::WriteAllText((Join-Path $scripts 'wss-ci/Evidence.ps1'),'function New-WssCiEvidenceIdentity($Repository,$Run,$Attempt,$Sha,$Architecture){$global:ReusableEvidence=$true;@{source_sha=$Sha}}')
    $evidence=Join-Path $temp 'tools/.github/scripts/tests';$null=New-Item -ItemType Directory $evidence -Force;[IO.File]::WriteAllText((Join-Path $evidence 'Test-LayeredEvidence.ps1'),'param($ResultsRoot) if(!$global:ReusableCapture){throw "Evidence before runner"}')
    $env:GITHUB_WORKSPACE=$temp;$env:RUNNER_TEMP=Join-Path $temp 'runner';Push-Location $temp
    try {foreach($file in @('_python-validation.yml','_python-platform-validation.yml')){
        $workflow=Read-Workflow (Join-Path $root ".github/workflows/$file")
        Check ($workflow.on.workflow_call.inputs.tools_sha.required -ceq 'true') 'Required tooling input missing.'
        foreach($job in $workflow.jobs.Values){
            if(!$job.ContainsKey('steps')){continue};$steps=@($job.steps)
            $admission=@($steps|Where-Object {$_.name -ceq 'Authenticate registered reusable caller and tooling identity'})
            Check ($admission.Count -eq 1 -and $steps[0].name -ceq $admission[0].name) 'Admission must precede checkout.'
            $checkout=@($steps|Where-Object {$_.ContainsKey('with') -and $_.with.path -ceq 'tools'})
            Check ($checkout.Count -eq 1 -and $checkout[0].with.repository -ceq 'cwru-non-academic/Python_WSS_Integration_Lib' -and $checkout[0].with.ref -ceq '${{ inputs.tools_sha }}') 'Tooling checkout substitution.'
            $bind=@($steps|Where-Object {$_.name -ceq 'Verify immutable tooling before importing validators'})[0].run
            Check ($bind.IndexOf('Tooling checkout must remain clean.') -lt $bind.IndexOf('. ./tools/')) 'Import before tooling verification.'
            Check ($bind.Contains('Get-OrdinaryPythonToolsSha $caller $env:GITHUB_SHA')) 'Missing authenticated CLI pin.'
                $env:CANDIDATE_JSON='{"run_id":"42","artifact_id":"43","commit":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","archive":"candidate.zip","sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}'
                foreach($step in $steps){
                    if(!$step.ContainsKey('run')){continue}
                    if($step.run.Contains('Assert-PythonProducer')){
                        $global:ReusableProducer=$null;$global:ReusableRelease=$null
                        & ([scriptblock]::Create($step.run))
                        Check ($global:ReusableProducer.run_id -ceq '42' -and $global:ReusableRelease.ExpectedArtifactId -ceq '43') 'Producer/resolver authority routed incorrectly.'
                    } elseif($step.run.Contains('Complete-MacOSConsumer.ps1')){
                        $global:ReusableMacOS=$null;& ([scriptblock]::Create($step.run))
                        Check ($global:ReusableMacOS.ArtifactPrefix -ceq 'python-preflight-platform') 'macOS aggregate must use reviewed tools.'
                    } elseif($step.run.Contains('New-WssCiEvidenceIdentity')){
                        $global:ReusableEvidence=$false;& ([scriptblock]::Create($step.run))
                        Check $global:ReusableEvidence 'Worker evidence must use reviewed tools.'
                    }
                }
            $guard=[scriptblock]::Create($admission[0].run)
            foreach($channel in @('dev','main')){foreach($role in @('wrapper','cli')){
                $env:ROLE=$role;$env:WRAPPER_SHA='a'*40;$env:CLI_SHA='b'*40;$env:TOOLS_SHA=if($role -ceq 'wrapper'){$env:WRAPPER_SHA}else{'c'*40}
                $env:GITHUB_SHA=if($role -ceq 'wrapper'){$env:WRAPPER_SHA}else{$env:CLI_SHA}
                $env:GITHUB_REPOSITORY=if($role -ceq 'wrapper'){'cwru-non-academic/Python_WSS_Integration_Lib'}else{'cwru-non-academic/CLI_Python_WSS_Application'}
                $env:GITHUB_EVENT_NAME='workflow_dispatch';$env:GITHUB_REF="refs/heads/$channel";$env:GITHUB_REF_NAME=$channel;$env:WSS_CI_CHANNEL=$channel
                $env:GITHUB_WORKFLOW_REF="$env:GITHUB_REPOSITORY/.github/workflows/wss-preflight.yml@$env:GITHUB_REF";$env:GITHUB_WORKFLOW_SHA=$env:GITHUB_SHA
                & $guard;$count++
                foreach($m in @(@('ROLE','ros'),@('GITHUB_REPOSITORY','other/repo'),@('GITHUB_EVENT_NAME','pull_request_target'),@('WSS_CI_CHANNEL','other'),@('GITHUB_WORKFLOW_REF','other'),@('GITHUB_WORKFLOW_SHA',('d'*40)),@('GITHUB_SHA',('e'*40)),@('TOOLS_SHA','dev'),@('TOOLS_SHA',''),@('WRAPPER_SHA','main'))){
                    $old=[Environment]::GetEnvironmentVariable($m[0]);[Environment]::SetEnvironmentVariable($m[0],$m[1]);try{Reject {& $guard}}finally{[Environment]::SetEnvironmentVariable($m[0],$old)}
                }
                foreach($step in $steps){
                    if(!$step.ContainsKey('run') -or $step.run -notmatch '\./tools/\.github/scripts/Invoke-(PlatformCompatibility|DotNetConformance)\.ps1'){continue}
                    $code=$step.run.Replace('${{ inputs.tools_sha }}',$env:TOOLS_SHA).Replace('${{ needs.prerequisites.outputs.wrapper }}',$env:WRAPPER_SHA).Replace('${{ needs.prerequisites.outputs.cli }}',$env:CLI_SHA)
                    $env:MODE='candidate';$env:CANDIDATE_JSON='{}';$global:ReusableCapture=$null
                    & ([scriptblock]::Create($code))
                    Check ($null -ne $global:ReusableCapture) 'Reviewed runner not invoked.'
                    foreach($key in @('ToolsRoot','ToolsSha','ConfigPath','WrapperRoot','WrapperSha','FixtureRoot','Mode','ArtifactRoot','CandidatePath')){Check ($global:ReusableCapture.ContainsKey($key) -and !!$global:ReusableCapture[$key]) "Missing forwarding: $key"}
                    Check ($global:ReusableCapture.ToolsRoot -ceq "$temp/tools" -and $global:ReusableCapture.ConfigPath -ceq "$temp/tools/.github/python-ci.json" -and $global:ReusableCapture.ToolsSha -ceq $env:TOOLS_SHA) 'Tooling tuple substituted.'
                    Check ($global:ReusableCapture.WrapperRoot -ceq "$temp/wrapper" -and $global:ReusableCapture.WrapperSha -ceq $env:WRAPPER_SHA) 'Product authority substituted.'
                    if($role -ceq 'cli'){Check ($global:ReusableCapture.CliSha -ceq $env:CLI_SHA) 'CLI source not forwarded.'}
                }
            }}
        }
    }} finally {Pop-Location}
} finally {
    foreach($n in $names){[Environment]::SetEnvironmentVariable($n,$saved[$n])}
    $full=[IO.Path]::GetFullPath($temp);$parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if((Split-Path $full -Parent) -cne $parent -or (Split-Path $full -Leaf) -cnotmatch '^python-reusable-tooling-[a-f0-9]{32}$'){throw 'Unsafe cleanup root.'}
    Remove-Item -LiteralPath $full -Recurse -Force
}
"PASS: $count actual reusable admission and sentinel runner forwarding checks."