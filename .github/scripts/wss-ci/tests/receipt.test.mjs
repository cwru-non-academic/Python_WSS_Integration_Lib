import {test,after} from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync,existsSync} from 'node:fs';
import {join,resolve,dirname} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {tmpdir} from 'node:os';
// Generate the registered flat receiver closure, never patch managed copies in
// the owning repository. Core is the reviewed candidate; integration source is
// this committed candidate. This tests the real cross-origin import boundary.
const coreRoot=resolve(process.env.WSS_CORE_REFERENCE||'.ci-reference/Core');
const integrationRoot=resolve(dirname(fileURLToPath(import.meta.url)),'../../../..');
const closure=mkdtempSync(join(tmpdir(),'wss receipt closure '));
after(()=>rmSync(closure,{recursive:true,force:true}));
const sync=JSON.parse(execFileSync('git',['-C',coreRoot,'show','HEAD:tools/ci/sync-tooling.json'],{encoding:'utf8'}));
for(const [destination,entry] of Object.entries(sync.files)) {
  if(entry.repositories&&!entry.repositories.includes('Python_WSS_Integration_Lib'))continue;
  assert.ok(['core','integration'].includes(entry.origin),'Unrecognized closure origin');
  const source=entry.origin==='core'?coreRoot:integrationRoot;
  const bytes=execFileSync('git',['-C',source,'show',`HEAD:${entry.path}`]);
  const output=join(closure,destination);mkdirSync(dirname(output),{recursive:true});writeFileSync(output,bytes);
}
const module=name=>pathToFileURL(join(closure,'.github/scripts/wss-ci',name)).href;
const {runReceipt,readOnlyGh,targetPolicy}=await import(module('receipt.mjs'));
const {CORE,CORE_JOBS,digest,bytesDigest}=await import(module('verify.mjs'));
const {channelContext}=await import(module('channels.mjs'));
const {resolveTestSelection}=await import(module('test-selection-contract.mjs'));
const {CAMPAIGN_TEST_POLICY,selectionRequest,selectionFields,targetTestEvidence,selectedTestArtifactName}=await import(module('campaign-test-selection.mjs'));
const sha=n=>String(n).repeat(40);

