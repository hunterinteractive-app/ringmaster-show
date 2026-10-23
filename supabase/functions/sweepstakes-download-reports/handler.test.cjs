// Run with: node --test supabase/functions/sweepstakes-download-reports/handler.test.cjs
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {mkdtempSync,rmSync}=require('node:fs');
const {tmpdir}=require('node:os');
const {join,resolve}=require('node:path');
const {execFileSync}=require('node:child_process');
const output=mkdtempSync(join(tmpdir(),'portal-download-'));
execFileSync(process.execPath,[resolve('node_modules/typescript/bin/tsc'),join(__dirname,'handler.ts'),'--target','es2022','--module','commonjs','--outDir',output,'--skipLibCheck']);
process.on('exit',()=>rmSync(output,{recursive:true,force:true}));
const {createReportDownloadHandler}=require(join(output,'handler.js'));
function setup({visible=true,status='generated',readyArba=false,triggerFails=false,queueFails=false,alreadyPending=false}={}) {
 let queues=0,triggers=0,signatures=[];
 const artifact={id:'report',finalize_run_id:'run',scope_key:'scope',section_ids:['a'],report_name:readyArba?'arba_report':'sweepstakes_report',artifact_status:status,storage_bucket:'reports',storage_path:'file.pdf',metadata:{club_name:'Club',sanction_number:'123',section_label:'Open A'}};
 const user={auth:{getUser:async()=>({data:{user:{id:'chair'}}})},rpc:async()=>({data:visible?[{portal_club_id:'club',show_id:'show',sanction_number:'123',club_name:readyArba?'ARBA':'Club',section_label:'Open A',report_artifact_id:'report'}]:[]})};
 const admin={
 from(table){const chain={select(){return chain},eq(){return chain},in(){return chain},order(){return chain},then(resolve){return Promise.resolve({data:table==='show_report_artifacts'?[artifact]:[]}).then(resolve)}};return chain},
 rpc:async(name)=>{assert.equal(name,'request_portal_report_regeneration');queues++;return queueFails?{error:{message:'queue error'}}:{data:{queued_count:alreadyPending?0:1,already_pending:alreadyPending}}},
 storage:{from:()=>({createSignedUrl:async(path,ttl)=>{signatures.push(ttl);return {data:{signedUrl:'https://example.test/report'}}}})}
 };
 const handler=createReportDownloadHandler({createClient:(_,key)=>key==='anon'?user:admin,supabaseUrl:'url',anonKey:'anon',serviceRole:'service',triggerWorker:async()=>{assert.ok(queues>0);triggers++;if(triggerFails)throw new Error('provider secret must not leak')}});
 return {run:refresh=>handler(new Request('https://api.test',{method:'POST',headers:{Authorization:'Bearer test','Content-Type':'application/json'},body:JSON.stringify({show_id:'show',portal_club_id:'club',sanction_number:'123',refresh})})),queues:()=>queues,triggers:()=>triggers,signatures};
}
test('Download requests fresh regeneration even when reports already exist',async()=>{const f=setup();assert.equal((await f.run(true)).status,202);assert.equal(f.queues(),1);assert.equal(f.signatures.length,0)});
test('Polling retrieves completed files without restarting regeneration',async()=>{const f=setup();const r=await f.run(false);assert.equal(r.status,200);assert.equal((await r.json()).downloads.length,1);assert.equal(f.queues(),0);assert.deepEqual(f.signatures,[900,900])});
test('Failed reports can be explicitly retried',async()=>{const f=setup({status:'failed'});assert.equal((await f.run(true)).status,202);assert.equal(f.queues(),1)});
test('Polling queued jobs remains pending and does not requeue',async()=>{const f=setup({status:'queued'});assert.equal((await f.run(false)).status,202);assert.equal(f.queues(),0)});
test('Unassigned chair cannot queue or download reports',async()=>{const f=setup({visible:false});assert.equal((await f.run(true)).status,403);assert.equal(f.queues(),0);assert.equal(f.signatures.length,0)});
test('ARBA warnings with files are downloadable after regeneration',async()=>{const f=setup({status:'warning',readyArba:true});assert.equal((await f.run(false)).status,200)});
test('Download wakes worker after queue commits',async()=>{const f=setup();const r=await f.run(true);assert.equal((await r.json()).worker_trigger,'requested');assert.equal(f.triggers(),1)});
test('Pending generation can wake worker without resetting queued work',async()=>{const f=setup({alreadyPending:true});assert.equal((await f.run(true)).status,202);assert.equal(f.triggers(),1)});
test('Trigger failure keeps queued report available to scheduled backup',async()=>{const f=setup({triggerFails:true});const r=await f.run(true);assert.equal(r.status,202);const body=await r.json();assert.equal(body.worker_trigger,'scheduled_backup');assert.equal(JSON.stringify(body).includes('secret'),false);assert.equal(f.queues(),1)});
test('Polling never triggers worker',async()=>{for(const status of ['queued','generated']){const f=setup({status});await f.run(false);assert.equal(f.triggers(),0)}});
test('Unauthorized requests never trigger worker',async()=>{const f=setup({visible:false});await f.run(true);assert.equal(f.triggers(),0)});
test('Failed queue request never triggers worker',async()=>{const f=setup({queueFails:true});assert.equal((await f.run(true)).status,500);assert.equal(f.triggers(),0)});
