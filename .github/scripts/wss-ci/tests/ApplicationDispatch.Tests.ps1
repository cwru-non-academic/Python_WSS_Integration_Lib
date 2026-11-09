param([string]$CSharpSenderPath='', [string]$UnitySenderPath='')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$common=(Resolve-Path "$PSScriptRoot/../DispatchProof.ps1").Path
$peerFamilies=@()
$peerSpecs=@()
if($CSharpSenderPath){$peerFamilies+='CSharp';$peerSpecs+=,@($CSharpSenderPath,'Send-WssCliDispatch')}
if($UnitySenderPath){$peerFamilies+='Unity';$peerSpecs+=,@($UnitySenderPath,'Send-UnityGuiDispatch')}
. $common
# Load only sender functions; family product/promotion entrypoints are never run.
foreach($spec in $peerSpecs){
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $spec[0]).Path,[ref]$tokens,[ref]$errors)
    if($errors){throw "Adapter parse failed: $errors"}
    $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $spec[1]},$true)
    if(!$fn){throw "Requested peer sender function $($spec[1]) is absent from $($spec[0])."}
    $code=$fn.Extent.Text.Replace('. "$PSScriptRoot/wss-ci/DispatchProof.ps1"',". '$($common.Replace("'","''"))'")
    . ([scriptblock]::Create($code))
}
$script:UnityWrapperRepository='cwru-non-academic/Unity_WSS_Integration_Lib'
$script:UnityGuiRepository='cwru-non-academic/GUI_Unity_WSS_Application'
function Assert-WssCandidateRecord($candidate,$record){if($script:scenario -eq 'candidate'){throw 'Synthetic candidate mismatch'}}
function Assert-UnitySameCandidate($candidate,$record){if($script:scenario -eq 'candidate'){throw 'Synthetic candidate mismatch'}}
$nodeExecutable=(Get-Command node -CommandType Application | Select-Object -First 1).Source
function node {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    if($Arguments[0] -like '*workflow-freeze.mjs'){
        if($env:GH_TOKEN -cne 'synthetic-read'){throw 'Authorization used write token'}
        $script:auth++
        $global:LASTEXITCODE=0
        if($script:scenario -eq 'authorization'){$global:LASTEXITCODE=1;return ''}
        if($Arguments[2] -cne '11'){throw 'Wrong producer run ID'}
        return (@{schema='wss-receiver-workflow-authorization/v1';channel='main';repository=$env:GITHUB_REPOSITORY;candidate=$script:approval.candidate;plan_id=('d'*64)}|ConvertTo-Json -Depth 8 -Compress)
    }
    $output=& $nodeExecutable @Arguments 2>$null
    $code=$LASTEXITCODE
    $global:LASTEXITCODE=$code
    return $output
}
function git {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $global:LASTEXITCODE=0
    if($Arguments -contains 'status'){return ''}
    if($script:scenario -eq 'execution-source'){return ('f'*40)}
    return $env:GITHUB_SHA
}
function gh {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $global:LASTEXITCODE=0
    if($Arguments -contains 'POST'){
        if($env:GH_TOKEN -cne 'synthetic-write'){throw 'POST used read token'}
        $script:posts++
        if($script:scenario -eq 'uncertain'){$global:LASTEXITCODE=1;return ''}
        return ''
    }
    if($env:GH_TOKEN -cne 'synthetic-read'){throw 'Read used write token'}
    $script:reads++
    $path=$Arguments[-1]
    if($path -match '/git/ref/heads/'){
        if(!$path.EndsWith('/'+$script:channel)){throw 'Wrong source channel'}
        $script:sourceReads++
        $repo=($path -split '/git/ref/heads/')[0].Substring(6)
        $sha=$script:sources[$repo]
        if($script:scenario -eq 'pre-move' -or ($script:scenario -eq 'post-move' -and $script:sourceReads -gt 2)){$sha='f'*40}
        return (@{object=@{sha=$sha}}|ConvertTo-Json -Compress)
    }
    if($path -match '/actions/workflows/promote-integration.yml/runs\?'){
        $run=@{id=91;display_title=$script:title}
        $runs=@()
        if($script:scenario -in @('reuse','reuse-attempt2','pending','failed','foreign-run','wrong-branch','ambiguous')){$runs=@($run)}
        if($script:scenario -eq 'ambiguous'){$runs=@($run,$run)}
        return (ConvertTo-Json -InputObject @(@{workflow_runs=$runs}) -Depth 8 -Compress)
    }
    if($path -match '/actions/runs/91$'){
        $run=@{id=91;display_title=$script:title;repository=@{full_name=$script:repository};head_repository=@{full_name=$script:repository};path='.github/workflows/promote-integration.yml';event='workflow_dispatch';head_branch=$script:channel;head_sha=('b'*40);status='completed';conclusion='success'}
        if($script:scenario -eq 'pending'){$run.status='in_progress'}
        if($script:scenario -eq 'failed'){$run.conclusion='failure'}
        if($script:scenario -eq 'foreign-run'){$run.head_repository.full_name='foreign/repo'}
        if($script:scenario -eq 'wrong-branch'){$run.head_branch=if($script:channel -eq 'main'){'dev'}else{'main'}}
        return ($run|ConvertTo-Json -Depth 8 -Compress)
    }
    if($path -match '/actions/artifacts\?'){
        $artifact=@{name=$script:intent;expired=$false;workflow_run=@{id=77;head_sha=('a'*40)}}
        if($script:scenario -eq 'foreign-intent'){$artifact.workflow_run.id=78}
        if($script:scenario -eq 'expired-intent'){$artifact.expired=$true}
        $artifacts=@($artifact)
        if($script:scenario -eq 'missing-intent'){$artifacts=@()}
        if($script:scenario -eq 'ambiguous-intent'){$artifacts=@($artifact,$artifact)}
        return (ConvertTo-Json -InputObject @(@{artifacts=$artifacts}) -Depth 8 -Compress)
    }
    throw "Unexpected fake API request: $path"
}
$work=Join-Path ([IO.Path]::GetTempPath()) ('sender-regression-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory "$work/.github/scripts" -Force|Out-Null
@{source_repository='cwru-non-academic/WSSCore';source_commit=('a'*40)}|ConvertTo-Json|Set-Content "$work/.github/scripts/wss-ci.lock.json"
$env:WSS_CORE_TOOLS_ROOT=$work;$env:WSS_TARGET_ROOT=$work
$count=0
try {
foreach($family in @('CSharp','Unity','Python','Matlab')){foreach($role in $(if($family -eq 'Python'){@('cli','ros')}elseif($family -eq 'Unity'){@('gui')}else{@('cli')})){foreach($script:channel in @('dev','main')){
    $cases=@('send','reuse','reuse-attempt2','pre-move','post-move','missing-intent','foreign-intent','expired-intent','ambiguous-intent','attempt2','pending','failed','foreign-run','wrong-branch','ambiguous','uncertain','wrong-ref','bad-sources','bad-intent','missing-read','missing-write','bad-owner','bad-destination','extra-source','callback-contract')
    if($channel -eq 'dev' -and $family -in @('CSharp','Unity')){$cases=@($cases|Where-Object {$_ -ne 'callback-contract'})}
    if($channel -eq 'main'){$cases+=@('authorization');if($peerFamilies -contains $family){$cases+=@('candidate','execution-source','execution-event')}}
    foreach($script:scenario in $cases){
        $script:posts=0;$script:reads=0;$script:sourceReads=0;$script:auth=0
        $owner="cwru-non-academic/${family}_WSS_Integration_Lib"
        $prefix=if($role -eq 'gui'){'GUI'}elseif($role -eq 'ros'){'ROS'}else{'CLI'}
        $script:repository="cwru-non-academic/${prefix}_${family}_WSS_Application"
        $script:approval=@{candidate=@{run_id='11';artifact_id='12'}};$approval[$role]=@{source_sha=('b'*40)}
        $inputs=@{approval_json=($approval|ConvertTo-Json -Depth 8 -Compress)}
        if($family -eq 'CSharp'){$inputs.integration_sha='a'*40;$inputs.correlation_id='wss-11-12'}else{$inputs.wrapper_sha='a'*40}
        $script:title="Promote Integration $('a'*40) / wss-11-12"
        $script:intent="$($family.ToLowerInvariant())-$role-dispatch-$('a'*40)"
        $script:sources=@{};$sources[$owner]='a'*40;$sources[$repository]='b'*40
        $env:WSS_CI_CHANNEL=$channel;$env:GITHUB_ACTIONS='true';$env:GITHUB_REPOSITORY=$owner
        $env:GITHUB_RUN_ID='77';$env:GITHUB_RUN_ATTEMPT=if($scenario -in @('attempt2','reuse-attempt2')){'2'}else{'1'}
        $env:GITHUB_SHA='a'*40;$env:GITHUB_WORKFLOW_SHA=$env:GITHUB_SHA;$env:GITHUB_REF='refs/heads/'+$channel
        $env:GITHUB_EVENT_NAME=if($scenario -eq 'execution-event'){'push'}else{'workflow_dispatch'}
        $wf=if($family -eq 'Unity'){'dispatch-unity-promotion.yml'}else{'dispatch-cli-promotion.yml'}
        $env:GITHUB_WORKFLOW_REF="$owner/.github/workflows/$wf@refs/heads/$channel";$env:GITHUB_WORKSPACE=$work
        $env:PRODUCER_RUN_ID='11';$env:GH_TOKEN='synthetic-original'
        $ref=if($scenario -eq 'wrong-ref'){'wrong'}else{$channel}
        $request=Join-Path $work 'request.json';@{ref=$ref;inputs=$inputs}|ConvertTo-Json -Depth 8|Set-Content $request
        $read=if($scenario -eq 'missing-read'){''}else{'synthetic-read'};$write=if($scenario -eq 'missing-write'){''}else{'synthetic-write'}
        # Mapping/callback corruption tests target the common contract directly for all families.
        if($scenario -eq 'bad-owner'){$owner='foreign/repo'}
        if($scenario -eq 'bad-destination'){$repository='foreign/repo'}
        if($scenario -eq 'extra-source'){$sources['foreign/repo']='c'*40}
        if($scenario -eq 'bad-sources'){$sources[$repository]='c'*40}
        if($scenario -eq 'bad-intent'){$intent+='-foreign'}
        $errorText=$null;$result=$null
        try {
            if(($peerFamilies -contains 'CSharp') -and $family -eq 'CSharp' -and $scenario -notin @('bad-sources','bad-intent','bad-owner','bad-destination','extra-source','callback-contract')){$result=Send-WssCliDispatch $request $read $write}
            elseif(($peerFamilies -contains 'Unity') -and $family -eq 'Unity' -and $scenario -notin @('bad-sources','bad-intent','bad-owner','bad-destination','extra-source','callback-contract')){$result=Send-UnityGuiDispatch $request $read $write}
            elseif($scenario -eq 'callback-contract'){
                if($family -in @('CSharp','Unity')){
                    if($channel -eq 'dev'){throw 'Main callback contract applies only on main'}
                    $result=Send-WssCiApplicationDispatch $repository $request $read $write $owner $intent $sources
                }else{$result=Send-WssCiApplicationDispatch $repository $request $read $write $owner $intent $sources -AuthorizeMain {throw 'Must not call foreign callback'}}
            }elseif(($peerFamilies -notcontains $family) -and $family -in @('CSharp','Unity')){
                # This test double exercises the common callback boundary, not peer authorization algorithms.
                $authorize={param($request,$approval) Assert-WssCiWorkflowAuthorization ([string]$approval.candidate.run_id)}
                $result=Send-WssCiApplicationDispatch $repository $request $read $write $owner $intent $sources -AuthorizeMain $authorize
            }else{$result=Send-WssCiApplicationDispatch $repository $request $read $write $owner $intent $sources}
        }catch{$errorText=$_.Exception.Message}
        $label="$family/$role/$channel/$scenario"
        $success=$scenario -in @('send','reuse','reuse-attempt2')
        if($success -and $errorText){throw "${label}: unexpected error $errorText"}
        if(!$success -and !$errorText){throw "${label}: expected failure"}
        $expectedPosts=if($scenario -in @('send','uncertain')){1}else{0}
        if($posts -ne $expectedPosts){throw "${label}: POST count $posts instead of $expectedPosts ($errorText)"}
        if($env:GH_TOKEN -cne 'synthetic-original'){throw "${label}: token not restored"}
        if($success -and $result -cne $(if($scenario -in @('reuse','reuse-attempt2')){'reused'}else{'dispatched'})){throw "${label}: wrong result $result"}
        if($scenario -eq 'send' -and $sourceReads -ne 4){throw "${label}: final source reads missing"}
        if($scenario -eq 'uncertain' -and $errorText -notmatch 'failed or uncertain'){throw "${label}: uncertain outcome not preserved"}
        $count++
    }
}}}
"PASS $count common sender scenarios (real peer adapters=$($peerFamilies -join ','); other families common-only); all external commands synthetic; failures caught and asserted; suite exit 0."
}finally{Remove-Item -LiteralPath $work -Recurse -Force}