function fixture(channel='dev') {
  const context=channelContext(channel);
  const root=mkdtempSync(join(tmpdir(),'wss receipt '));
  const git=(...args)=>execFileSync('git',['-C',root,...args],{encoding:'utf8'}).trim();
  git('init');mkdirSync(join(root,'.github/scripts'),{recursive:true});writeFileSync(join(root,'.github/scripts/proof.ps1'),'# trusted adapter\n');writeFileSync(join(root,'.github/python-ci.json'),'{}\n');
  git('add','.');git('-c','user.name=CI','-c','user.email=ci@example.invalid','commit','-m','fixture');
  const head=git('rev-parse','HEAD'),scripts=git('rev-parse','HEAD:.github/scripts'),config=git('rev-parse','HEAD:.github/python-ci.json');
  const manifest=JSON.parse(execFileSync('git',['-C',coreRoot,'show',`HEAD:tools/release/targets.${channel}.json`],{encoding:'utf8'}));
  const id='python-wrapper',t=manifest.targets.find(t=>t.id===id);
  const zip=Buffer.from('canonical archive'),candidate={repository:CORE,commit:sha(1),run_id:'1',artifact_id:'2',archive:'WSS-Universal-ci.zip',sha256:bytesDigest(zip)};
  const body={schema:context.planSchema,channel,candidate,manifest,manifest_sha256:digest(manifest),target_snapshots:Object.fromEntries(manifest.targets.map(target=>[target.id,{head_sha:sha(2),trusted:Object.fromEntries(target.trusted_paths.map(path=>[path,target.id===id&&path==='.github/scripts'?scripts:target.id===id&&path==='.github/python-ci.json'?config:sha(3)]))}]))};
  if(channel==='main')body.workflow_snapshots={schema:'wss-workflow-snapshots/v2',targets:Object.fromEntries(manifest.targets.flatMap(target=>{
    const row=role=>[`${target.id}:${role}`,{repository:target.repository,branch:role==='counterpart'?'dev':'main',role,source_sha:role==='counterpart'?sha(6):sha(2),tree_sha:sha(3)}];
    return [row('accepted-baseline'),...(target.kind==='payload'?[row('execution-authority'),row('counterpart')]:[])];
  }))};
  const p={...body,plan_id:digest(body)};
  const pr={number:10,merged:true,state:'closed',merge_commit_sha:head,merged_at:'2026-11-01T00:00:00Z',user:{type:'Bot'},merged_by:{type:'User'},base:{ref:channel,repo:{full_name:t.repository}},head:{sha:sha(4),ref:`automation/python-wss-1-${candidate.sha256}`,repo:{full_name:t.repository}}};
  const identity={repository:{full_name:t.repository},head_repository:{full_name:t.repository},head_sha:head,head_branch:channel,run_attempt:1};
  const normal={...identity,id:20,path:t.workflow,event:'push',status:'completed',conclusion:'success',created_at:'2026-11-01T00:01:00Z'};
  const proofs=[30,31,32].map(run=>({repository:t.repository,run_id:String(run),source_sha:sha(5),workflow:'.github/workflows/wss-preflight.yml'}));
  const producer={id:1,repository:{full_name:CORE},head_repository:{full_name:CORE},head_sha:sha(1),head_branch:channel,path:'.github/workflows/artifacts.yml',event:'push',status:'completed',conclusion:'success',run_attempt:1};
  const artifact={id:2,name:'universal-release-assets',expired:false,workflow_run:{id:1,head_sha:sha(1)}};
  const state={moved:false,rerun:false,normal:[normal],proofs};
  const g={
    head:(repo,branch)=>{assert.equal(branch,channel,'Every authoritative head lookup binds the target channel');return repo===CORE?sha(1):(state.moved?sha(9):head);},
    get:path=>path.includes('/contents/')?{encoding:'base64',content:Buffer.from(JSON.stringify(manifest)).toString('base64')}:pr,
    run:(repo,id)=>String(id)==='1'?producer:String(id)==='99'?{...identity,id:99,event:'workflow_dispatch',path:'.github/workflows/release-receipt.yml'}:String(id)==='20'?{...normal,run_attempt:state.rerun?2:1}:{...identity,id:Number(id),head_sha:sha(5),event:'workflow_dispatch',path:'.github/workflows/wss-preflight.yml',status:'completed',conclusion:'success'},
    pages:path=>path.includes('/commits/')?[pr]:state.normal,
    object:(repo,ref,path)=>({sha:p.target_snapshots[id].trusted[path]}),
    jobs:(repo,r)=>(repo===CORE?CORE_JOBS:t.jobs).map(name=>({name,status:'completed',conclusion:'success'})),
    artifact:()=>artifact,
    tree:()=>sha(6),
    download:(repo,id,name)=>name==='wss-propagation-plan'?{'plan.json':Buffer.from(JSON.stringify(p))}:name==='universal-release-assets'?{[candidate.archive]:zip,'SHA256SUMS.txt':Buffer.from(`${candidate.sha256}  ${candidate.archive}\n`)}:{'candidate.json':Buffer.from(JSON.stringify(candidate))}
  };
  const env={GITHUB_ACTIONS:'true',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REF:context.ref,GITHUB_SHA:head,GITHUB_REPOSITORY:t.repository,GITHUB_RUN_ID:'99',GITHUB_RUN_ATTEMPT:'1',TARGET_ID:id,PRODUCER_RUN_ID:'1',PLAN_ID:p.plan_id,...(channel==='main'?{WSS_CI_CHANNEL:'main',GITHUB_WORKFLOW_SHA:head,GITHUB_WORKFLOW_REF:`${t.repository}/.github/workflows/release-receipt.yml@refs/heads/main`}:{})};
  return {root,g,env,p,t,state,producer,pr,identity,config:{sourceRoot:root,toolsRoot:root,outputRoot:join(root,'output')},dispose:()=>rmSync(root,{recursive:true,force:true})};
}

