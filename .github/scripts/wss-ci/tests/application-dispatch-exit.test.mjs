import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const common=fileURLToPath(new URL('../DispatchProof.ps1',import.meta.url)).replaceAll("'","''");
test('uncaught sender rejection exits nonzero instead of reporting success',()=>{
  const result=spawnSync('pwsh',['-NoProfile','-Command',`$ErrorActionPreference='Stop'; . '${common}'; Send-WssCiApplicationDispatch -ReadToken '' -WriteToken ''`],{encoding:'utf8'});
  assert.ifError(result.error);
  assert.notEqual(result.status,0);
  assert.match(result.stderr,/Separate read and target-only Actions-write tokens required/);
  assert.doesNotMatch(result.stdout,/dispatched|reused/);
});
test('module loading performs no dispatch and exits successfully',()=>{
  const result=spawnSync('pwsh',['-NoProfile','-Command',`$ErrorActionPreference='Stop'; . '${common}'; 'loaded'`],{encoding:'utf8'});
  assert.ifError(result.error);
  assert.equal(result.status,0,result.stderr);
  assert.equal(result.stdout.trim(),'loaded');
});for(const parameter of ['CSharpSenderPath','UnitySenderPath'])test(`requested missing ${parameter} fails instead of silently skipping adapter coverage`,()=>{
  const suite=fileURLToPath(new URL('./ApplicationDispatch.Tests.ps1',import.meta.url));
  const missing=fileURLToPath(new URL('./nonexistent-explicit-peer-source.ps1',import.meta.url));
  const result=spawnSync('pwsh',['-NoProfile','-File',suite,`-${parameter}`,missing],{encoding:'utf8'});
  assert.ifError(result.error);
  assert.notEqual(result.status,0);
  assert.match(result.stderr,/does not exist|Cannot find path/);
  assert.doesNotMatch(result.stdout,/PASS/);
});