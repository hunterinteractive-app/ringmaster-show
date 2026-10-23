const {test}=require('node:test');
const assert=require('node:assert/strict');
const {mkdtempSync,rmSync}=require('node:fs');
const {tmpdir}=require('node:os');
const {join,resolve}=require('node:path');
const {execFileSync}=require('node:child_process');
const output=mkdtempSync(join(tmpdir(),'worker-trigger-'));
execFileSync(process.execPath,[resolve('node_modules/typescript/bin/tsc'),join(__dirname,'worker-trigger.ts'),'--target','es2022','--module','commonjs','--outDir',output,'--skipLibCheck']);
process.on('exit',()=>rmSync(output,{recursive:true,force:true}));
const {createWorkerTrigger}=require(join(output,'worker-trigger.js'));
const workerUrl='https://report-worker-123.us-east1.run.app';
function harness(overrides={}) {
 const tasks=[]; let failures=0;
 const trigger=createWorkerTrigger({workerUrl,workToken:'test-work-token',
  getIdentityToken:async(a)=>{assert.equal(a,workerUrl);return 'test-oidc'},
  waitUntil:t=>tasks.push(t),onFailure:()=>failures++,
  request:async(url,options)=>{
   assert.equal(url,workerUrl+'/dispatch');
   assert.equal(options.headers.Authorization,'Bearer test-oidc');
   assert.equal(options.headers['X-Work-Token'],'test-work-token');
   assert.equal(options.redirect,'error');
   return new Response('{}');
  },...overrides});
 return {trigger,tasks,failures:()=>failures};
}
test('Calls only the configured private renderer with both credentials',async()=>{
 const h=harness();await h.trigger();await Promise.all(h.tasks);assert.equal(h.failures(),0);
});
test('Portal returns before render response and registers background lifecycle',async()=>{
 let release; const h=harness({request:()=>new Promise(r=>release=r)});
 await h.trigger();assert.equal(h.tasks.length,1);release(new Response('{}'));
 await Promise.all(h.tasks);
});
test('Every committed request wakes the worker, including work arriving during a render',async()=>{
 const h=harness();await Promise.all([h.trigger(),h.trigger()]);
 assert.equal(h.tasks.length,2);await Promise.all(h.tasks);
});
test('Network and authentication failures are handled for scheduled recovery',async()=>{
 for(const overrides of [{request:async()=>{throw new Error('secret')}},
 {getIdentityToken:async()=>{throw new Error('secret')}},
 {request:async()=>new Response('denied',{status:403})}]){
  const h=harness(overrides);await h.trigger();await Promise.all(h.tasks);
  assert.equal(h.failures(),1);
 }
});
test('Timeout aborts HTTP request and settles background task',async()=>{
 let signal;const h=harness({timeoutMs:10,request:async(_,o)=>{signal=o.signal;return new Promise(()=>{})}});
 await h.trigger();await Promise.all(h.tasks);assert.equal(signal.aborted,true);assert.equal(h.failures(),1);
});
test('Identity-token timeout does not send a late request',async()=>{
 let release;const h=harness({timeoutMs:10,getIdentityToken:()=>new Promise(r=>release=r),request:async()=>assert.fail('late request')});
 await h.trigger();await Promise.all(h.tasks);release('late-token');await new Promise(r=>setTimeout(r,5));assert.equal(h.failures(),1);
});
test('Invalid URL or missing work token fails before background invocation',async()=>{
 for(const overrides of [{workerUrl:''},{workerUrl:workerUrl+'/refund'},
 {workerUrl:'https://untrusted.test'},{workToken:''}]) {
  const h=harness(overrides);await assert.rejects(h.trigger(),/not configured/);
  assert.equal(h.tasks.length,0);
 }
});