test('common receipt emits canonical six-field candidate and complete adapter proof',async()=>{
  const f=fixture();try {
    const receipt=await runReceipt(f.config,{g:f.g,env:f.env,adapter:()=>f.state.proofs});
    assert.deepEqual(receipt.candidate,f.p.candidate);assert.equal(Object.keys(receipt.candidate).length,6);
    assert.deepEqual(receipt.preflights,f.state.proofs);assert.equal(receipt.normal_ci.run_id,'20');
    assert.deepEqual(JSON.parse(readFileSync(join(f.root,'output/receipt.json'),'utf8')),receipt);
  } finally {f.dispose();}
});
for(const [name,mutate,pattern] of [
  ['ambiguous successful CI',f=>f.state.normal.push({...f.state.normal[0],id:21}),/Ambiguous/],
  ['missing rich proof',f=>f.state.proofs.pop(),/Missing rich/],
  ['late source movement',f=>f.state.moved=true,/Source moved/],
  ['late normal rerun',f=>f.state.rerun=true,/run\/attempt changed/]
]) test(`common receipt rejects ${name}`,async()=>{
  const f=fixture();try {
    if(name==='ambiguous successful CI') mutate(f);
    await assert.rejects(()=>runReceipt(f.config,{g:f.g,env:f.env,adapter:()=>{if(name!=='ambiguous successful CI')mutate(f);return f.state.proofs;}}),pattern);
  } finally {f.dispose();}
});
test('receipt capability and target metadata cannot authorize publication or weaker checks',()=>{
  for(const args of [['api','--method','POST',`repos/${CORE}/dispatches`],['workflow','run','promote.yml']]) assert.throws(()=>readOnlyGh(args));
  const f=fixture();try {f.p.manifest.targets.find(t=>t.id==='python-wrapper').jobs.pop();assert.throws(()=>targetPolicy(f.p,'python-wrapper'),/Frozen target differs/);}finally{f.dispose();}
});
test('the same receipt engine accepts exact main proof with v2 identity',async()=>{
  const f=fixture('main');try{
    const r=await runReceipt(f.config,{g:f.g,env:f.env,adapter:()=>f.state.proofs});
    assert.equal(r.channel,'main');assert.equal(r.schema,'wss-acceptance-receipt/v2');assert.deepEqual(r.candidate,f.p.candidate);
  }finally{f.dispose();}
});
for(const [name,mutate]of [
  ['target ref',f=>f.env.GITHUB_REF='refs/heads/dev'],['event',f=>f.env.GITHUB_EVENT_NAME='pull_request'],
  ['source',f=>f.env.GITHUB_SHA=sha(9)],['repository',f=>f.env.GITHUB_REPOSITORY=CORE],
  ['workflow source',f=>f.env.GITHUB_WORKFLOW_SHA=sha(9)],['workflow ref',f=>f.env.GITHUB_WORKFLOW_REF=`${f.t.repository}/.github/workflows/other.yml@refs/heads/main`],
  ['context channel',f=>f.env.WSS_CI_CHANNEL='dev'],['producer channel',f=>f.producer.head_branch='dev'],
  ['merge channel',f=>f.pr.base.ref='dev'],['normal channel',f=>f.state.normal[0].head_branch='dev'],
  ['preflight channel',f=>{const run=f.g.run;f.g.run=(repo,id)=>['30','31','32'].includes(String(id))?{...run(repo,id),head_branch:'dev'}:run(repo,id);}]
])test(`canonical main plan cannot replace receiver ${name} identity`,async()=>{
  const f=fixture('main');try{mutate(f);await assert.rejects(runReceipt(f.config,{g:f.g,env:f.env,adapter:()=>f.state.proofs}));}
  finally{f.dispose();}
});

