import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {publishPromotion} from '../promotion.mjs';
const sha=n=>String(n).repeat(40);
function fixture(channel='dev') {
  const calls=[],c={target_id:'python-cli',repository_root:'.',source_sha:sha(1),candidate:{repository:'cwru-non-academic/WSSCore',commit:sha(2),run_id:'1',artifact_id:'2',archive:'WSS-Universal-ci.zip',sha256:'a'.repeat(64)},branch:`automation/python-wss-1-${'a'.repeat(64)}`,allowed_paths:['external/wss-py-wrapper'],gitlinks:{'external/wss-py-wrapper':sha(3)},parent_heads:{'cwru-non-academic/Python_WSS_Integration_Lib':sha(3)},markers:['approval'],body_path:'body.md',title:'Promotion',commit_message:'Promote'};
  const env={GITHUB_ACTIONS:'true',GITHUB_REF:'refs/heads/dev',GITHUB_REPOSITORY:'cwru-non-academic/CLI_Python_WSS_Application',WSS_PUSH_TOKEN:'fixture-only'};
  if(channel==='main'){
    c.channel='main';Object.assign(env,{GITHUB_REF:'refs/heads/main',WSS_CI_CHANNEL:'main',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_SHA:c.source_sha,GITHUB_WORKFLOW_SHA:c.source_sha,GITHUB_WORKFLOW_REF:`${env.GITHUB_REPOSITORY}/.github/workflows/promote-integration.yml@refs/heads/main`});
  }
  const state={moved:false,refs:[],pulls:[]};
  const g={head:(repo,branch)=>{assert.equal(branch,channel);return repo===env.GITHUB_REPOSITORY?(state.moved?sha(9):sha(1)):sha(3);},pages:()=>state.pulls,get:path=>path.includes('matching-refs')?state.refs:{tree:{sha:sha(4)},parents:[{sha:sha(1)}]}};
  const git=(root,args)=>{
    calls.push(args);
    if(args[0]==='rev-parse')return sha(1);
    if(args[0]==='diff'&&args.includes('--name-only'))return args.includes('--cached')?'external/wss-py-wrapper':'';
    if(args[0]==='ls-files')return `160000 ${sha(3)} 0\texternal/wss-py-wrapper`;
    if(args[0]==='write-tree')return sha(4);
    if(args[0]==='branch')return 'feature';return '';
  };
  const writer={command:args=>{calls.push(args);return 'https://github.com/example/pull/1';}};
  const loadFrozenPlan=()=>({channel,candidate:c.candidate,manifest:JSON.parse(readFileSync(resolve(process.env.WSS_CORE_REFERENCE||'.ci-reference/Core',`tools/release/targets.${channel}.json`)))});
  const authorize=()=>calls.push(['canonical-Core-guard']);
  return {c,env,state,g,git,writer,calls,loadFrozenPlan,authorize};
}
test('one publication engine pushes without force and creates only draft dev PR',async()=>{
  const f=fixture();await publishPromotion(f.c,f);
  const push=f.calls.find(args=>args.includes('push'));assert.ok(push);assert.ok(!push.includes('--force'));
  const pr=f.calls.find(args=>args[0]==='pr');assert.ok(pr.includes('--draft'));assert.equal(pr[pr.indexOf('--base')+1],'dev');
});
test('orphan branches and moved sources cannot produce a write',async()=>{
  for(const mutate of [f=>f.state.refs=[{ref:`refs/heads/${f.c.branch}`,object:{sha:sha(7)}}],f=>f.state.moved=true]) {
    const f=fixture();mutate(f);await assert.rejects(()=>publishPromotion(f.c,f));
    assert.ok(!f.calls.some(args=>args.includes('push')||args[0]==='pr'));
  }
});
test('the same publication engine targets main only after canonical policy and live guard proof',async()=>{
  const f=fixture('main');await publishPromotion(f.c,f);
  const pr=f.calls.find(args=>args[0]==='pr');assert.equal(pr[pr.indexOf('--base')+1],'main');assert.ok(pr.includes('--draft'));
  assert.ok(f.calls.filter(args=>args[0]==='canonical-Core-guard').length>=2);
  const writeAt=f.calls.findIndex(args=>args.includes('push'));assert.ok(f.calls.slice(0,writeAt).some(args=>args[0]==='canonical-Core-guard'));
});
for(const [name,mutate]of [
  ['event',f=>f.env.GITHUB_EVENT_NAME='pull_request'],['ref',f=>f.env.GITHUB_REF='refs/heads/dev'],
  ['source',f=>f.env.GITHUB_SHA=sha(9)],['workflow source',f=>f.env.GITHUB_WORKFLOW_SHA=sha(9)],
  ['workflow identity',f=>f.env.GITHUB_WORKFLOW_REF=`${f.env.GITHUB_REPOSITORY}/.github/workflows/other.yml@refs/heads/main`],
  ['repository',f=>f.env.GITHUB_REPOSITORY='cwru-non-academic/OTHER'],['context channel',f=>f.env.WSS_CI_CHANNEL='dev'],
  ['plan channel',f=>{const load=f.loadFrozenPlan;f.loadFrozenPlan=()=>({...load(),channel:'dev'});}],
  ['candidate',f=>{const load=f.loadFrozenPlan;f.loadFrozenPlan=()=>({...load(),candidate:{...f.c.candidate,commit:sha(9)}});}],
  ['frozen authority',f=>f.authorize=()=>{throw Error('Frozen workflow changed');}]
])test(`main Core plan alone cannot bypass receiver ${name}`,async()=>{
  const f=fixture('main');mutate(f);await assert.rejects(publishPromotion(f.c,f));
  assert.ok(!f.calls.some(args=>args.includes('push')||args[0]==='pr'));
});
