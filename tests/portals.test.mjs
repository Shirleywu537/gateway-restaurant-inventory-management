import test from 'node:test';
import assert from 'node:assert/strict';
import {stockRows,orderStatusRows,orderValueByRestaurant,barChart,donutChart} from '../dist/charts.js';
import {supplierContent,supplierOrderBody,supplierPages,preferredSupplierAccount,supplierBusinessName} from '../dist/supplier.js';
import {supplierDemoSnapshot} from '../dist/supplier-demo.js';
test('Stock comparison never mixes units or includes archived ingredients',()=>{
 const rows=stockRows([{name:'Rice',base_unit:'kg',is_active:true,quantity_on_hand:5,reorder_point:2},{name:'Milk',base_unit:'l',is_active:true,quantity_on_hand:99,reorder_point:1},{name:'Old',base_unit:'kg',is_active:false,quantity_on_hand:1,reorder_point:4}],'kg');
 assert.deepEqual(rows,[{label:'Rice',value:5,secondary:2}]);
});
test('Order value charts separate currencies and exclude cancelled orders',()=>{
 const orders=[{restaurant_id:'a',restaurant_name:'A',currency:'USD',status:'ordered',total_amount:50},{restaurant_id:'a',restaurant_name:'A',currency:'EUR',status:'ordered',total_amount:900},{restaurant_id:'a',restaurant_name:'A',currency:'USD',status:'cancelled',total_amount:900},{restaurant_id:'b',restaurant_name:'B',currency:'USD',status:'received',total_amount:10}];
 assert.deepEqual(orderValueByRestaurant(orders,'USD'),[{label:'A',value:50},{label:'B',value:10}]);
 assert.equal(orderStatusRows(orders).reduce((n,r)=>n+r.value,0),4);
});
test('Charts handle empty data and escape labels',()=>{
 assert(!donutChart('Empty','',[]).includes('NaN'));assert(!barChart('x','',[]).includes('NaN'));
 assert(barChart('Safe','',[{label:'<img src=x>',value:2}]).includes('&lt;img src=x&gt;'));
});
test('Supplier views omit inventory routes and private stock fields',()=>{
 assert.deepEqual(Object.keys(supplierPages),['home','restaurants','orders','deliveries','workspace']);
 const p=structuredClone(supplierDemoSnapshot);p.quantity_on_hand='PRIVATE_BALANCE';p.inventory_items=[{name:'PRIVATE_INGREDIENT'}];p.stock_movements=[{reason:'PRIVATE_USAGE'}];
 for(const page of Object.keys(supplierPages)){
  const html=supplierContent({page,supplierSnapshot:p,supplierRestaurant:'',search:'',chartCurrency:'USD'});
  assert(!/PRIVATE_BALANCE|PRIVATE_INGREDIENT|PRIVATE_USAGE|href="#\/ingredients"|href="#\/suppliers"|href="#\/transactions"/.test(html));
 }
 assert(supplierOrderBody(p,p.orders[0].id).body.includes('not the restaurant’s current stock'));
});

test('Supplier selection opens the created membership and ignores stale or unauthorized saved IDs',()=>{
 const accounts=[{id:'a',name:'First supplier'},{id:'b',name:'Second supplier'}];
 assert.equal(preferredSupplierAccount(accounts,{preferredId:'b',currentId:'a',savedId:'a'}).id,'b');
 assert.equal(preferredSupplierAccount(accounts,{savedId:'b'}).id,'b');
 assert.equal(preferredSupplierAccount(accounts,{preferredId:'outside',currentId:'removed',savedId:'other-user'}).id,'a');
 assert.equal(preferredSupplierAccount([],{savedId:'b'}),null);
});
test('Supplier creation validates meaningful business names and preserves read-only samples',()=>{
 assert.equal(supplierBusinessName('  QA Produce  '),'QA Produce');
 assert.throws(()=>supplierBusinessName('   '),/business name/);
 assert.throws(()=>supplierBusinessName('a'.repeat(161)),/160/);
 const base={page:'workspace',supplierSnapshot:supplierDemoSnapshot,supplierRestaurant:'',search:'',chartCurrency:'USD'};
 const sample=supplierContent({...base,demo:true});
 assert(!sample.includes('data-action="new-supplier-account"'));
 assert(sample.includes('Sign in to create and manage real supplier businesses.'));
 assert(supplierContent({...base,demo:false}).includes('data-action="new-supplier-account"'));
});
