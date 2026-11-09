import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const owner=fileURLToPath(new URL('..',import.meta.url));
const literal=s=>"'"+s.replaceAll("'","''")+"'";
for(const helper of ['normal','missing','faulting-load','faulting-emitter'])test(`sender observations preserve operations/native status with ${helper}`,()=>{
 const dir=mkdtempSync(join(tmpdir(),'sender-observation-'));
 try{
  for(const name of ['DispatchProof.ps1','Channel.ps1'])writeFileSync(join(dir,name),readFileSync(join(owner,name)));
  if(helper!=='missing')writeFileSync(join(dir,'PhaseDiagnostics.ps1'),readFileSync(join(owner,'PhaseDiagnostics.ps1'),'utf8')+(helper==='faulting-load'?"\n$global:LASTEXITCODE=91; 'unwanted-loader-output'; throw 'loader-fault'\n":''));
  for(const nativePresent of [true,false])for(const scenario of ['send','reuse','authorization','source','reuse-error','intent','post']){
   const script=`$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. ${literal(join(dir,'DispatchProof.ps1'))}
$script:calls=[Collections.Generic.List[string]]::new()
$script:scenario=${literal(scenario)}
function Get-WssCiChannel { 'main' }
function Assert-WssCiWorkflowAuthorization { param($id) $script:calls.Add('authorization'); if($script:scenario -ceq 'authorization'){throw 'original-authorization'} }
function Assert-WssCiApplicationDispatchSources { param($sources,$channel) $script:calls.Add('source'); if($script:scenario -ceq 'source'){throw 'original-source'} }
function Get-WssCiApplicationDispatchReuse { param($repo,$mapping) $script:calls.Add('reuse'); if($script:scenario -ceq 'reuse-error'){throw 'original-reuse'}; return ($script:scenario -ceq 'reuse') }
function Assert-WssCiDispatchArtifacts { param($repo,$intent,[switch]$RequireCurrent) $script:calls.Add('intent'); if($script:scenario -ceq 'intent'){throw 'original-intent'} }
# Process.ps1 is loaded inside the real sender, so supply a synthetic boundary file.
$env:GITHUB_REPOSITORY='cwru-non-academic/Python_WSS_Integration_Lib'
$env:PRODUCER_RUN_ID='11';$env:GH_TOKEN='original-token'
$approval=@{candidate=@{run_id='11';artifact_id='12'};cli=@{source_sha=('b'*40)}}
$request=${literal(join(dir,'request.json'))}
@{ref='main';inputs=@{wrapper_sha=('a'*40);approval_json=($approval|ConvertTo-Json -Depth 6 -Compress)}}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $request
$sources=@{'cwru-non-academic/Python_WSS_Integration_Lib'=('a'*40);'cwru-non-academic/CLI_Python_WSS_Application'=('b'*40)}
${helper==='faulting-emitter'?"function Write-Host { $global:LASTEXITCODE=91; throw 'emitter-fault' }":''}
${nativePresent?'$global:LASTEXITCODE=23':'Remove-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue'}
$result=$null;$failure=$null
try{$result=Send-WssCiApplicationDispatch 'cwru-non-academic/CLI_Python_WSS_Application' $request 'read-token' 'write-token' $env:GITHUB_REPOSITORY ('python-cli-dispatch-'+('a'*40)) $sources}catch{$failure=$_.Exception.Message}
@{result=$result;failure=$failure;calls=@($script:calls.ToArray());native=$(if(Get-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue){$global:LASTEXITCODE}else{$null});token=$env:GH_TOKEN}|ConvertTo-Json -Compress -Depth 5
exit 0
`;
   writeFileSync(join(dir,'Process.ps1'),`function Invoke-WssCiProcess { param($Executable,$Arguments,$FailureMessage) $script:calls.Add('post'); if($env:GH_TOKEN -cne 'write-token'){throw 'wrong-post-token'}; if($script:scenario -ceq 'post'){throw 'original-post'} }\n`);
   writeFileSync(join(dir,'case.ps1'),script);
   const r=spawnSync('pwsh',['-NoLogo','-NoProfile','-NonInteractive','-File',join(dir,'case.ps1')],{encoding:'utf8'});
   assert.ifError(r.error);assert.equal(r.status,0,r.stderr);
   const lines=r.stdout.trim().split(/\r?\n/),actual=JSON.parse(lines.at(-1));
   assert.equal(actual.native,nativePresent?23:null,`${helper}/${scenario}: native status`);assert.equal(actual.token,'original-token');
   assert.doesNotMatch(r.stdout,/unwanted-loader-output/);assert.doesNotMatch(r.stderr,/loader-fault|emitter-fault/);
   const expected={send:['authorization','source','reuse','intent','source','post'],reuse:['authorization','source','reuse'],authorization:['authorization'],source:['authorization','source'],'reuse-error':['authorization','source','reuse'],intent:['authorization','source','reuse','intent'],post:['authorization','source','reuse','intent','source','post']}[scenario];
   assert.deepEqual(actual.calls,expected);
   if(scenario==='send'||scenario==='reuse'){assert.equal(actual.failure,null);assert.equal(actual.result,scenario==='send'?'dispatched':'reused');}
   else{assert.equal(actual.result,null);assert.equal(actual.failure,'original-'+(scenario==='reuse-error'?'reuse':scenario));}
  }
 }finally{rmSync(dir,{recursive:true,force:true});}
});
