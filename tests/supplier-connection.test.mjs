import test from 'node:test';
import assert from 'node:assert/strict';
import {saveSupplierWithConnection,supplierConnectionCode} from '../dist/supplier-connection.js';

const code='29dbdd43-38e3-4ee0-96c0-fdaf2b3a13c2';
function setup(){
 const calls=[];
 return {calls,options:{draft:{id:'same-supplier',isNew:true},restaurantId:'restaurant-a',values:{name:'QA supplier',is_active:true},code,saveSupplier:async(...args)=>calls.push(['save',...args]),requestConnection:async(...args)=>calls.push(['connect',...args])}};
}
test('A blank connection code saves only the supplier; a supplied code is trimmed and normalized',async()=>{
 const {calls,options}=setup();
 assert.equal(supplierConnectionCode(`  ${code.toUpperCase()}  `),code);
 const result=await saveSupplierWithConnection({...options,code:'  '});
 assert.equal(result.connectionRequested,false);assert.deepEqual(calls.map(c=>c[0]),['save']);
});
test('Malformed codes and inactive suppliers are rejected before any write',async()=>{
 for(const overrides of [{code:'not-a-code'},{values:{name:'QA supplier',is_active:false}}]){
  const {calls,options}=setup();
  await assert.rejects(saveSupplierWithConnection({...options,...overrides}),/connection code|Active supplier/);
  assert.equal(calls.length,0);
 }
});
test('A connection request uses the newly saved supplier and the selected restaurant',async()=>{
 const {calls,options}=setup();
 assert.equal((await saveSupplierWithConnection(options)).connectionRequested,true);
 assert.deepEqual(calls.map(c=>c[0]),['save','connect']);
 assert.deepEqual(calls[1],['connect','restaurant-a','same-supplier',code]);
});
test('Connection failure keeps the saved supplier; correcting the code updates that same row',async()=>{
 const {calls,options}=setup();
 await assert.rejects(saveSupplierWithConnection({...options,requestConnection:async()=>{throw new Error('Supplier connection code not found');}}),/Supplier saved.*code not found/);
 assert.equal(options.draft.saved,true);assert.equal(options.draft.isNew,false);
 await saveSupplierWithConnection(options);
 assert.equal(calls.filter(c=>c[0]==='save'&&c[4]===true).length,1);
 assert.equal(calls.filter(c=>c[0]==='save'&&c[4]===false).length,1);
 assert(calls.every(c=>c[0]!=='save'||c[1]==='same-supplier'));
});
test('A failed supplier save never requests a connection and retains the same retry ID',async()=>{
 const {calls,options}=setup();
 await assert.rejects(saveSupplierWithConnection({...options,saveSupplier:async()=>{throw new Error('Failed to fetch');}}));
 assert.equal(calls.length,0);assert.equal(options.draft.isNew,true);assert.equal(options.draft.id,'same-supplier');
});
