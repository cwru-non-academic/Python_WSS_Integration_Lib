import {execFileSync} from 'node:child_process';
import {mkdtempSync,readFileSync,writeFileSync,existsSync,mkdirSync,rmSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {pathToFileURL} from 'node:url';
import {CONTRACT_SHA,RECEIPT_WORKFLOW,need,readOnlyGh,targetPolicy,runIdentity,normalRun,mergedPr,emitter,changedHead} from './ReceiptGuards.mjs';

const [sourceRoot,toolsRoot,contractRoot,outputRoot]=process.argv.slice(2).map(x=>resolve(x));
need(sourceRoot && toolsRoot && contractRoot && outputRoot,'Four trusted workspace paths are required');
need(process.env.GITHUB_ACTIONS==='true','Receipt writer is Actions-only');
const git=(root,...args)=>execFileSync('git',['-C',root,...args],{encoding:'utf8'}).trim();
need(git(contractRoot,'rev-parse','HEAD')===CONTRACT_SHA,'Contract verifier is not the immutable reviewed revision');
for(const root of [sourceRoot,toolsRoot,contractRoot]) need(git(root,'status','--porcelain','--untracked-files=no')==='','Receipt validator checkouts must be clean');
const v=await import(pathToFileURL(join(contractRoot,'tools/release/verify.mjs')));
const c=await import(pathToFileURL(join(contractRoot,'tools/release/github.mjs')));
class ReadOnly extends c.GitHub { command(args) { readOnlyGh(args);return super.command(args); } }
const g=new ReadOnly(),id=process.env.TARGET_ID,producerId=process.env.PRODUCER_RUN_ID,planId=process.env.PLAN_ID;
need(/^[1-9][0-9]*$/.test(producerId||'') && /^[a-f0-9]{64}$/.test(planId||''),'Invalid reconciliation inputs');
const p=c.loadPlan(g,producerId);
need(p.plan_id===planId,'Input plan ID differs from frozen producer plan');
const t=targetPolicy(p,id),head=g.head(t.repository),snapshot=p.target_snapshots[id];
changedHead(head,snapshot);
need(git(sourceRoot,'rev-parse','HEAD')===head,'Checkout is not exact current target dev');
emitter(g.run(t.repository,process.env.GITHUB_RUN_ID),process.env,t,head);
const zip=c.archive(g,p.candidate),coreRun=g.run(v.CORE,producerId);
v.producer(p,{run:coreRun,current_head:g.head(v.CORE),jobs:g.jobs(v.CORE,coreRun),artifact:zip.artifact,archive_sha256:v.bytesDigest(zip.files[p.candidate.archive])});
for(const path of t.trusted_paths) need(g.object(t.repository,head,path).sha===snapshot.trusted[path],`Frozen receipt/CI tooling changed: ${path}`);
need(git(toolsRoot,'rev-parse','HEAD:.github/scripts')===p.target_snapshots['python-wrapper'].trusted['.github/scripts'],'Pinned Python validator tree differs from frozen wrapper tooling');
const associations=g.pages(`repos/${t.repository}/commits/${head}/pulls`).filter(pr=>pr.merge_commit_sha===head && pr.merged_at && pr.base?.ref==='dev');
need(associations.length===1,'Current dev is not a unique reviewed dependency merge');
const pr=g.get(`repos/${t.repository}/pulls/${associations[0].number}`);
mergedPr(pr,t,head,p.candidate);
const normal=normalRun(g.pages(`repos/${t.repository}/actions/workflows/${t.workflow.split('/').at(-1)}/runs?branch=dev&head_sha=${head}`,'workflow_runs'),t,pr);
v.jobs(g.jobs(t.repository,normal),t.jobs);
need(g.tree(t.repository,normal.head_sha)===g.tree(t.repository,head),'Normal CI did not test accepted tree');
const parents=Object.fromEntries(Object.entries(t.parents).map(([parent,path])=>{
  const entry=g.object(t.repository,head,path);
  need(entry.type==='commit' && entry.mode==='160000','Parent is not a Git submodule');
  return [parent,entry.sha];
}));
const work=mkdtempSync(join(tmpdir(),'wss-python-receipt-'));
try {
  writeFileSync(join(work,'context.json'),JSON.stringify({plan:p,target:t,head,pr,parents}));
  execFileSync('pwsh',['-NoProfile','-File',join(toolsRoot,'.github/scripts/Verify-ReleaseAcceptance.ps1'),'-ContextPath',join(work,'context.json'),'-ToolsRoot',toolsRoot,'-WorkRoot',join(work,'validation'),'-OutputPath',join(work,'preflights.json')],{stdio:'inherit'});
  const preflights=JSON.parse(readFileSync(join(work,'preflights.json'),'utf8').replace(/^\uFEFF/,''));
  need(Array.isArray(preflights) && preflights.length===(t.role==='wrapper'?3:4),'Missing full v2 and merged-wrapper preflight proof');
  for(const d of preflights) {
    const r=g.run(d.repository,d.run_id);
    runIdentity(r,d.repository,d.workflow,d.source_sha,'workflow_dispatch');
    need(r.status==='completed' && r.conclusion==='success','Preflight is not successful');
    const normalized=JSON.parse(g.download(d.repository,d.run_id,'wss-candidate-provenance',['candidate.json'])['candidate.json']);
    v.candidate(normalized);need(v.canonical(normalized)===v.canonical(p.candidate),'Normalized candidate differs from rich proof/frozen plan');
  }
  // Recheck mutable branch/tool state immediately before writing a read-only claim.
  need(g.head(t.repository)===head && g.head(v.CORE)===p.candidate.commit,'Source moved during verification');
  const latest=normalRun(g.pages(`repos/${t.repository}/actions/workflows/${t.workflow.split('/').at(-1)}/runs?branch=dev&head_sha=${head}`,'workflow_runs'),t,pr);
  need(String(latest.id)===String(normal.id) && latest.run_attempt===normal.run_attempt,'New normal CI supersedes selected proof');
  need(!existsSync(join(outputRoot,'receipt.json')),'Receipt output must be new');mkdirSync(outputRoot,{recursive:true});
  const receipt={schema:'wss-acceptance-receipt/v1',plan_id:p.plan_id,channel:'dev',target_id:id,candidate:p.candidate,mode:'merged-pr',
    merge:{pr_number:String(pr.number),head_sha:pr.head.sha,sha:head},normal_ci:{run_id:String(normal.id),attempt:normal.run_attempt},preflights,parents,
    emitter:{run_id:process.env.GITHUB_RUN_ID,attempt:Number(process.env.GITHUB_RUN_ATTEMPT),source_sha:head,workflow:RECEIPT_WORKFLOW},coverage:t.coverage};
  writeFileSync(join(outputRoot,'receipt.json'),v.canonical(receipt)+'\n');
  console.log(`Verified ${id} acceptance at ${head}; receipt awaits successful artifact upload/emitter completion.`);
} finally {rmSync(work,{recursive:true,force:true});}
