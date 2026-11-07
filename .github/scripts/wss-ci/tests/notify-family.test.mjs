import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {digest} from '../verify.mjs';
import {prepareFamilyWakeup} from '../notify-family.mjs';
import {channelContext,targetForChannel} from '../channels.mjs';
const profiles=JSON.parse(readFileSync(new URL('../receipt-targets.json',import.meta.url))),targets=JSON.parse(readFileSync(new URL('../staging-targets.json',import.meta.url)));
const sha=n=>String(n).repeat(40),core='cwru-non-academic/WSSCore';
function fixture(family='python',channel='dev'){
  const contextPolicy=channelContext(channel),profile=profiles[family+'-wrapper'],t=targetForChannel(profile.target,channel),repo=t.repository;
  const candidate={repository:core,commit:sha(1),run_id:'1',artifact_id:'2',archive:'WSS-Universal-ci.zip',sha256:'a'.repeat(64)};
  const pr={number:3,merged:true,state:'closed',merged_at:'2026-01-01T00:00:00Z',merge_commit_sha:sha(2),user:{type:'Bot'},merged_by:{type:'User'},head:{repo:{full_name:repo}},base:{ref:channel,repo:{full_name:repo}}};
  const p={schema:contextPolicy.planSchema,channel,candidate:structuredClone(candidate),manifest:{schema:contextPolicy.manifestSchema,release_kind:contextPolicy.kind,stable_enabled:channel==='main',channel,excluded:[],targets:Object.values(profiles).map(p=>targetForChannel(p.target,channel))},target_snapshots:{[t.id]:{trusted:Object.fromEntries(t.trusted_paths.map(path=>[path,sha(4)]))}}};
  p.manifest.workflow_snapshot_policy=channel==='main'?'wss-workflow-snapshots/v2':'wss-workflow-snapshots/v1';
  p.target_snapshots=Object.fromEntries(p.manifest.targets.map(t=>[t.id,{head_sha:sha(5),trusted:Object.fromEntries(t.trusted_paths.map(path=>[path,sha(4)]))}]));
  p.workflow_snapshots={schema:p.manifest.workflow_snapshot_policy,targets:{[t.id+(channel==='main'?':execution-authority':':main')]:{repository:repo,branch:'main',source_sha:sha(5),tree_sha:sha(4),...(channel==='main'?{role:'execution-authority'}:{})}}};
  p.manifest_sha256=digest(p.manifest);p.plan_id=digest(p);
  const stage={schema:contextPolicy.stageSchema,channel,application_fanout:'per-integration',libraries:[{id:family,...targets[family]}]};
  const run={id:4,repository:{full_name:repo},head_repository:{full_name:repo},head_sha:sha(2),head_branch:channel,path:t.workflow,event:'workflow_dispatch',created_at:'2026-01-01T00:01:00Z',status:'completed',conclusion:'success'};
  const context={repository:repo,eventName:'pull_request_target',event:{pull_request:{number:3}},sourceSha:channel==='main'?sha(2):sha(3),workflowRef:`${repo}/.github/workflows/notify-core-stage.yml@refs/heads/main`};
  const g={head:(r,b='dev')=>r===core?candidate.commit:channel==='main'?sha(2):b==='main'?sha(3):sha(2),object:()=>({type:'tree',sha:sha(4)}),pages:()=>[pr],get:path=>path.endsWith('/pulls/3')?pr:{type:'file',encoding:'base64',content:Buffer.from(JSON.stringify(path.includes(contextPolicy.stagePolicy)?stage:{candidate})).toString('base64')},run:r=>r===core?{repository:{full_name:core},head_repository:{full_name:core},path:'.github/workflows/artifacts.yml',event:'push',head_branch:channel,head_sha:candidate.commit,status:'completed',conclusion:'success'}:run};
  const authorizations=[];
  return {g,context,pr,p,stage,run,loadFrozenPlan:()=>p,authorize:c=>authorizations.push(c),authorizations,env:{GITHUB_WORKSPACE:'/fixture',GITHUB_REPOSITORY:repo}};
}
for(const family of Object.keys(targets))test(`${family} uses one wake-up implementation after its own actual merge`,()=>{const f=fixture(family);assert.equal(prepareFamilyWakeup(f.g,f.context,f).needed,true);});

