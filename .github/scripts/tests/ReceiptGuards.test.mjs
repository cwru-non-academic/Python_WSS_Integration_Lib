import test from 'node:test';
import assert from 'node:assert/strict';
import {TARGETS,RECEIPT_WORKFLOW,WRAPPER,readOnlyGh,targetPolicy,normalRun,mergedPr,emitter,changedHead} from '../ReceiptGuards.mjs';
const target={id:'python-cli',...TARGETS['python-cli'],branch:'dev'};
const candidate={run_id:'1',sha256:'d'.repeat(64)};
const pr={number:10,merged:true,state:'closed',merge_commit_sha:'a'.repeat(40),merged_at:'2026-10-29T00:01:00Z',merged_by:{type:'User'},user:{type:'Bot'},
  base:{ref:'dev',repo:{full_name:target.repository}},head:{sha:'b'.repeat(40),ref:`automation/python-wss-1-${candidate.sha256}`,repo:{full_name:target.repository}}};
const run={id:100,status:'completed',conclusion:'success',event:'push',path:target.workflow,head_sha:pr.merge_commit_sha,head_branch:'dev',
  repository:{full_name:target.repository},head_repository:{full_name:target.repository},created_at:'2026-10-29T00:02:00Z',run_attempt:1};
test('receipt transport cannot dispatch, publish or write through gh',()=>{
  readOnlyGh(['api',`repos/${WRAPPER}/actions/runs/1`]);
  readOnlyGh(['run','download','1','--repo',WRAPPER,'--name','wss-propagation-plan','--dir','temporary']);
  for(const args of [['api','--method','POST',`repos/${WRAPPER}/dispatches`],['workflow','run','promote-wss.yml'],['release','create','tag'],['api','repos/unrelated/repo']]) assert.throws(()=>readOnlyGh(args));
});
test('required checks, parent pins and coverage cannot be relaxed by plan metadata',()=>{
  for(const id of Object.keys(TARGETS)) {
    const t={id,...structuredClone(TARGETS[id]),branch:'dev'};
    assert.equal(targetPolicy({manifest:{targets:[t]}},id).role,TARGETS[id].role);
    t.jobs.pop();assert.throws(()=>targetPolicy({manifest:{targets:[t]}},id));
  }
});
test('normal proof is actual postmerge CI and latest failure blocks older success',()=>{
  assert.equal(normalRun([run],target,pr).id,100);
  assert.throws(()=>normalRun([run,{...run,id:101,conclusion:'failure'}],target,pr));
  for(const change of [{event:'pull_request'},{head_sha:'f'.repeat(40)},{head_branch:'main'},{created_at:'2026-10-29T00:00:00Z'},{status:'in_progress'},{head_repository:{full_name:'unrelated/fork'}}]) assert.throws(()=>normalRun([{...run,...change}],target,pr));
});
test('only the exact human merged bot dependency PR can be accepted',()=>{
  mergedPr(pr,target,pr.merge_commit_sha,candidate);
  for(const change of [{merged:false},{state:'open'},{merge_commit_sha:'f'.repeat(40)},{merged_by:{type:'Bot'}},{user:{type:'User'}},{base:{...pr.base,ref:'main'}},{head:{...pr.head,ref:'unrelated'}}]) assert.throws(()=>mergedPr({...pr,...change},target,pr.merge_commit_sha,candidate));
});
test('emitter is read-only reconciliation at exact actual merge, never PR/fork source',()=>{
  const env={GITHUB_ACTIONS:'true',GITHUB_REPOSITORY:target.repository,GITHUB_REF:'refs/heads/dev',GITHUB_SHA:pr.merge_commit_sha,GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_RUN_ID:'100',GITHUB_RUN_ATTEMPT:'1'};
  const r={...run,path:RECEIPT_WORKFLOW,event:'workflow_dispatch'};
  emitter(r,env,target,pr.merge_commit_sha);
  for(const change of [{GITHUB_SHA:'f'.repeat(40)},{GITHUB_REF:'refs/heads/main'},{GITHUB_EVENT_NAME:'pull_request'},{GITHUB_RUN_ATTEMPT:'2'}]) assert.throws(()=>emitter(r,{...env,...change},target,pr.merge_commit_sha));
});
test('preparation/no-op state cannot manufacture a merged-pr acceptance',()=>{
  changedHead('a'.repeat(40),{head_sha:'b'.repeat(40)});
  assert.throws(()=>changedHead('a'.repeat(40),{head_sha:'a'.repeat(40)}));
  assert.throws(()=>changedHead('invalid',{head_sha:'b'.repeat(40)}));
});
