import {test,after} from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync,cpSync,existsSync,realpathSync} from 'node:fs';
import {join,resolve,dirname} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {CORE,CORE_JOBS,digest,bytesDigest} from '../verify.mjs';
import {channelContext} from '../channels.mjs';
const here=dirname(fileURLToPath(import.meta.url));
const coreSource=resolve(process.env.WSS_CORE_REFERENCE||'.ci-reference/Core');
const base=mkdtempSync(join(tmpdir(),'wss receipt \u03a9 '));
after(()=>rmSync(base,{recursive:true,force:true}));
const git=(root,...args)=>execFileSync('git',['-C',root,...args],{encoding:'utf8',stdio:['ignore','pipe','pipe']}).trim();
function put(root,path,text){mkdirSync(dirname(join(root,path)),{recursive:true});writeFileSync(join(root,path),text);}
function init(root){mkdirSync(root,{recursive:true});git(root,'init');put(root,'.gitattributes','* text=auto eol=lf\n');}
function commit(root){git(root,'add','.');git(root,'-c','user.name=CI','-c','user.email=ci@example.invalid','commit','--allow-empty','-m','pure receipt fixture');return git(root,'rev-parse','HEAD');}
const owner=join(base,'bootstrap/Python_WSS_Integration_Lib');init(owner);cpSync(resolve(here,'..'),join(owner,'.github/scripts/wss-ci'),{recursive:true});put(owner,'.github/workflows/notify-core-stage.yml',readFileSync(resolve(here,'../../../workflows/notify-core-stage.yml')));put(owner,'.github/scripts/Write-ReleaseReceipt.mjs',readFileSync(resolve(here,'../../Write-ReleaseReceipt.mjs')));const P=commit(owner);
const core=join(base,'core');init(core);cpSync(join(coreSource,'tools'),join(core,'tools'),{recursive:true});
const manifest=JSON.parse(readFileSync(join(core,'tools/ci/sync-tooling.json')));manifest.origins.integration.commit=P;manifest.origins.integration.ref=`refs/heads/ci/tooling/${P}`;put(core,'tools/ci/sync-tooling.json',JSON.stringify(manifest));const C=commit(core);
const {expectedLock,sourceBytes}=await import(pathToFileURL(join(core,'tools/ci/sync-tooling.mjs')));
const {receiptProfiles,renderReceiptWorkflow}=await import(pathToFileURL(join(owner,'.github/scripts/wss-ci/receipt-workflows.mjs')));
const {runReceipt,readOnlyGh,receiptRoots,ROOT_KEYS}=await import(pathToFileURL(join(owner,'.github/scripts/wss-ci/receipt.mjs')));
const zipCache=new Map();
function candidateZip(candidate) {
 const text=JSON.stringify(candidate);if(zipCache.has(text))return zipCache.get(text);
 const dir=mkdtempSync(join(tmpdir(),'receipt-candidate-zip-'));
 try {writeFileSync(join(dir,'candidate.json'),text);writeFileSync(join(dir,'zip.ps1'),'param([string]$Source,[string]$Destination)\n$ErrorActionPreference="Stop"; Compress-Archive -LiteralPath $Source -DestinationPath $Destination');execFileSync('pwsh',['-NoProfile','-File',join(dir,'zip.ps1'),join(dir,'candidate.json'),join(dir,'proof.zip')]);const bytes=readFileSync(join(dir,'proof.zip'));zipCache.set(text,bytes);return bytes;}finally{rmSync(dir,{recursive:true,force:true});}
}
const sha=n=>String(n).repeat(40);
const stub=`param([string]$TargetId,[string]$ProducerRunId,[string]$PlanId,[string]$ContextPath,[string]$ToolsRoot,[string]$WorkRoot,[string]$OutputPath)
$ErrorActionPreference='Stop'
$ctx=Get-Content -LiteralPath $ContextPath -Raw|ConvertFrom-Json
if(!$ctx.paths.engineRoot -or !$ctx.paths.coreRoot -or $ctx.head -cne $env:GITHUB_SHA){throw 'Broken common/native contract'}
Set-Content -LiteralPath $env:WSS_TEST_SENTINEL -Value $ctx.target.id
if($env:WSS_TEST_MODE -ceq 'fail'){exit 17}
if($env:WSS_TEST_MODE -ceq 'no-output'){exit 0}
if($env:WSS_TEST_MODE -ceq 'dirty'){Set-Content -LiteralPath (Join-Path $ctx.paths.sourceRoot 'untracked-native-file') -Value 'dirty'}
Get-Content -LiteralPath $env:WSS_TEST_PROOFS -Raw|Set-Content -LiteralPath $OutputPath
`;
function sources(root,id){
 init(root);const p=receiptProfiles[id],lock=expectedLock(p.target.repository.split('/')[1],C,dirname(owner));
 for(const [path,entry] of Object.entries(lock.files))put(root,path,sourceBytes({origin:entry.origin,path:entry.source},dirname(owner),C));
 put(root,'.github/scripts/wss-ci.lock.json',JSON.stringify(lock));
 for(const name of ['Write-ReleaseReceipt.ps1','Verify-ReleaseAcceptance.ps1'])put(root,`.github/scripts/${name}`,stub);
 for(const path of p.target.trusted_paths)if(path!=='.github/scripts'&&!existsSync(join(root,path)))put(root,path,path.endsWith('.json')?JSON.stringify({baseline_ready:true,candidate_preflight_ready:true}):'# frozen source\n');
 if(p.receipt.configuration)put(root,p.receipt.configuration,JSON.stringify({baseline_ready:true,candidate_preflight_ready:true}));
}
let sequence=0;const cases=new Map();
function fixture(id,channel){
 const key=`${id}/${channel}`;if(cases.has(key))return cases.get(key).reset();
 const home=join(base,`case ${++sequence} ${id} ${channel}`);mkdirSync(home);
 const profile=receiptProfiles[id],app=profile.role!=='wrapper',source=join(home,'accepted'),validator=app?join(home,'validator'):source,integration=app?join(home,'integration'):source;
 let V=P;
 if(app){sources(validator,profile.wrapper);V=commit(validator);cpSync(validator,integration,{recursive:true});}
 sources(source,id);put(source,'.github/workflows/release-receipt.yml',renderReceiptWorkflow(id,{core:C,engine:P,validator:V}).text);
 if(app)for(const path of Object.values(profile.target.parents))git(source,'update-index','--add','--cacheinfo',`160000,${V},${path}`);
 const head=commit(source),context=channelContext(channel),m=JSON.parse(readFileSync(join(core,`tools/release/targets.${channel}.json`)));
 const t=m.targets.find(t=>t.id===id),zip=Buffer.from('canonical archive');
 const candidate={repository:CORE,commit:sha(1),run_id:'1',artifact_id:'2',archive:'WSS-Universal-ci.zip',sha256:bytesDigest(zip)};
 const snapshots=Object.fromEntries(m.targets.map(target=>{const root=target.id===id?source:target.id===profile.wrapper?validator:null;return [target.id,{head_sha:sha(2),trusted:Object.fromEntries(target.trusted_paths.map(path=>[path,root?git(root,'rev-parse',`HEAD:${path}`):sha(3)]))}];}));
 const ws=Object.fromEntries(m.targets.flatMap(target=>{const row=(key,branch,role)=>[`${target.id}:${key}`,{repository:target.repository,branch,...(role?{role}:{}),source_sha:sha(2),tree_sha:target.id===id?git(source,'rev-parse','HEAD:.github/workflows'):sha(3)}];return channel==='main'?[row('accepted-baseline','main','accepted-baseline'),...(target.kind==='payload'?[row('execution-authority','main','execution-authority'),row('counterpart','dev','counterpart')]:[])]:[row('dev','dev'),...(target.kind==='payload'?[row('main','main')]:[])];}));
 const body={schema:context.planSchema,channel,candidate,manifest:m,manifest_sha256:digest(m),target_snapshots:snapshots,workflow_snapshots:{schema:channel==='main'?'wss-workflow-snapshots/v2':'wss-workflow-snapshots/v1',targets:ws}},plan={...body,plan_id:digest(body)};
 const pr={number:10,merged:true,state:'closed',merge_commit_sha:head,merged_at:'2026-11-01T00:00:00Z',user:{type:'Bot'},merged_by:{type:'User'},base:{ref:channel,repo:{full_name:t.repository}},head:{sha:sha(4),ref:`automation/${profile.family}-wss-1-${candidate.sha256}`,repo:{full_name:t.repository}}};
 const identity={repository:{full_name:t.repository},head_repository:{full_name:t.repository},head_sha:head,head_branch:channel,run_attempt:1},normal={...identity,id:20,path:t.workflow,event:'push',status:'completed',conclusion:'success',created_at:'2026-11-01T00:01:00Z'};
 const proofs=Array.from({length:profile.preflights},(_,i)=>({repository:t.repository,run_id:String(30+i),source_sha:sha(2),workflow:'.github/workflows/wss-preflight.yml',attempt:1,jobs:[{id:'900',name:'Native proof',status:'completed',conclusion:'success'}],artifacts:[{id:String(1000+i),name:'rich-proof',digest:'sha256:'+bytesDigest(Buffer.from('rich proof ZIP'))}],logs:[]}));
 const producer={id:1,repository:{full_name:CORE},head_repository:{full_name:CORE},head_sha:sha(1),head_branch:channel,path:'.github/workflows/artifacts.yml',event:'push',status:'completed',conclusion:'success',run_attempt:1},artifact={id:2,name:'universal-release-assets',expired:false,workflow_run:{id:1,head_sha:sha(1)}};
 const richBytes=Buffer.from('rich proof ZIP'),candidateBytes=candidateZip(candidate);
 const proofArtifact=(run,name)=>({id:(name==='rich-proof'?1000:2000)+Number(run)-30,name,digest:'sha256:'+bytesDigest(name==='rich-proof'?richBytes:candidateBytes),expired:false,workflow_run:{id:Number(run),head_sha:sha(2)}});
 const state={normal:[normal],associations:[pr],proofs,late:false};
 const g={head:(repo,branch)=>repo===CORE?sha(1):repo===t.repository?(state.late&&existsSync(env.WSS_TEST_SENTINEL)?sha(9):head):V,
 get:path=>path.includes('/actions/artifacts/')?proofArtifact(String(30+Number(path.split('/').at(-1))%1000),Number(path.split('/').at(-1))<2000?'rich-proof':'wss-candidate-provenance'):path.includes('/contents/')?{type:'file',encoding:'base64',content:Buffer.from(JSON.stringify(m)).toString('base64')}:pr,
 run:(repo,run)=>String(run)==='1'?producer:String(run)==='99'?{...identity,id:99,event:'workflow_dispatch',path:'.github/workflows/release-receipt.yml'}:String(run)==='20'?normal:{...identity,id:Number(run),head_sha:sha(2),event:'workflow_dispatch',path:'.github/workflows/wss-preflight.yml',status:'completed',conclusion:'success'},
 pages:path=>path.includes('/artifacts')?['rich-proof','wss-candidate-provenance'].map(name=>proofArtifact(path.split('/runs/')[1].split('/')[0],name)):path.includes('/commits/')?state.associations:state.normal,
 artifactBytes:(repo,id)=>Number(id)<2000?richBytes:candidateBytes,
 object:(repo,ref,path)=>path==='.github/workflows'?{type:'tree',sha:git(source,'rev-parse','HEAD:.github/workflows')}:Object.values(t.parents).includes(path)?{type:'commit',mode:'160000',sha:V}:{sha:snapshots[id].trusted[path]},
 jobs:(repo,r)=>r.path==='.github/workflows/wss-preflight.yml'?[{id:900,name:'Native proof',status:'completed',conclusion:'success'}]:(repo===CORE?CORE_JOBS:t.jobs).map(name=>({name,status:'completed',conclusion:'success'})),artifact:()=>artifact,tree:()=>sha(6),
 download:(repo,run,name)=>name==='wss-propagation-plan'?{'plan.json':Buffer.from(JSON.stringify(plan))}:name==='universal-release-assets'?{[candidate.archive]:zip,'SHA256SUMS.txt':Buffer.from(`${candidate.sha256}  ${candidate.archive}\n`)}:{'candidate.json':Buffer.from(JSON.stringify(candidate))}};
 const env={...process.env,GITHUB_ACTIONS:'true',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REF:context.ref,GITHUB_SHA:head,GITHUB_REPOSITORY:t.repository,GITHUB_RUN_ID:'99',GITHUB_RUN_ATTEMPT:'1',TARGET_ID:id,PRODUCER_RUN_ID:'1',PLAN_ID:plan.plan_id,WSS_CI_CHANNEL:channel,GITHUB_WORKFLOW_SHA:head,GITHUB_WORKFLOW_REF:`${t.repository}/.github/workflows/release-receipt.yml@refs/heads/${channel}`,WSS_RECEIPT_ENGINE_SHA:P,WSS_RECEIPT_CORE_SHA:C,WSS_RECEIPT_VALIDATOR_SHA:V,WSS_TEST_SENTINEL:join(home,'native ran.txt'),WSS_TEST_PROOFS:join(home,'proofs.json'),WSS_TEST_MODE:'',GITHUB_OUTPUT:join(home,'outputs.txt')};
 const config={sourceRoot:source,toolsRoot:profile.receipt.adapter_owner==='receiver'?source:validator,validatorRoot:validator,integrationRoot:integration,engineRoot:owner,coreRoot:core,outputRoot:join(home,'output')};
 const f={home,source,config,env,g,state,plan,producer,artifact,pr,normal,proofs,run:()=>{writeFileSync(env.WSS_TEST_PROOFS,JSON.stringify(proofs));return runReceipt(config,{g,env});}};
 const originals=new Map([config,env,g,producer,artifact,pr,normal].map(o=>[o,{...o}])),originalProofs=structuredClone(proofs);
 f.reset=()=>{
   for(const [object,original] of originals){for(const k of Object.keys(object))delete object[k];Object.assign(object,original);}
   for(const path of [config.outputRoot,env.WSS_TEST_SENTINEL,env.GITHUB_OUTPUT,join(source,'untracked.txt'),join(source,'untracked-native-file')])rmSync(path,{recursive:true,force:true});
   proofs.splice(0,proofs.length,...structuredClone(originalProofs));state.normal=[normal];state.associations=[pr];state.late=false;
   return f;
 };
 cases.set(key,f);return f;
}
// Exercise physical checkout identity independently of the receipt network/adapter
// fixture. Windows must exercise a real filesystem 8.3 alias, not a mocked path.
function rootFixture() {
 const home=mkdtempSync(join(base,'receipt root identity '));
 const source=join(home,'accepted source'),engine=join(home,'engine source'),core=join(home,'core source');
 for(const root of [source,engine,core]){init(root);commit(root);}
 const profile=Object.values(receiptProfiles).find(p=>p.family==='python'&&p.role==='wrapper');
 return {home,source,profile,config:{sourceRoot:source,toolsRoot:source,validatorRoot:source,integrationRoot:source,engineRoot:engine,coreRoot:core,outputRoot:join(home,'fresh output')}};
}
function shortPath(path) {
 return execFileSync('pwsh',['-NoProfile','-NonInteractive','-Command',"$ErrorActionPreference='Stop'; (New-Object -ComObject Scripting.FileSystemObject).GetFolder($env:WSS_TEST_LONG_PATH).ShortPath"],{encoding:'utf8',env:{...process.env,WSS_TEST_LONG_PATH:path}}).trim();
}
test('receipt roots preserve exact physical checkout identities',()=>{
 const f=rootFixture(),roots=receiptRoots(f.config,f.profile);
 for(const [role,path] of Object.entries(f.config))assert.equal(roots[role],role==='outputRoot'?join(realpathSync.native(f.home),'fresh output'):realpathSync.native(path));
 assert.equal(existsSync(roots.outputRoot),false);
});
test('receipt roots canonicalize real Windows 8.3 and long checkout aliases',{skip:process.platform!=='win32'},()=>{
 const f=rootFixture(),short=Object.fromEntries(['sourceRoot','engineRoot','coreRoot'].map(role=>[role,shortPath(f.config[role])]));
 for(const [role,path] of Object.entries(short)){
  assert.notEqual(path.toLowerCase(),f.config[role].toLowerCase(),'Regression requires an actual distinct Windows 8.3 path');
  assert.equal(realpathSync.native(path),realpathSync.native(f.config[role]));
  assert.equal(realpathSync.native(git(path,'rev-parse','--show-toplevel')),realpathSync.native(path));
 }
 const expected=receiptRoots(f.config,f.profile);
 const mixed={...f.config,...short,toolsRoot:short.sourceRoot,integrationRoot:short.sourceRoot,outputRoot:join(shortPath(f.home),'fresh output')};
 assert.deepEqual(receiptRoots(mixed,f.profile),expected);
 assert.deepEqual(receiptRoots({...mixed,sourceRoot:f.source,validatorRoot:short.sourceRoot},f.profile),expected);
 assert.throws(()=>receiptRoots({...mixed,engineRoot:short.sourceRoot},f.profile),/Undeclared overlapping receipt root roles/);
 mkdirSync(join(f.source,'not-checkout-root'));
 assert.throws(()=>receiptRoots({...mixed,sourceRoot:join(short.sourceRoot,'not-checkout-root')},f.profile),/checkout root/);
 assert.equal(existsSync(expected.outputRoot),false);
});
for(const [name,mutate,error] of [
 ['subdirectory',f=>{const sub=join(f.source,'subdirectory');mkdirSync(sub);f.config.sourceRoot=sub;},/checkout root/],
 ['undeclared alias',f=>f.config.engineRoot=f.source,/Undeclared overlapping receipt root roles/],
 ['split wrapper roles',f=>f.config.toolsRoot=f.config.engineRoot,/Wrapper native roles must alias/],
 ['nested checkout',f=>{const nested=join(f.source,'nested');init(nested);commit(nested);f.config.engineRoot=nested;},/Undeclared overlapping receipt root roles/],
 ['tracked dirt',f=>put(f.source,'.gitattributes','* text=auto eol=crlf\n'),/checkouts must be clean/],
 ['untracked dirt',f=>put(f.source,'unexpected.txt','dirty'),/checkouts must be clean/],
 ['existing output',f=>mkdirSync(f.config.outputRoot),/output root must be new/],
 ['output inside checkout',f=>f.config.outputRoot=join(f.source,'receipt'),/Undeclared overlapping receipt root roles/],
 ['relative root',f=>f.config.sourceRoot='relative',/explicit absolute paths/],
 ['extra role',f=>f.config.extraRoot=f.source,/exactly the declared root roles/]
])test(`receipt roots reject ${name}`,()=>{const f=rootFixture();mutate(f);assert.throws(()=>receiptRoots(f.config,f.profile),error);});
const immutableRootRoles=ROOT_KEYS.filter(role=>role!=='outputRoot');
function ignoredNestedCheckout(parent,name) {
 const ignore=join(parent,'.gitignore');
 put(parent,'.gitignore',(existsSync(ignore)?readFileSync(ignore,'utf8'):'')+`\n/${name}/\n`);
 commit(parent);
 const nested=join(parent,name);init(nested);commit(nested);
 assert.equal(git(parent,'status','--porcelain','--untracked-files=all'),'','The parent must be clean so overlap, not dirt, is rejected');
 assert.equal(git(nested,'status','--porcelain','--untracked-files=all'),'','The nested checkout must independently be clean');
 return nested;
}
for(const role of immutableRootRoles)for(const name of ['..receipt','...receipt'])test(`receipt roots reject two-dot ${name} output beneath ${role}`,()=>{
 const f=rootFixture();f.config.outputRoot=join(f.config[role],name);
 assert.throws(()=>receiptRoots(f.config,f.profile),/Undeclared overlapping receipt root roles/);
 assert.equal(existsSync(f.config.outputRoot),false);
});
for(const name of ['..engine','...engine'])for(const reverse of [false,true])test(`receipt roots reject two-dot ${name} nested checkout with ${reverse?'engine':'source'} ancestor`,()=>{
 const f=rootFixture();
 if(reverse){const nested=ignoredNestedCheckout(f.config.engineRoot,name);for(const role of ['sourceRoot','toolsRoot','validatorRoot','integrationRoot'])f.config[role]=nested;}
 else f.config.engineRoot=ignoredNestedCheckout(f.source,name);
 assert.throws(()=>receiptRoots(f.config,f.profile),/Undeclared overlapping receipt root roles/);
 assert.equal(existsSync(f.config.outputRoot),false);
});
test('receipt roots admit external output, sibling-prefix roots and declared aliases with two-dot names',()=>{
 const f=rootFixture(),sibling=join(f.home,'accepted source..engine');init(sibling);commit(sibling);
 f.config.engineRoot=sibling;f.config.outputRoot=join(f.home,'accepted source...receipt');
 const roots=receiptRoots(f.config,f.profile);
 assert.equal(roots.engineRoot,realpathSync.native(sibling));
 assert.equal(roots.outputRoot,join(realpathSync.native(f.home),'accepted source...receipt'));
 for(const role of ['toolsRoot','validatorRoot','integrationRoot'])assert.equal(roots[role],roots.sourceRoot);
 assert.equal(existsSync(roots.outputRoot),false);
});
async function rejectsOverlapBeforeExecution(f) {
 let transportCalls=0;
 const g=new Proxy({}, {get(){transportCalls++;throw Error('Transport must not be consulted for overlapping roots');}});
 await assert.rejects(runReceipt(f.config,{g,env:f.env}),error=>error.code==='WSS_RECEIPT_ROOTS'&&/Undeclared overlapping receipt root roles/.test(error.message));
 assert.equal(transportCalls,0);
 assert.equal(existsSync(f.env.WSS_TEST_SENTINEL),false);
 assert.equal(existsSync(f.config.outputRoot),false);
 assert.equal(existsSync(f.env.GITHUB_OUTPUT),false);
}
for(const id of Object.keys(receiptProfiles))for(const channel of ['dev','main']) {
 for(const role of immutableRootRoles)for(const name of ['..receipt','...receipt'])test(`${id}/${channel}: two-dot ${name} output beneath ${role} fails ROOTS before adapter or transport`,async()=>{
  const f=fixture(id,channel);f.config.outputRoot=join(f.config[role],name);
  await rejectsOverlapBeforeExecution(f);
 });
 test(`${id}/${channel}: two-dot ignored nested engine fails ROOTS before adapter or transport`,async()=>{
  const f=fixture(id,channel);
  try{f.config.engineRoot=ignoredNestedCheckout(f.source,'..engine');await rejectsOverlapBeforeExecution(f);}
  finally{cases.delete(`${id}/${channel}`);}
 });
}
for(const id of Object.keys(receiptProfiles))for(const channel of ['dev','main']) {
 test(`${id}/${channel}: generated workflow -> immutable engine -> real pwsh adapter -> receipt`,async()=>{const f=fixture(id,channel),r=await f.run();assert.equal(r.target_id,id);assert.equal(r.channel,channel);assert.equal(r.preflights.length,receiptProfiles[id].preflights);assert.ok(existsSync(f.env.WSS_TEST_SENTINEL));assert.ok(existsSync(join(f.config.outputRoot,'receipt.json')));assert.match(readFileSync(f.env.GITHUB_OUTPUT,'utf8'),/artifact_name=wss-acceptance-/);});
 for(const [name,phase,mutate] of [
 ['wrong repository','ELIGIBILITY',f=>f.env.GITHUB_REPOSITORY=CORE],['wrong channel','ELIGIBILITY',f=>f.env.WSS_CI_CHANNEL='other'],['wrong event','ELIGIBILITY',f=>f.env.GITHUB_EVENT_NAME='pull_request'],['wrong workflow source','ELIGIBILITY',f=>f.env.GITHUB_WORKFLOW_SHA=sha(9)],
 ['unknown root','ROOTS',f=>f.config.contractRoot=core],['aliased engine','ROOTS',f=>f.config.engineRoot=f.source],['dirty root','ROOTS',f=>put(f.source,'untracked.txt','x')],['wrong engine pin','PINS',f=>f.env.WSS_RECEIPT_ENGINE_SHA=sha(9)],['wrong core pin','PINS',f=>f.env.WSS_RECEIPT_CORE_SHA=sha(9)],
 ['wrong producer channel','AUTHORITY',f=>f.producer.head_branch=channel==='dev'?'main':'dev'],['failed producer','AUTHORITY',f=>f.producer.conclusion='failure'],['wrong archive id','AUTHORITY',f=>f.artifact.id=88],['missing merge','AUTHORITY',f=>f.state.associations=[]],['ambiguous merge','AUTHORITY',f=>f.state.associations.push(f.pr)],['missing CI','AUTHORITY',f=>f.state.normal=[]],['duplicate CI','AUTHORITY',f=>f.state.normal.push({...f.normal,id:21})],['failed required job','AUTHORITY',f=>f.g.jobs=()=>[]]
 ])test(`${id}/${channel}: ${name} fails ${phase} before native execution`,async()=>{const f=fixture(id,channel);mutate(f);await assert.rejects(f.run(),e=>e.code===`WSS_RECEIPT_${phase}`);assert.equal(existsSync(f.env.WSS_TEST_SENTINEL),false);assert.equal(existsSync(f.config.outputRoot),false);assert.equal(existsSync(f.env.GITHUB_OUTPUT),false);});
 for(const [name,phase,mutate] of [['native exit','ADAPTER',f=>f.env.WSS_TEST_MODE='fail'],['native missing output','ADAPTER',f=>f.env.WSS_TEST_MODE='no-output'],['missing descriptor','PROOF',f=>f.proofs.pop()],['wrong proof source','PROOF',f=>f.proofs[0].source_sha=sha(8)],['duplicate proof','PROOF',f=>f.proofs[1]=f.proofs[0]],['late movement','RECHECK',f=>f.state.late=true],['native dirtied root','RECHECK',f=>f.env.WSS_TEST_MODE='dirty']])test(`${id}/${channel}: ${name} never emits`,async()=>{const f=fixture(id,channel);mutate(f);await assert.rejects(f.run(),e=>e.code===`WSS_RECEIPT_${phase}`);assert.ok(existsSync(f.env.WSS_TEST_SENTINEL));assert.equal(existsSync(f.config.outputRoot),false);assert.equal(existsSync(f.env.GITHUB_OUTPUT),false);});
}

