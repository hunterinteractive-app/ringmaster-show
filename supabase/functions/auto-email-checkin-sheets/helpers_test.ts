import {loadAllPages,errorMessage,retryWindowOpen} from './helpers.ts';
function assert(value:unknown) { if(!value) throw new Error('Assertion failed'); }
Deno.test('loads 2006 entries despite a smaller server cap',async()=>{
 const entries=Array.from({length:2006},(_,id)=>({id}));
 const result=await loadAllPages(async(from,to)=>entries.slice(from,Math.min(to+1,from+137)));
 assert(result.length===2006 && new Set(result.map(r=>r.id)).size===2006);
 assert(result[2005].id===2005);
});
Deno.test('empty report stops immediately',async()=>{
 let calls=0;assert((await loadAllPages(async()=>{calls++;return []})).length===0);assert(calls===1);
});
Deno.test('page errors prevent partial results',async()=>{
 let calls=0;let threw=false;
 try {await loadAllPages(async()=>{if(calls++)throw new Error('database unavailable');return [1]})}catch{threw=true}
 assert(threw);
});
Deno.test('structured database errors remain readable',()=>{
 assert(errorMessage({code:'57014',message:'statement timeout',details:'report read'})==='57014: statement timeout: report read');
 assert(errorMessage(new Error('provider failure'))==='provider failure');
});
Deno.test('uncertain sends stop before provider idempotency expires',()=>{
 const start='2026-09-11T00:00:00Z';assert(retryWindowOpen(start,Date.parse(start)+3600000));
 assert(!retryWindowOpen(start,Date.parse(start)+24*3600000));
});
