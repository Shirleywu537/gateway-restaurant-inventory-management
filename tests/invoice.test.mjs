import test from 'node:test';
import assert from 'node:assert/strict';
import {invoiceMetadata,invoiceKey,convertInvoiceQuantity,suggestInvoiceLines,reviewedInvoiceLines,validateInvoiceHeader} from '../dist/invoice-core.js';
import {demoData} from '../dist/demo.js';
test('Invoice matching identifies explicit document/order references without guessing',()=>{
 const m=invoiceMetadata('Metro Produce\nInvoice number: INV-123\nPurchase order: DEMO-PO-001',demoData.purchase_orders,demoData.suppliers);
 assert.equal(m.number,'INV-123');assert.equal(m.orderId,'sample-order');assert.ok(m.supplierId);
 assert.equal(invoiceMetadata('Invoice\nDate 2026-11-16',[],[]).number,'');
 assert.equal(invoiceMetadata('CREDIT NOTE: C-1',[],[]).creditNote,true);
 assert.equal(invoiceKey(' inv / 123 '),invoiceKey('INV-123'));
});
test('Receipt suggestions use an explicit quantity and unit, never prices or ambiguous packs',()=>{
 const line=suggestInvoiceLines('Tomatoes 3 kg $2.50 $7.50','sample-order',demoData).find(r=>r.name==='Tomatoes');
 assert.equal(line.quantity,3);
 for(const text of ['Tomatoes 3 2.50 7.50','Tomatoes 2 x 5 kg','Tomatoes 3 kg\nTomatoes 2 kg','Tomatoes -3 kg','Tomatoes 3 kg 2 cases'])assert.equal(suggestInvoiceLines(text,'sample-order',demoData).find(r=>r.name==='Tomatoes').quantity,null,text);
});
test('Unit conversion requires compatible base units or an exact catalog pack unit',()=>{
 assert.equal(convertInvoiceQuantity(1500,'g','kg'),1.5);
 assert.equal(convertInvoiceQuantity(2,'l','ml'),2000);
 assert.equal(convertInvoiceQuantity(2,'case','kg',{purchase_unit:'case',base_units_per_pack:5}),10);
 assert.equal(convertInvoiceQuantity(2,'case','kg'),null);
 assert.equal(convertInvoiceQuantity(2,'lb','kg'),null);
 assert.equal(convertInvoiceQuantity(.1,'g','kg'),null);
});
test('Reviewed receiving needs explicit confirmation, rejects over-receipts and duplicate mappings',()=>{
 const p=[{purchase_order_line_id:'one',quantity_outstanding:8}];
 assert.throws(()=>reviewedInvoiceLines([{purchase_order_line_id:'one',quantity:3}],p,false),/Confirm/);
 assert.throws(()=>reviewedInvoiceLines([{purchase_order_line_id:'one',quantity:9}],p,true),/exceeds/);
 assert.throws(()=>reviewedInvoiceLines([{purchase_order_line_id:'one',quantity:1},{purchase_order_line_id:'one',quantity:1}],p,true),/once/);
 assert.deepEqual(reviewedInvoiceLines([{purchase_order_line_id:'one',quantity:3}],p,true),[{purchase_order_line_id:'one',quantity:3}]);
});
test('Invoice metadata validates identifiers and bounded PDF provenance',()=>{
 const file={sha256:'a'.repeat(64),size:12000,name:'invoice.pdf'};
 assert.doesNotThrow(()=>validateInvoiceHeader('INV-123',file));
 assert.throws(()=>validateInvoiceHeader('---',file));
 assert.throws(()=>validateInvoiceHeader('INV-123',{...file,size:21*1024*1024}));
 assert.throws(()=>validateInvoiceHeader('INV-123',{...file,sha256:'not-a-file-hash'}));
});
