import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promotionCredentialArguments} from '../promotion.mjs';

const execute=promisify(execFile);
test('real Git HTTP transport sends only the delayed credential despite inherited checkout headers',async()=>{
  const requests=[];
  const server=createServer((req,res)=>{
    requests.push(req.rawHeaders.filter((_,i)=>i%2===0).flatMap((name,i)=>name.toLowerCase()==='authorization'?[req.rawHeaders[i*2+1]]:[]));
    res.writeHead(403);res.end('Fixture stops before any remote write.');
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const scope=`http://127.0.0.1:${server.address().port}/`,token='synthetic-ci-credential';
  const root=await mkdtemp(join(tmpdir(),'wss-http-credential-'));
  const options={env:{...process.env,GIT_TERMINAL_PROMPT:'0',GIT_CONFIG_NOSYSTEM:'1'}};
  try {
    await execute('git',['init',root],options);
    for(const values of [['AUTHORIZATION: basic old-checkout'],['AUTHORIZATION: basic old-checkout','AUTHORIZATION: basic other-inherited']]){
      await execute('git',['-C',root,'config','--replace-all',`http.${scope}.extraheader`,values[0]],options);
      for(const value of values.slice(1))await execute('git',['-C',root,'config','--add',`http.${scope}.extraheader`,value],options);
      const before=requests.length;
      await assert.rejects(execute('git',['-C',root,...promotionCredentialArguments(token,scope),'ls-remote',scope+'fixture.git'],options));
      assert.ok(requests.length>before,'Git must exercise the actual HTTP transport');
      for(const headers of requests.slice(before))assert.deepEqual(headers,['basic '+Buffer.from('x-access-token:'+token).toString('base64')]);
    }
  } finally {
    server.closeAllConnections();await new Promise(resolve=>server.close(resolve));await rm(root,{recursive:true,force:true});
  }
});