for(const id of Object.keys(receiptProfiles))for(const channel of ['dev','main']) {
 for(const [name,phase,mutate] of [
  ['accepted source','AUTHORITY',f=>{f.env.GITHUB_SHA=sha(9);f.env.GITHUB_WORKFLOW_SHA=sha(9);}],
  ['frozen plan','AUTHORITY',f=>f.env.PLAN_ID='f'.repeat(64)],
  ['missing workflow freeze','AUTHORITY',f=>{delete f.plan.workflow_snapshots;const {plan_id,...body}=f.plan;f.plan.plan_id=digest(body);f.env.PLAN_ID=f.plan.plan_id;}],
  ['wrong workflow freeze source','AUTHORITY',f=>{Object.values(f.plan.workflow_snapshots.targets)[0].source_sha=sha(9);const {plan_id,...body}=f.plan;f.plan.plan_id=digest(body);f.env.PLAN_ID=f.plan.plan_id;}],
  ['stale normal CI','AUTHORITY',f=>f.normal.created_at='2025-01-01T00:00:00Z'],
  ['missing or duplicate producer artifact','AUTHORITY',f=>f.g.artifact=()=>{throw Error('Missing/duplicate producer artifact');}],
  ['committed source lock','PINS',f=>{const path='.github/scripts/wss-ci.lock.json',lock=JSON.parse(readFileSync(join(f.source,path)));lock.source_commit=sha(9);put(f.source,path,JSON.stringify(lock));const head=commit(f.source);f.env.GITHUB_SHA=head;f.env.GITHUB_WORKFLOW_SHA=head;}]
 ])test(`${id}/${channel}: expanded ${name} rejection`,async()=>{
  cases.delete(`${id}/${channel}`);const f=fixture(id,channel);mutate(f);await assert.rejects(f.run(),e=>e.code===`WSS_RECEIPT_${phase}`);assert.equal(existsSync(f.env.WSS_TEST_SENTINEL),false);assert.equal(existsSync(f.config.outputRoot),false);cases.delete(`${id}/${channel}`);
 });
}
test('all18 generated callers retain existing credential scopes and fixed sequence',()=>{const audit=JSON.parse(readFileSync(join(here,'receipt-permission-audit.json')));assert.equal(audit.length,18);for(const row of audit){assert.deepEqual(row.old,row.proposed);assert.deepEqual(row.delta,[]);const text=renderReceiptWorkflow(row.target,{core:C,engine:P,validator:receiptProfiles[row.target].role==='wrapper'?P:sha(8)}).text;assert.ok(text.includes(`repositories: ${row.old.repositories.join(',')}`));assert.ok(text.indexOf('Require static caller')<text.indexOf('create-github-app-token'));assert.ok(text.indexOf('create-github-app-token')<text.indexOf('Admit authority'));assert.ok(text.indexOf('Admit authority')<text.indexOf('upload-artifact'));assert.match(text,/if: \$\{\{ success\(\) \}\}/);assert.doesNotMatch(text,/ref: main|Write-ReleaseReceipt\.ps1|Write-ReleaseReceipt\.mjs|contractRoot/);}});
test('read-only transport rejects writes and retired launcher fails closed',()=>{for(const args of [['api','--method','POST',`repos/${CORE}/dispatches`],['workflow','run','promote.yml']])assert.throws(()=>readOnlyGh(args));assert.match(readFileSync(resolve(here,'../../Write-ReleaseReceipt.mjs'),'utf8'),/Legacy receipt launcher is retired/);});