test('merge notification executes frozen main code and independently validates the merged dev payload',()=>{
  const f=fixture();assert.notEqual(f.context.sourceSha,f.pr.merge_commit_sha);
  assert.equal(prepareFamilyWakeup(f.g,f.context,f).needed,true);
  for(const mutate of [x=>x.context.sourceSha=x.pr.merge_commit_sha,x=>x.context.workflowRef=x.context.workflowRef.replace('/main','/dev'),x=>x.context.sourceSha=sha(9)]){
    const invalid=fixture();mutate(invalid);assert.throws(()=>prepareFamilyWakeup(invalid.g,invalid.context,invalid),/current trusted main/);
  }
});
test('successful postmerge completion wakes its family from trusted main',()=>{const f=fixture();f.context={...f.context,eventName:'workflow_run',event:{workflow_run:{id:4}},sourceSha:sha(3),workflowRef:f.context.workflowRef.replace('/dev','/main')};assert.equal(prepareFamilyWakeup(f.g,f.context,f).needed,true);f.run.conclusion='failure';assert.throws(()=>prepareFamilyWakeup(f.g,f.context,f),/successful committed/);});
test('ordinary source CI does not request coordinator credentials',()=>{const f=fixture();f.context={...f.context,eventName:'workflow_run',event:{workflow_run:{id:4}},sourceSha:sha(3),workflowRef:f.context.workflowRef.replace('/dev','/main')};f.pr.user.type='User';assert.equal(prepareFamilyWakeup(f.g,f.context,f).needed,false);});
test('unmerged, foreign, stale or bot-merged changes cannot request coordinator credentials',()=>{
  for(const mutate of [f=>f.pr.merged=false,f=>f.pr.merged_by.type='Bot',f=>f.pr.head.repo.full_name='other/repo',f=>f.p.candidate.commit=sha(9),f=>f.g.object=()=>({sha:sha(8)}),f=>f.context.workflowRef='untrusted']){const f=fixture();mutate(f);assert.throws(()=>prepareFamilyWakeup(f.g,f.context,f));}
});
test('an older frozen all-integration policy is not silently changed by a notifier',()=>{const f=fixture();delete f.stage.application_fanout;assert.equal(prepareFamilyWakeup(f.g,f.context,f).needed,false);});
for(const family of Object.keys(targets))test(`${family}: main wake uses accepted M and canonical Core guard, never old S`,()=>{
  const f=fixture(family,'main'),result=prepareFamilyWakeup(f.g,f.context,f);
  assert.equal(result.needed,true);assert.equal(result.channel,'main');assert.equal(f.authorizations.length,1);
  f.context.sourceSha=sha(3);assert.throws(()=>prepareFamilyWakeup(f.g,f.context,f),/current trusted main/);
});

