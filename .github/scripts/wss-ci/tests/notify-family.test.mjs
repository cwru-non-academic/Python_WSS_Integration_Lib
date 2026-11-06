import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {prepareFamilyWakeup} from '../notify-family.mjs';
import {channelContext,targetForChannel} from '../channels.mjs';
const profiles=JSON.parse(readFileSync(new URL('../receipt-targets.json',import.meta.url))),targets=JSON.parse(readFileSync(new URL('../staging-targets.json',import.meta.url)));
const sha=n=>String(n).repeat(40),core='cwru-non-academic/WSSCore';
function fixture(family='python',channel='dev'){
  const contextPolicy=channelContext(channel),profile=profiles[family+'-wrapper'],t=targetForChannel(profile.target,channel),repo=t.repository;
  const candidate={repository:core,commit:sha(1),run_id:'1',artifact_id:'2',archive:'WSS-Universal-ci.zip',sha256:'a'.repeat(64)};
  const pr={number:3,merged:true,state:'closed',merged_at:'2026-01-01T00:00:00Z',merge_commit_sha:sha(2),user:{type:'Bot'},merged_by:{type:'User'},head:{repo:{full_name:repo}},base:{ref:channel,repo:{full_name:repo}}};
  const p={channel,candidate:structuredClone(candidate),manifest:{channel,excluded:[],targets:Object.values(profiles).map(p=>targetForChannel(p.target,channel))},target_snapshots:{[t.id]:{trusted:Object.fromEntries(t.trusted_paths.map(path=>[path,sha(4)]))}}};
  const stage={schema:contextPolicy.stageSchema,channel,application_fanout:'per-integration',libraries:[{id:family,...targets[family]}]};
  const run={id:4,repository:{full_name:repo},head_repository:{full_name:repo},head_sha:sha(2),head_branch:channel,path:t.workflow,event:'workflow_dispatch',created_at:'2026-01-01T00:01:00Z',status:'completed',conclusion:'success'};
  const context={repository:repo,eventName:'pull_request_target',event:{pull_request:{number:3}},sourceSha:channel==='main'?sha(2):sha(3),workflowRef:`${repo}/.github/workflows/notify-core-stage.yml@refs/heads/main`};
  const g={head:(r,b='dev')=>r===core?candidate.commit:channel==='main'?sha(2):b==='main'?sha(3):sha(2),object:()=>({sha:sha(4)}),pages:()=>[pr],get:path=>path.endsWith('/pulls/3')?pr:{type:'file',encoding:'base64',content:Buffer.from(JSON.stringify(path.includes(contextPolicy.stagePolicy)?stage:{candidate})).toString('base64')},run:r=>r===core?{repository:{full_name:core},head_repository:{full_name:core},path:'.github/workflows/artifacts.yml',event:'push',head_branch:channel,head_sha:candidate.commit,status:'completed',conclusion:'success'}:run};
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