test('all18 actual generated PowerShell launch blocks preserve closed root roles and argv',()=>{
 for(const id of Object.keys(receiptProfiles))for(const channel of ['dev','main']){
  const p=receiptProfiles[id],app=p.role!=='wrapper',text=renderReceiptWorkflow(id,{core:C,engine:P,validator:app?sha(8):P}).text;
  const section=text.slice(text.indexOf('      - name: Admit authority'),text.indexOf('      - uses: actions/upload-artifact'));
  const block=section.slice(section.indexOf('        run: |\n')+'        run: |\n'.length).split('\n').map(line=>line.startsWith('          ')?line.slice(10):line).join('\n');
  const home=join(base,`launch ${id} ${channel}`);mkdirSync(home);const workspace=join(home,'workspace \u03a9'),temp=join(home,'temp');mkdirSync(workspace);mkdirSync(temp);
  const script=join(home,'launch.ps1'),report=join(home,'argv.json');
  writeFileSync(script,`$ErrorActionPreference='Stop'\nfunction node { @{argv=@($args)}|ConvertTo-Json|Set-Content -LiteralPath $env:WSS_TEST_REPORT; $global:LASTEXITCODE=0 }\n`+block);
  execFileSync('pwsh',['-NoProfile','-NonInteractive','-File',script],{env:{...process.env,GITHUB_WORKSPACE:workspace,RUNNER_TEMP:temp,WSS_TEST_REPORT:report,WSS_CI_CHANNEL:channel},stdio:'pipe'});
  const args=JSON.parse(readFileSync(report,'utf8').replace(/^\uFEFF/,'')).argv;
  assert.deepEqual(args,[join(workspace,'bootstrap/Python_WSS_Integration_Lib/.github/scripts/wss-ci/receipt.mjs'),join(temp,'receipt-config.json')]);
  const actual=JSON.parse(readFileSync(args[1],'utf8').replace(/^\uFEFF/,''));
  assert.deepEqual(actual,{sourceRoot:join(workspace,'accepted'),toolsRoot:join(workspace,p.receipt.adapter_owner==='receiver'?'accepted':app?'validator':'accepted'),validatorRoot:join(workspace,app?'validator':'accepted'),integrationRoot:join(workspace,app?'integration':'accepted'),engineRoot:join(workspace,'bootstrap/Python_WSS_Integration_Lib'),coreRoot:join(workspace,'core'),outputRoot:join(temp,'release-receipt')});
 }
});

