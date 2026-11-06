import {test} from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {runReceipt,readOnlyGh,targetPolicy} from '../receipt.mjs';
import {CORE,CORE_JOBS,digest,bytesDigest} from '../verify.mjs';
import {channelContext} from '../channels.mjs';
const sha=n=>String(n).repeat(40);

function fixture(channel='dev') {
  const context=channelContext(channel);
  const root=mkdtempSync(join(tmpdir(),'wss receipt '));
  const git=(...args)=>execFileSync('git',['-C',root,...args],{encoding:'utf8'}).trim();
  git('init');mkdirSync(join(root,'.github/scripts'),{recursive:true});writeFileSync(join(root,'.github/scripts/proof.ps1'),'# trusted adapter\n');writeFileSync(join(root,'.github/python-ci.json'),'{}\n');
  git('add','.');git('-c','user.name=CI','-c','user.email=ci@example.invalid','commit','-m','fixture');
  const head=git('rev-parse','HEAD'),scripts=git('rev-parse','HEAD:.github/scripts'),config=git('rev-parse','HEAD:.github/python-ci.json');
  const manifest=JSON.parse(readFileSync(resolve(process.env.WSS_CORE_REFERENCE||'.ci-reference/Core',`tools/release/targets.${channel}.json`)));
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
