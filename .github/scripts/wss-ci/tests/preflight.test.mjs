import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,existsSync} from 'node:fs';
import {request,assertRun,startPreflight,waitRun,dispatchJson} from '../preflight.mjs';
import {resolve} from 'node:path';

const sha=n=>String(n).repeat(40),repository='cwru-non-academic/Python_WSS_Integration_Lib';
const candidate={repository:'cwru-non-academic/WSSCore',commit:sha(1),run_id:'12',artifact_id:'34',archive:'WSS-Universal-ci.zip',sha256:'a'.repeat(64)};
function fixture(){
  const context={repository,candidate,wrapper_sha:sha(2),application_sha:sha(3)},expected=request(context);
  const run={id:56,repository:{full_name:repository},head_repository:{full_name:repository},path:'.github/workflows/wss-preflight.yml',head_sha:sha(2),head_branch:'dev',event:'workflow_dispatch',display_title:expected.title,status:'completed',conclusion:'success'};
  const f={context,expected,run,runs:[],posts:0,time:0};
  f.g={head:()=>sha(2),pages:()=>f.runs,run:()=>f.run};
  f.options={now:()=>f.time,pause:async ms=>{f.time+=ms;},post:async()=>{f.posts++;f.runs=[f.run];}};
  return f;
}
test('all nine profiles use the same request builder and retain only wire-format differences',()=>{
  const repositories={
    CSharp_WSS_Integration_Lib:['csharp','wrapper'],CLI_CSharp_WSS_Application:['csharp','cli'],
    Unity_WSS_Integration_Lib:['unity','wrapper'],GUI_Unity_WSS_Application:['unity','gui'],
    Python_WSS_Integration_Lib:['python','wrapper'],CLI_Python_WSS_Application:['python','cli'],ROS_Python_WSS_Application:['python','ros'],
    Matlab_WSS_Integration_Lib:['matlab','wrapper'],CLI_Matlab_WSS_Application:['matlab','cli']
  };
  for(const [name,[family,role]] of Object.entries(repositories)){
    const c={repository:`cwru-non-academic/${name}`,candidate,wrapper_sha:family==='csharp'&&role==='wrapper'?'':sha(2),application_sha:family==='csharp'?'':sha(3),correlation_id:'wss-12-34-fixture'};
    const r=request(c);assert.equal(r.body.ref,'dev');assert.equal(r.body.inputs.correlation_id,c.correlation_id);
    if(family==='csharp'){assert.equal(r.body.inputs.wss_commit,candidate.commit);assert.equal(r.body.inputs.integration_sha,role==='cli'?sha(2):undefined);}
    else{assert.deepEqual(JSON.parse(r.body.inputs.candidate_json),candidate);assert.equal(r.body.inputs[family==='unity'?'gui_sha':role==='ros'?'ros_sha':'cli_sha'],sha(3));}
  }
});
test('foreign repositories and incomplete source/candidate identities fail before transport',async()=>{
  for(const mutate of [c=>c.repository='other/repository',c=>c.candidate={...candidate,run_id:'0'},c=>c.wrapper_sha='short',c=>c.source_sha='bad']){
    const f=fixture();mutate(f.context);await assert.rejects(startPreflight(f.g,f.context,f.options));assert.equal(f.posts,0);
  }
});
test('unique existing correlated run is reused without requesting write credentials',async()=>{
  const f=fixture();f.runs=[f.run];assert.equal((await startPreflight(f.g,f.context,f.options)).id,56);assert.equal(f.posts,0);
});
test('duplicates, foreign runs, changed sources and failed correlated runs never select another green run',async()=>{
  for(const mutate of [f=>f.runs=[f.run,f.run],f=>f.run.head_repository.full_name='other/repo',f=>f.run.head_sha=sha(9),f=>f.run.head_branch='main',f=>f.run.conclusion='failure',f=>f.run.id=99]){
    const f=fixture();f.runs=[structuredClone(f.run)];mutate(f);await assert.rejects(startPreflight(f.g,f.context,f.options));assert.equal(f.posts,0);
  }
});
test('new request verifies the dev source and issues exactly one dispatch',async()=>{
  const f=fixture();assert.equal((await startPreflight(f.g,f.context,f.options)).id,56);assert.equal(f.posts,1);
  const changed=fixture();changed.g.head=()=>sha(8);await assert.rejects(startPreflight(changed.g,changed.context,changed.options),/advanced/);assert.equal(changed.posts,0);
});
test('failed POST and missing discovery stay uncertain without automatic redispatch',async()=>{
  const f=fixture();f.options.post=async()=>{f.posts++;throw Error('transport outcome uncertain');};
  await assert.rejects(startPreflight(f.g,f.context,f.options),/uncertain/);assert.equal(f.posts,1);
  const missing=fixture();missing.options.post=async()=>{missing.posts++;};missing.context.discovery_seconds=1;
  await assert.rejects(startPreflight(missing.g,missing.context,missing.options),/outcome uncertain/);assert.equal(missing.posts,1);
});
test('wait uses the same exact run throughout, rejecting identity changes and failed completion',async()=>{
  const f=fixture(),e={...f.expected,run_id:'56',timeout_seconds:1};
  assert.equal((await waitRun(f.g,e,f.options)).id,56);
  f.run.status='in_progress';await assert.rejects(waitRun(f.g,e,f.options),/Timed out/);
  f.run.status='completed';f.run.conclusion='failure';await assert.rejects(waitRun(f.g,e,f.options),/failed/);
  assert.throws(()=>assertRun({...f.run,conclusion:'success',id:99},e),/identity/);
});
test('a green PR artifact cannot masquerade as the exact canonical dev push producer',()=>{
  const f=fixture(),repo=candidate.repository;
  const run={...f.run,repository:{full_name:repo},head_repository:{full_name:repo},head_sha:candidate.commit,path:'.github/workflows/artifacts.yml',event:'pull_request'};
  assert.throws(()=>assertRun(run,{repository:repo,source_sha:candidate.commit,workflow:'artifacts.yml',event:'push',run_id:'56'}),/identity/);
});
test('invalid wait expectations fail before any GitHub lookup',async()=>{
  let reads=0;await assert.rejects(waitRun({run:()=>{reads++;}},{repository:'foreign/repo',source_sha:sha(1),run_id:'56'}),/expectation/);assert.equal(reads,0);
});
test('HTTP body is a UTF-8 file with literal JSON and scoped credential isolation',()=>{
  let count=0,path;
  const body={ref:'dev',inputs:{text:'quote" slash\\ newline\n Unicode λ literal $(value)'}};
  dispatchJson(repository,body,'write-fixture',{environment:{GH_TOKEN:'read-fixture'},execute:(command,args,options)=>{
    count++;assert.equal(command,'gh');assert.deepEqual(args.slice(0,4),['api','--method','POST',`repos/${repository}/actions/workflows/wss-preflight.yml/dispatches`]);
    path=args.at(-1);assert.equal(args.at(-2),'--input');assert.notEqual(path,'-');
    const bytes=readFileSync(path);assert.notEqual(bytes[0],0xef);assert.deepEqual(JSON.parse(bytes),body);assert.equal(options.env.GH_TOKEN,'write-fixture');
  }});
  assert.equal(count,1);assert.equal(existsSync(path),false);
});
test('HTTP error performs one POST, cleans request file and does not expose credentials',()=>{
  let count=0,path;
  assert.throws(()=>dispatchJson(repository,{ref:'dev',inputs:{}},'secret-fixture',{execute:(_cmd,args)=>{count++;path=args.at(-1);throw Error('secret-fixture');}}),error=>/failed\/uncertain/.test(error.message)&&!error.message.includes('secret-fixture'));
  assert.equal(count,1);assert.equal(existsSync(path),false);
});
test('main uses the same serializer but binds the immutable producer and frozen main target',async()=>{
  const f=fixture();f.context.channel='main';f.run.head_branch='main';
  const manifest=JSON.parse(readFileSync(resolve(process.env.WSS_CORE_REFERENCE||'.ci-reference/Core','tools/release/targets.main.json')));
  const p={channel:'main',candidate,manifest,target_snapshots:{'python-wrapper':{head_sha:sha(2)}}};
  f.g.head=(repo,branch)=>{assert.equal(branch,'main');return repo===candidate.repository?candidate.commit:sha(2);};
  f.options.loadFrozenPlan=()=>p;
  assert.equal((await startPreflight(f.g,f.context,f.options)).id,56);assert.equal(f.posts,1);assert.equal(request(f.context).body.ref,'main');
  const bad=fixture();bad.context.channel='main';bad.options.loadFrozenPlan=()=>({...p,channel:'dev'});bad.g.head=()=>candidate.commit;
  await assert.rejects(startPreflight(bad.g,bad.context,bad.options));assert.equal(bad.posts,0);
});