test('actual immutable Node CLI admits local eligibility without credentials and rejects extra entrypoints',()=>{
 const entry=join(owner,'.github/scripts/wss-ci/receipt.mjs');
 for(const id of Object.keys(receiptProfiles))for(const channel of ['dev','main']){
  const f=fixture(id,channel),env={...f.env,GH_TOKEN:'',GITHUB_TOKEN:''};
  execFileSync(process.execPath,[entry,'--eligibility',f.source],{env,stdio:'pipe'});
  assert.equal(existsSync(f.env.WSS_TEST_SENTINEL),false);
  assert.throws(()=>execFileSync(process.execPath,[entry,'--eligibility',f.source,'--skip-authority'],{env,stdio:'pipe'}));
 }
});

test('all18 generated product checkouts retain historical sources required by native evidence',()=>{
 for(const id of Object.keys(receiptProfiles))for(const channel of ['dev','main']) {
  const p=receiptProfiles[id],text=renderReceiptWorkflow(id,{core:C,engine:P,validator:p.role==='wrapper'?P:sha(8)}).text;
  const checkouts=text.split('      - uses: actions/checkout@v4\n').slice(1).map(block=>block.split(/(?=^      - )/m)[0]);
  for(const role of ['accepted','integration']) {
   const matches=checkouts.filter(block=>block.includes(`          path: ${role}\n`));
   assert.equal(matches.length,1,`${id}/${channel}: one explicit ${role} source checkout`);
   assert.match(matches[0],/^          fetch-depth: 0$/m,`${id}/${channel}: ${role} must retain frozen ancestor objects for native source comparisons`);
   assert.match(matches[0],/^          persist-credentials: false$/m);
  }
  // Tool-only roots need exact pinned blobs; product roots need their ancestors.
  assert.match(checkouts.find(block=>block.includes('          path: accepted\n')),/ref: \$\{\{ github.sha \}\}/);
 }
});

