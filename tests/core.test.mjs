import test from 'node:test';
import assert from 'node:assert/strict';
import {decimal,orderLines,receiptLines,movementChange,requestTicket,escapeHtml,manager,stockOperator} from '../dist/core.js';
const items=[{id:'tomato',is_active:true},{id:'rice',is_active:true},{id:'old',is_active:false}];
test('Order inputs reject duplicate ingredients, archived items and excess precision',()=>{
 const row={item_id:'tomato',quantity:'20',unit_price:'2.50'};
 assert.deepEqual(orderLines([row],items),[{item_id:'tomato',quantity:20,unit_price:2.5}]);
 assert.throws(()=>orderLines([row,row],items),/one line/);
 assert.throws(()=>orderLines([{...row,item_id:'old'}],items),/active ingredient/);
 assert.throws(()=>orderLines([{...row,quantity:'1.0001'}],items),/decimal/);
});
test('Partial receiving skips zero lines and rejects over-receiving',()=>{
 const p=[{purchase_order_line_id:'t',quantity_outstanding:8},{purchase_order_line_id:'r',quantity_outstanding:0}];
 assert.deepEqual(receiptLines([{purchase_order_line_id:'t',quantity:'3'},{purchase_order_line_id:'r',quantity:'0'}],p),[{purchase_order_line_id:'t',quantity:3}]);
 assert.throws(()=>receiptLines([{purchase_order_line_id:'t',quantity:'9'}],p),/exceeds/);
 assert.throws(()=>receiptLines([{purchase_order_line_id:'t',quantity:'0'}],p),/at least one/);
});
test('Stock entry converts deductions and enforces staff restrictions',()=>{
 assert.equal(movementChange('usage','4','staff'),-4);
 assert.equal(movementChange('waste','1','manager'),-1);
 assert.equal(movementChange('opening','10','owner'),10);
 assert.equal(movementChange('adjustment','-2','owner'),-2);
 assert.throws(()=>movementChange('adjustment','1','staff'),/owners and managers/);
 assert.throws(()=>movementChange('usage','1','viewer'),/cannot/);
 assert.throws(()=>movementChange('receipt','1','owner'),/supported/);
 assert.throws(()=>movementChange('usage','-1','owner'));
});
test('Retry tickets preserve identity and payload across interrupted requests',()=>{
 const data=new Map();const storage={getItem:k=>data.get(k)||null,setItem:(k,v)=>data.set(k,v),removeItem:k=>data.delete(k)};
 const first=requestTicket(storage,'user:restaurant','receive',{quantity:12});
 const retry=requestTicket(storage,'user:restaurant','receive',{quantity:12});
 assert.equal(first.id,retry.id);
 assert.throws(()=>requestTicket(storage,'user:restaurant','receive',{quantity:13}),/unconfirmed/);
 assert.notEqual(requestTicket(storage,'other:restaurant','receive',{quantity:12}).id,first.id);
 first.clear();assert.notEqual(requestTicket(storage,'user:restaurant','receive',{quantity:12}).id,first.id);
});
test('Numeric boundaries and untrusted content are handled safely',()=>{
 for(const v of ['NaN','Infinity','1e9','','0x10'])assert.throws(()=>decimal(v,'Quantity'));
 assert.equal(decimal('1.125','Quantity'),1.125);
 assert.equal(escapeHtml('<img src=x onerror="alert(1)">'),'&lt;img src=x onerror=&quot;alert(1)&quot;&gt;');
 assert.equal(manager('staff'),false);assert.equal(stockOperator('staff'),true);
});
