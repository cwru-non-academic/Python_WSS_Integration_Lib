import {test,after} from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync,realpathSync,existsSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {receiptRoots,ROOT_KEYS,createReceiptWorkspace} from '../receipt.mjs';
import {receiptProfiles} from '../receipt-workflows.mjs';

// Isolated path contracts: no copied Core tree, native product execution or network.
const base=realpathSync.native(mkdtempSync(join(tmpdir(),'receipt paths Unicode Ω ')));
after(()=>rmSync(base,{recursive:true,force:true}));
const git=(root,...args)=>execFileSync('git',['-C',root,...args],{encoding:'utf8',stdio:['ignore','pipe','pipe']}).trim();
function checkout(name) {
 const root=join(base,name);mkdirSync(root);git(root,'init');
 git(root,'-c','user.name=CI','-c','user.email=ci@example.invalid','commit','--allow-empty','-m','Receipt path fixture');
 return root;
}
function shortPath(path) {
 return execFileSync('pwsh',['-NoProfile','-NonInteractive','-Command',"$ErrorActionPreference='Stop'; (New-Object -ComObject Scripting.FileSystemObject).GetFolder($env:WSS_PATH).ShortPath"],{encoding:'utf8',env:{...process.env,WSS_PATH:path}}).trim();
}
const roots=Object.fromEntries(['sourceRoot','validatorRoot','integrationRoot','engineRoot','coreRoot'].map(role=>[role,checkout(role+' long checkout')]));
const shortRoots=process.platform==='win32'?Object.fromEntries(Object.entries(roots).map(([role,path])=>[role,shortPath(path)])):null;
function configFor(profile,paths=roots) {
 const config={...paths,toolsRoot:profile.receipt.adapter_owner==='receiver'?paths.sourceRoot:paths.validatorRoot,outputRoot:join(base,'fresh output')};
 if(profile.role==='wrapper')for(const role of ['validatorRoot','integrationRoot','toolsRoot'])config[role]=paths.sourceRoot;
 return config;
}
assert.equal(Object.keys(receiptProfiles).length,9);
for(const [id,profile] of Object.entries(receiptProfiles)) {
 test(`${id}: all declared receipt roles admit clean physical roots`,()=>{
  const config=configFor(profile),actual=receiptRoots(config,profile);
  for(const role of ROOT_KEYS)assert.equal(actual[role],config[role]);
  assert.equal(existsSync(actual.outputRoot),false);
  assert.throws(()=>receiptRoots({...config,engineRoot:config.sourceRoot},profile),/Undeclared overlapping/);
  assert.throws(()=>receiptRoots({...config,outputRoot:join(config.sourceRoot,'..receipt')},profile),/Undeclared overlapping/);
 });
 test(`${id}: mixed Windows 8.3 aliases retain all declared roles`,{skip:process.platform!=='win32'},()=>{
  for(const role of Object.keys(roots)) {
   assert.notEqual(shortRoots[role].toLowerCase(),roots[role].toLowerCase(),'An actual distinct 8.3 alias is required');
   assert.equal(realpathSync.native(shortRoots[role]),roots[role]);
  }
  const mixed=configFor(profile,shortRoots);mixed.sourceRoot=roots.sourceRoot;
  mixed.outputRoot=join(shortPath(base),'fresh output');
  assert.deepEqual(receiptRoots(mixed,profile),receiptRoots(configFor(profile),profile));
 });
}

test('receipt workspace is a new canonical physical directory',()=>{
 const work=createReceiptWorkspace();
 try {assert.equal(work,realpathSync.native(work));assert.deepEqual(readFileSync(new URL('../receipt.mjs',import.meta.url),'utf8').match(/const work=createReceiptWorkspace\(\);/g),['const work=createReceiptWorkspace();']);}
 finally {rmSync(work,{recursive:true,force:true});}
});

for(const alias of [false,true])test(`Node ${alias?'8.3 alias':'long'} TEMP passes physical workspace to child PowerShell inventory`,{skip:alias&&process.platform!=='win32'},()=>{
 const temp=alias?shortPath(base):base;
 if(alias)assert.notEqual(temp.toLowerCase(),base.toLowerCase());
 const helper=resolve(process.env.WSS_CORE_REFERENCE||'.ci-reference/Core','tools/ci/shared/restored-assets/Universal-WssFiles.ps1');
 assert.equal(existsSync(helper),true,'Set WSS_CORE_REFERENCE to the reviewed Core checkout');
 const script=join(base,`inventory-${alias}.ps1`);
 writeFileSync(script,`param([string]$Root,[string]$Helper)
$ErrorActionPreference='Stop'
. $Helper
# Independent physical-root assertion prevents the repaired reader masking a bad Node workspace.
if ((Get-Item -LiteralPath $Root).FullName -cne $Root) { throw 'Workspace root is not physical' }
$expected=@($WssUniversalFiles)+@($WssMacOSFiles)
foreach($path in $expected) {
 $file=Join-Path $Root $path
 [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($file))|Out-Null
 [IO.File]::WriteAllText($file,'inventory path fixture only')
}
$enumerated=@(Get-ChildItem -LiteralPath $Root -File -Recurse|ForEach-Object {
 if (!$_.FullName.StartsWith($Root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal)) { throw 'Child metadata escaped physical root' }
 $_.FullName.Substring($Root.Length).TrimStart('\\','/').Replace('\\','/')
})
if (@(Compare-Object $expected $enumerated -CaseSensitive).Count) { throw 'Physical child inventory mismatch' }
$actual=@(Read-WssUniversalFiles -Root $Root)
if ($actual.Count -ne 27 -or @(Compare-Object $expected $actual -CaseSensitive).Count) { throw 'Universal inventory mismatch' }
Write-Output 'inventory-27-ok'
`);
 const module=new URL('../receipt.mjs',import.meta.url).href;
 const code=`import {createReceiptWorkspace} from ${JSON.stringify(module)};
import {realpathSync,rmSync} from 'node:fs';import {execFileSync} from 'node:child_process';import assert from 'node:assert/strict';
const work=createReceiptWorkspace();try {assert.equal(work,realpathSync.native(work));process.stdout.write(execFileSync('pwsh',['-NoProfile','-NonInteractive','-File',process.env.WSS_SCRIPT,'-Root',work,'-Helper',process.env.WSS_HELPER],{encoding:'utf8'}));}finally {rmSync(work,{recursive:true,force:true});}`;
 const result=execFileSync(process.execPath,['--input-type=module','-e',code],{encoding:'utf8',env:{...process.env,TEMP:temp,TMP:temp,TMPDIR:temp,WSS_SCRIPT:script,WSS_HELPER:helper}});
 assert.match(result,/inventory-27-ok/);
});