function selectedFixture(channel='dev') {
  const f=fixture(channel),m=f.p.manifest;
  m.test_selection_policy={schema:CAMPAIGN_TEST_POLICY,targets:m.targets.map(t=>({id:t.id,repository:t.repository,default_test_repository:'cwru-non-academic/TestBundle',allowed_test_repositories:['cwru-non-academic/TestBundle']}))};
  const selection=resolveTestSelection(selectionRequest(m,f.p.candidate),{head:()=>sha(7)});
  Object.assign(f.p,selectionFields(m,f.p.candidate,selection));f.p.manifest_sha256=digest(m);
  const {plan_id,...body}=f.p;f.p.plan_id=digest(body);f.env.PLAN_ID=f.p.plan_id;
  const originalRun=f.g.run,originalArtifact=f.g.artifact,originalDownload=f.g.download;
  f.state.proofs.forEach(d=>d.source_sha=sha(2));
  f.g.run=(repo,id)=>{const r=originalRun(repo,id);return ['30','31','32'].includes(String(id))?{...r,head_sha:sha(2)}:r;};
  f.state.selected=new Map();
  for(const id of ['20','30','31','32']) {
    const r=f.g.run(f.t.repository,id);
    f.state.selected.set(id,{artifact:{id:100+Number(id),name:selectedTestArtifactName(f.t.id,r.run_attempt),expired:false,workflow_run:{id:r.id,head_sha:r.head_sha}},bytes:Buffer.from(JSON.stringify(targetTestEvidence(f.p,f.t.id)))});
  }
  f.g.artifact=(repo,id,name)=>name.startsWith('wss-selected-tests-')?f.state.selected.get(String(id))?.artifact:originalArtifact(repo,id,name);
  f.g.download=(repo,id,name,files)=>name.startsWith('wss-selected-tests-')?{'evidence.json':f.state.selected.get(String(id))?.bytes}:originalDownload(repo,id,name,files);
  return f;
}
for(const channel of ['dev','main'])test(`${channel} selected receipt declares only independently authenticated normal evidence`,async()=>{
  const f=selectedFixture(channel);try {
    const receipt=await runReceipt(f.config,{g:f.g,env:{...f.env,SELECTION_ID:'forged'},adapter:()=>f.state.proofs});
    assert.deepEqual(receipt.selected_tests,targetTestEvidence(f.p,f.t.id));
    assert.deepEqual(JSON.parse(readFileSync(join(f.config.outputRoot,'receipt.json'),'utf8')),receipt);
  } finally {f.dispose();}
});
for(const phase of ['normal','preflight'])for(const [name,mutate] of Object.entries({
  'missing artifact':proof=>proof.artifact=undefined,
  'expired artifact':proof=>proof.artifact.expired=true,
  'foreign artifact run':proof=>proof.artifact.workflow_run.id=900,
  'foreign artifact head':proof=>proof.artifact.workflow_run.head_sha=sha(8),
  'stale artifact attempt':proof=>proof.artifact.name=proof.artifact.name.replace('-a1','-a2'),
  'foreign artifact target':proof=>proof.artifact.name=proof.artifact.name.replace('python-wrapper','python-cli'),
  'missing bytes':proof=>proof.bytes=undefined,
  'malformed bytes':proof=>proof.bytes=Buffer.from('{'),
  'wrong selection digest':proof=>{const e=JSON.parse(proof.bytes);e.selection_id='b'.repeat(64);proof.bytes=Buffer.from(JSON.stringify(e));},
  'wrong selected source':proof=>{const e=JSON.parse(proof.bytes);e.test_commit=sha(8);proof.bytes=Buffer.from(JSON.stringify(e));},
  'wrong selected repository':proof=>{const e=JSON.parse(proof.bytes);e.test_repository='untrusted/tests';proof.bytes=Buffer.from(JSON.stringify(e));},
  'extra self-attested fields':proof=>{const e=JSON.parse(proof.bytes);e.passed=true;proof.bytes=Buffer.from(JSON.stringify(e));}
}))test(`selected receipt rejects ${phase} ${name} before output`,async()=>{
  const f=selectedFixture();try {
    mutate(f.state.selected.get(phase==='normal'?'20':'30'));
    await assert.rejects(runReceipt(f.config,{g:f.g,env:f.env,adapter:()=>f.state.proofs}));
    assert.equal(existsSync(join(f.config.outputRoot,'receipt.json')),false);
  } finally {f.dispose();}
});
for(const [name,mutate] of Object.entries({
  'unknown preflight repository':f=>f.state.proofs[0].repository='untrusted/repository',
  'wrong frozen preflight source':f=>f.state.proofs[0].source_sha=sha(8),
  'preflight run ID mismatch':f=>{const run=f.g.run;f.g.run=(repo,id)=>String(id)==='30'?{...run(repo,id),id:99}:run(repo,id);},
  'artifact transport failure':f=>f.g.artifact=()=>{throw Error('403 denied');},
  'plan selection digest mismatch':f=>{f.p.test_selection_id='b'.repeat(64);const {plan_id,...body}=f.p;f.p.plan_id=digest(body);f.env.PLAN_ID=f.p.plan_id;}
}))test(`selected receipt rejects ${name} without trusting adapter output`,async()=>{
  const f=selectedFixture();try {
    mutate(f);await assert.rejects(runReceipt(f.config,{g:f.g,env:f.env,adapter:()=>f.state.proofs}));
    assert.equal(existsSync(join(f.config.outputRoot,'receipt.json')),false);
  } finally {f.dispose();}
});

test('registered candidate closure imports all shared receiver engines without source-checkout fallbacks',async()=>{
  for(const name of ['channels.mjs','verify.mjs','github.mjs','receipt.mjs','promotion.mjs','staging.mjs','preflight.mjs','campaign-test-selection.mjs','test-selection-contract.mjs'])await import(module(name));
});
