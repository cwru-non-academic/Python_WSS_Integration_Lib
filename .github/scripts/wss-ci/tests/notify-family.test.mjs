import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {prepareFamilyWakeup} from '../notify-family.mjs';
const profiles=JSON.parse(readFileSync(new URL('../receipt-targets.json',import.meta.url))),targets=JSON.parse(readFileSync(new URL('../staging-targets.json',import.meta.url)));
const sha=n=>String(n).repeat(40),core='cwru-non-academic/WSSCore';
function fixture(family='python'){
  const profile=profiles[family+'-wrapper'],t=profile.target,repo=t.repository;
  const candidate={repository:core,commit:sha(1),run_id:'1',artifact_id:'2',archive:'WSS-Universal-ci.zip',sha256:'a'.repeat(64)};
  const pr={number:3,merged:true,state:'closed',merged_at:'2026-01-01T00:00:00Z',merge_commit_sha:sha(2),user:{type:'Bot'},merged_by:{type:'User'},head:{repo:{full_name:repo}},base:{ref:'dev',repo:{full_name:repo}}};
  const p={candidate:structuredClone(candidate),manifest:{targets:Object.values(profiles).map(p=>p.target)},target_snapshots:{[t.id]:{trusted:Object.fromEntries(t.trusted_paths.map(path=>[path,sha(4)]))}}};
  const stage={schema:'wss-dev-stage/v1',application_fanout:'per-integration',libraries:[{id:family,...targets[family]}]};
  const run={id:4,repository:{full_name:repo},head_repository:{full_name:repo},head_sha:sha(2),head_branch:'dev',path:t.workflow,event:'workflow_dispatch',created_at:'2026-01-01T00:01:00Z',status:'completed',conclusion:'success'};
  const context={repository:repo,eventName:'pull_request_target',event:{pull_request:{number:3}},sourceSha:sha(2),workflowRef:`${repo}/.github/workflows/notify-core-stage.yml@refs/heads/dev`};
  const g={head:(r,b='dev')=>r===core?candidate.commit:b==='main'?sha(3):sha(2),object:()=>({sha:sha(4)}),pages:()=>[pr],get:path=>path.endsWith('/pulls/3')?pr:{type:'file',encoding:'base64',content:Buffer.from(JSON.stringify(path.includes('dev-propagation.json')?stage:{candidate})).toString('base64')},run:r=>r===core?{repository:{full_name:core},head_repository:{full_name:core},path:'.github/workflows/artifacts.yml',event:'push',head_branch:'dev',head_sha:candidate.commit,status:'completed',conclusion:'success'}:run};
  return {g,context,pr,p,stage,run,loadFrozenPlan:()=>p};
}
for(const family of Object.keys(targets))test(`${family} uses one wake-up implementation after its own actual merge`,()=>{const f=fixture(family);assert.equal(prepareFamilyWakeup(f.g,f.context,f).needed,true);});
test('successful postmerge completion wakes its family from trusted main',()=>{const f=fixture();f.context={...f.context,eventName:'workflow_run',event:{workflow_run:{id:4}},sourceSha:sha(3),workflowRef:f.context.workflowRef.replace('/dev','/main')};assert.equal(prepareFamilyWakeup(f.g,f.context,f).needed,true);f.run.conclusion='failure';assert.throws(()=>prepareFamilyWakeup(f.g,f.context,f),/successful committed/);});
test('unmerged, foreign, stale or bot-merged changes cannot request coordinator credentials',()=>{
  for(const mutate of [f=>f.pr.merged=false,f=>f.pr.merged_by.type='Bot',f=>f.pr.head.repo.full_name='other/repo',f=>f.p.candidate.commit=sha(9),f=>f.g.object=()=>({sha:sha(8)}),f=>f.context.workflowRef='untrusted']){const f=fixture();mutate(f);assert.throws(()=>prepareFamilyWakeup(f.g,f.context,f));}
});
test('an older frozen all-integration policy is not silently changed by a notifier',()=>{const f=fixture();delete f.stage.application_fanout;assert.equal(prepareFamilyWakeup(f.g,f.context,f).needed,false);});