for(const id of Object.keys(receiptProfiles))for(const channel of ['dev','main'])for(const late of [false,true])test(`${id}/${channel}: native attempt movement ${late?'at final recheck':'after adapter return'} never emits`,async()=>{
 const f=fixture(id,channel),run=f.g.run;let reads=0;f.g.run=(repo,id)=>{const r=run(repo,id);if(r.path==='.github/workflows/wss-preflight.yml'&&++reads>(late?receiptProfiles[f.env.TARGET_ID].preflights*2:0))return {...r,run_attempt:2};return r;};
 await assert.rejects(f.run(),e=>e.code===`WSS_RECEIPT_${late?'RECHECK':'PROOF'}`);assert.ok(existsSync(f.env.WSS_TEST_SENTINEL));assert.equal(existsSync(f.config.outputRoot),false);assert.equal(existsSync(f.env.GITHUB_OUTPUT),false);
});
for(const id of Object.keys(receiptProfiles))for(const channel of ['dev','main'])for(const [name,mutate] of [
 ['missing observed attempt',f=>delete f.proofs[0].attempt],
 ['invalid observed attempt',f=>f.proofs[0].attempt=0],
 ['changed native job status',f=>{const jobs=f.g.jobs;f.g.jobs=(repo,r)=>r.path==='.github/workflows/wss-preflight.yml'?jobs(repo,r).map(j=>({...j,conclusion:'skipped'})):jobs(repo,r);}],
 ['replaced native artifact',f=>f.proofs[0].artifacts[0].id='9999'],
 ['expired native artifact',f=>{const get=f.g.get;f.g.get=path=>{const v=get(path);return path.includes('/actions/artifacts/')?{...v,expired:true}:v;};}]
])test(`${id}/${channel}: ${name} rejects after native without output`,async()=>{const f=fixture(id,channel);mutate(f);await assert.rejects(f.run(),e=>e.code==='WSS_RECEIPT_PROOF');assert.ok(existsSync(f.env.WSS_TEST_SENTINEL));assert.equal(existsSync(f.config.outputRoot),false);assert.equal(existsSync(f.env.GITHUB_OUTPUT),false);});
