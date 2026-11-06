import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,writeFileSync,rmSync} from 'node:fs';
import {join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {tmpdir} from 'node:os';
import {barrierExecution} from '../staging.mjs';
import {integrationConfiguration} from '../channels.mjs';
const sha=n=>String(n).repeat(40);
const repositories={csharp:'CSharp_WSS_Integration_Lib',unity:'Unity_WSS_Integration_Lib',python:'Python_WSS_Integration_Lib',matlab:'Matlab_WSS_Integration_Lib'};
function fixture(family){
  const root=mkdtempSync(join(tmpdir(),'wss accepted main '));
  const git=(...args)=>execFileSync('git',['-C',root,...args],{encoding:'utf8',stdio:['ignore','pipe','pipe']}).trim();
  const write=(path,text)=>{mkdirSync(dirname(join(root,path)),{recursive:true});writeFileSync(join(root,path),text);};
  const commit=()=>{git('add','.');git('-c','user.name=CI','-c','user.email=ci@example.invalid','commit','-m','fixture');return git('rev-parse','HEAD');};
  git('init');write('.github/scripts/guard.ps1','# frozen code\n');write(integrationConfiguration(family),'{}\n');write('.github/workflows/_nested-worker.yml','name: frozen\n');write('payload.bin','old bytes');
  const authority=commit(),paths=['.github/scripts',integrationConfiguration(family),'.github/workflows'];
  const trusted=Object.fromEntries(paths.map(p=>[p,git('rev-parse',`HEAD:${p}`)]));
  write('payload.bin','verified new bytes');const merge=commit(),repository=`cwru-non-academic/${repositories[family]}`;
  const workflow=family==='unity'?'dispatch-unity-promotion.yml':'dispatch-cli-promotion.yml';
  const ctx={channel:'main',family,source_root:root,env:{GITHUB_ACTIONS:'true',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REPOSITORY:repository,GITHUB_REF:'refs/heads/main',GITHUB_SHA:merge,GITHUB_WORKFLOW_SHA:merge,GITHUB_WORKFLOW_REF:`${repository}/.github/workflows/${workflow}@refs/heads/main`},
    barrier:{schema:'wss-integration-barrier/v3',channel:'main',plan_id:'a'.repeat(64),candidate:{repository:'cwru-non-academic/WSSCore',commit:sha(1),run_id:'11',artifact_id:'12',archive:'WSS-Universal-ci.zip',sha256:'b'.repeat(64)},emitter:{run_id:'20',attempt:1,workflow:'.github/workflows/main-propagation.yml'},integrations:{[family]:{repository,head_sha:merge,normal_ci:{run_id:'30',attempt:1},execution:{source_sha:merge,authority_source_sha:authority,trusted}}}}};
  return {root,ctx,write,commit,authority,dispose:()=>rmSync(root,{recursive:true,force:true})};
}
for(const family of Object.keys(repositories)){
  test(`${family}: the actual accepted M executes code/config/full workflow frozen at S`,()=>{
    const f=fixture(family);try{
      assert.notEqual(f.ctx.env.GITHUB_SHA,f.authority);assert.equal(barrierExecution(f.ctx),true);
      const script=join(f.root,'actual bridge.ps1'),input=join(f.root,'context.json');
      f.write('actual bridge.ps1',"param([string]$Bridge,[string]$Context)\n$ErrorActionPreference='Stop'\n. $Bridge\n$c=Get-Content -LiteralPath $Context -Raw|ConvertFrom-Json\nAssert-WssCiBarrierExecution $c.barrier $c.family $c.source_root\n$global:LASTEXITCODE=0\n");
      f.write('context.json',JSON.stringify(f.ctx));
      const args=['-NoProfile','-NonInteractive','-File',script,fileURLToPath(new URL('../Staging.ps1',import.meta.url)),input];
      execFileSync('pwsh',args,{env:{...process.env,...f.ctx.env,WSS_CI_CHANNEL:'main'},stdio:'pipe'});
      assert.throws(()=>execFileSync('pwsh',args,{env:{...process.env,...f.ctx.env,WSS_CI_CHANNEL:'main',GITHUB_REF:'refs/heads/dev'},stdio:'pipe'}));
      // The bridge inputs stay outside the committed source and are not part of
      // a candidate diff or the frozen scripts/config/workflow authority.
      rmSync(script);rmSync(input);
      for(const mutate of [c=>c.env.GITHUB_SHA=f.authority,c=>c.env.GITHUB_WORKFLOW_SHA=f.authority,c=>c.env.GITHUB_REF='refs/heads/dev',c=>c.env.GITHUB_EVENT_NAME='pull_request_target',c=>c.env.GITHUB_REPOSITORY='cwru-non-academic/OTHER',c=>c.env.GITHUB_WORKFLOW_REF+='-other',c=>c.barrier.channel='dev',c=>c.barrier.integrations[family].execution.source_sha=f.authority,c=>delete c.barrier.integrations[family].execution.trusted['.github/workflows']]){
        const bad=structuredClone(f.ctx);mutate(bad);assert.throws(()=>barrierExecution(bad));
      }
      f.write('payload.bin','later unverified payload');f.commit();
      assert.throws(()=>barrierExecution(f.ctx),/Execution checkout/);
    }finally{f.dispose();}
  });
  for(const path of ['.github/scripts/guard.ps1',integrationConfiguration(family),'.github/workflows/_nested-worker.yml'])test(`${family}: changed ${path} is rejected even with matching run and checkout SHA`,()=>{
    const f=fixture(family);try{
      f.write(path,'changed authority\n');const next=f.commit();
      f.ctx.env.GITHUB_SHA=next;f.ctx.env.GITHUB_WORKFLOW_SHA=next;
      f.ctx.barrier.integrations[family].head_sha=next;f.ctx.barrier.integrations[family].execution.source_sha=next;
      assert.throws(()=>barrierExecution(f.ctx),/changed frozen authority/);
    }finally{f.dispose();}
  });
}