function rehash(f){f.p.manifest_sha256=digest(f.p.manifest);const {plan_id,...body}=f.p;f.p.plan_id=digest(body);}
function authority(f){return f.p.workflow_snapshots.targets[Object.keys(f.p.workflow_snapshots.targets)[0]];}
function distinct(f){
  const base=f.g.object,target=f.p.manifest.targets.find(t=>t.repository===f.context.repository),differentPath=target.trusted_paths.includes('ci')?'ci':'.github/scripts';
  f.g.object=(repo,ref,path)=>path===differentPath?{type:'tree',sha:ref===f.pr.merge_commit_sha?sha(4):sha(6)}:base(repo,ref,path);
  return f;
}
for(const family of Object.keys(targets))test(`${family}: distinct accepted DEV and frozen MAIN trees are valid`,()=>{
  const f=distinct(fixture(family)),path=family==='matlab'?'ci':'.github/scripts';assert.notEqual(f.g.object(f.context.repository,f.pr.merge_commit_sha,path).sha,f.g.object(f.context.repository,f.context.sourceSha,path).sha);assert.equal(prepareFamilyWakeup(f.g,f.context,f).needed,true);
});
for(const [label,change] of [
  ['MAIN source drift',f=>{const base=f.g.object;f.g.object=(r,ref,path)=>ref===f.context.sourceSha&&path==='.github/scripts'?{type:'tree',sha:sha(9)}:base(r,ref,path);}],
  ['accepted channel drift',f=>{const base=f.g.object;f.g.object=(r,ref,path)=>ref===f.pr.merge_commit_sha&&path==='.github/scripts'?{type:'tree',sha:sha(9)}:base(r,ref,path);}],
  ['MAIN full workflow drift',f=>{const base=f.g.object;f.g.object=(r,ref,path)=>ref===f.context.sourceSha&&path==='.github/workflows'?{type:'tree',sha:sha(9)}:base(r,ref,path);}],
  ['frozen source workflow mismatch',f=>authority(f).tree_sha=sha(9)],
  ['missing snapshot',f=>delete f.p.workflow_snapshots],
  ['unknown snapshot schema',f=>f.p.workflow_snapshots.schema='unknown'],
  ['missing producer requirement',f=>delete f.p.manifest.workflow_snapshot_policy],
  ['unknown producer requirement',f=>f.p.manifest.workflow_snapshot_policy='unknown'],
  ['foreign repository',f=>authority(f).repository='other/repo'],
  ['wrong authority branch',f=>authority(f).branch='dev'],
  ['malformed source SHA',f=>authority(f).source_sha='main'],
  ['malformed tree SHA',f=>authority(f).tree_sha='wrong'],
  ['extra authority field',f=>authority(f).trusted={}],
  ['wrong target authority',f=>{f.p.workflow_snapshots.targets['other:main']=authority(f);delete f.p.workflow_snapshots.targets['matlab-wrapper:main'];}],
  ['invalid object SHA',f=>f.g.object=()=>({type:'tree',sha:'wrong'})],
  ['invalid object type',f=>f.g.object=()=>({type:'commit',sha:sha(4)})],
  ['missing object',f=>f.g.object=()=>null],
  ['current Core source moved',f=>{const base=f.g.head;f.g.head=(r,b)=>r===core?sha(9):base(r,b);}],
  ['candidate mismatch',f=>f.p.candidate.artifact_id='99'],
])test(`rejects ${label}`,()=>{const f=distinct(fixture('matlab'));change(f);rehash(f);assert.throws(()=>prepareFamilyWakeup(f.g,f.context,f));});
test('rejects snapshot edit without a matching envelope digest',()=>{const f=fixture();authority(f).source_sha=sha(8);assert.throws(()=>prepareFamilyWakeup(f.g,f.context,f),/Plan ID mismatch/);});
test('MAIN execution authority must match accepted baseline source',()=>{const f=fixture('matlab','main');authority(f).source_sha=sha(8);rehash(f);assert.throws(()=>prepareFamilyWakeup(f.g,f.context,f),/Invalid frozen/);});
test('equal SHA with changed object type is not MAIN authority',()=>{const f=fixture();const base=f.g.object;f.g.object=(r,ref,path)=>ref===f.context.sourceSha&&path==='.github/scripts'?{type:'blob',sha:sha(4)}:base(r,ref,path);assert.throws(()=>prepareFamilyWakeup(f.g,f.context,f),/frozen MAIN authority/);});
function authenticatedFixture(){
  const f=distinct(fixture('matlab')),get=f.g.get,context=channelContext('dev');
  f.g.download=(repo,id,name,files)=>{assert.equal(repo,core);assert.equal(id,'1');assert.equal(name,'wss-propagation-plan');assert.deepEqual(files,['plan.json']);return {'plan.json':Buffer.from(JSON.stringify(f.p))};};
  f.reviewed=structuredClone(f.p.manifest);
  f.g.get=path=>path===`repos/${core}/contents/${context.targetPolicy}?ref=${f.p.candidate.commit}`?{type:'file',encoding:'base64',content:Buffer.from(JSON.stringify(f.reviewed)).toString('base64')}:get(path);
  delete f.loadFrozenPlan;return f;
}
test('production loader authenticates distinct channel authority from producer artifact and immutable policy',()=>{const f=authenticatedFixture();assert.equal(prepareFamilyWakeup(f.g,f.context,f).needed,true);});
for(const [label,change] of [
  ['rehashed unreviewed policy',f=>{f.p.manifest.workflow_snapshot_policy='unknown';rehash(f);}],
  ['foreign producer repository',f=>{const base=f.g.run;f.g.run=r=>r===core?{...base(r),repository:{full_name:'other/repo'}}:base(r);}],
  ['wrong producer source',f=>{const base=f.g.run;f.g.run=r=>r===core?{...base(r),head_sha:sha(9)}:base(r);}],
  ['wrong producer run binding',f=>{f.p.candidate.run_id='99';rehash(f);}],
  ['unsuccessful producer',f=>{const base=f.g.run;f.g.run=r=>r===core?{...base(r),conclusion:'failure'}:base(r);}],
])test(`production loader rejects ${label}`,()=>{const f=authenticatedFixture();change(f);assert.throws(()=>prepareFamilyWakeup(f.g,f.context,f));});
