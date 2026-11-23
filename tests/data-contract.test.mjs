import test from 'node:test';
import assert from 'node:assert/strict';
const dataStore=new Map();
globalThis.sessionStorage={getItem:k=>dataStore.get(k)||null,setItem:(k,v)=>dataStore.set(k,v),removeItem:k=>dataStore.delete(k)};
const calls=[];
let response={data:[],error:null,count:0};
const client={
 rpc:async(name,payload)=>{calls.push({rpc:name,payload});return response;},
 from(table){const call={table,steps:[]};calls.push(call);const q=new Proxy({}, {get(_,method){if(method==='then')return (yes,no)=>Promise.resolve(response).then(yes,no);return (...args)=>{call.steps.push([method,...args]);return q;};}});return q;}
};
globalThis.window={supabase:{createClient:()=>client}};
const {loadWorkspace,getTransactions,rpcWrite,saveRecord}=await import('../dist/data.js');
test('Every workspace table query is restricted to the selected restaurant',async()=>{
 calls.length=0;response={data:[],error:null};await loadWorkspace('restaurant-a');
 assert.equal(calls.length,10);
 for(const call of calls)assert.ok(call.steps.some(s=>s[0]==='eq'&&s[1]==='restaurant_id'&&s[2]==='restaurant-a'));
});
test('Transaction pagination, filters and count are server-side',async()=>{
 calls.length=0;response={data:[],count:40,error:null};await getTransactions('restaurant-b',{page:1,item:'tomato',type:'usage'});
 const steps=calls[0].steps;
 assert.ok(steps.some(s=>s[0]==='eq'&&s[1]==='restaurant_id'&&s[2]==='restaurant-b'));
 assert.ok(steps.some(s=>s[0]==='eq'&&s[1]==='item_id'&&s[2]==='tomato'));
 assert.ok(steps.some(s=>s[0]==='eq'&&s[1]==='movement_type'&&s[2]==='usage'));
 assert.ok(steps.some(s=>s[0]==='range'&&s[1]===25&&s[2]===49));
});
test('Interrupted RPC retries use the same ID; definitive failures release the ticket',async()=>{
 calls.length=0;dataStore.clear();const payload={p_restaurant_id:'a',p_order_id:'po',p_lines:[{quantity:12}]};
 response={error:{message:'Failed to fetch',code:''}};
 await assert.rejects(rpcWrite('u','a','receive_purchase_order',payload));
 const initial=calls[0].payload.p_request_id;
 response={data:'receipt',error:null};assert.equal(await rpcWrite('u','a','receive_purchase_order',payload),'receipt');
 assert.equal(calls[1].payload.p_request_id,initial);assert.equal(dataStore.size,0);
 response={error:{code:'42501',message:'Forbidden'}};
 await assert.rejects(rpcWrite('u','a','receive_purchase_order',payload));assert.equal(dataStore.size,0);
});
test('Record updates include both record ID and restaurant scope',async()=>{
 calls.length=0;response={data:{id:'item'},error:null};await saveRecord('inventory_items','item','a',{name:'Tomatoes'},false);
 assert.ok(calls[0].steps.some(s=>s[0]==='eq'&&s[1]==='id'&&s[2]==='item'));
 assert.ok(calls[0].steps.some(s=>s[0]==='eq'&&s[1]==='restaurant_id'&&s[2]==='a'));
 assert.deepEqual(calls[0].steps.find(s=>s[0]==='update')[1],{name:'Tomatoes'});
});
