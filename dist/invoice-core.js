import {receiptLines,decimal} from './core.js';
export const MAX_PDF_BYTES=20*1024*1024,MAX_PDF_PAGES=10;
export const invoiceKey=value=>String(value||'').trim().toUpperCase().replace(/[^A-Z0-9]/g,'');
const words=value=>String(value||'').toLowerCase().replace(/[^a-z0-9]+/g,' ').trim();
const contains=(text,value)=>value&&(` ${words(text)} `).includes(` ${words(value)} `);
export function invoiceMetadata(text,orders,suppliers){
 const number=String(text).match(/\binvoice\s*(?:number|no\.?|#|id)?\s*[:#-]?\s*([A-Z0-9][A-Z0-9_/-]*\d[A-Z0-9_/-]*|\d+)\b/i)?.[1]||'';
 const matchingOrders=orders.filter(o=>contains(text,o.order_number));
 const matchingSuppliers=suppliers.filter(s=>contains(text,s.name));
 return {number,orderId:matchingOrders.length===1?matchingOrders[0].id:'',supplierId:matchingSuppliers.length===1?matchingSuppliers[0].id:'',creditNote:/\bcredit\s+(?:note|memo)\b/i.test(text)};
}
export function convertInvoiceQuantity(quantity,unit,baseUnit,catalog){
 const aliases={kgs:'kg',kilogram:'kg',kilograms:'kg',grams:'g',gram:'g',litre:'l',litres:'l',liter:'l',liters:'l',mls:'ml',ea:'each',pcs:'each',pc:'each',units:'each'};
 const u=aliases[unit.toLowerCase()]||unit.toLowerCase();let factor;
 if(u===baseUnit)factor=1;
 else if(u==='g'&&baseUnit==='kg'||u==='ml'&&baseUnit==='l')factor=.001;
 else if(u==='kg'&&baseUnit==='g'||u==='l'&&baseUnit==='ml')factor=1000;
 else if(catalog&&words(u)===words(catalog.purchase_unit))factor=Number(catalog.base_units_per_pack);
 else return null;
 const n=Number(quantity)*factor;
 if(!Number.isFinite(n)||n<=0||Math.abs(n*1000-Math.round(n*1000))>1e-7)return null;
 return Math.round(n*1000)/1000;
}
export function suggestInvoiceLines(text,orderId,data){
 const order=data.purchase_orders.find(o=>o.id===orderId);
 if(!order)return [];
 const raw=String(text).split(/\r?\n/).map(x=>x.trim()).filter(Boolean);
 return data.purchase_order_progress.filter(l=>l.purchase_order_id===orderId).map(line=>{
  const item=data.inventory_items.find(i=>i.id===line.item_id),catalog=data.supplier_items.find(c=>c.item_id===line.item_id&&c.supplier_id===order.supplier_id);
  const matches=raw.filter(r=>/\d/.test(r)&&[item?.name,item?.sku,catalog?.supplier_sku].filter(Boolean).some(v=>contains(r,v)));
  let quantity=null,detected='',note=matches.length>1?'Multiple matches — enter the actual received quantity.':'No reliable quantity — enter it manually.';
  if(matches.length===1){
   const r=matches[0];const tokens=[...r.matchAll(/(?<![\d.,$-])(\d+(?:,\d{3})*(?:\.\d+)?)\s*(kg(?:s)?|kilograms?|grams?|g|mls?|litres?|liters?|l|each|ea|pcs?|units?|cases?|packs?|boxes?|bags?)\b/gi)];
   // More than one quantity/unit pair can be a pack-size expression. Never guess.
   if(tokens.length===1&&!/\b\d+\s*[x×]\s*\d+/i.test(r)){
    const [,q,u]=tokens[0];detected=`${q} ${u}`;
    quantity=convertInvoiceQuantity(q.replaceAll(',',''),u,line.base_unit,catalog);
    if(quantity!==null)note=`Suggested ${quantity} ${line.base_unit} — check against the delivery.`;
    else note='Unit needs checking — enter the quantity in the ingredient’s base unit.';
   }
  }
  return {...line,name:item?.name||'Ingredient',source:matches.join('\n'),detected,quantity,note};
 });
}
export function reviewedInvoiceLines(rows,progress,confirmed){
 if(!confirmed)throw new Error('Confirm the supplier, invoice number, units, and goods actually received.');
 return receiptLines(rows,progress);
}
export function validateInvoiceHeader(number,file){
 if(!invoiceKey(number)||number.trim().length>100)throw new Error('Enter the supplier’s invoice number (up to 100 characters).');
 if(!file||!(/^[a-f0-9]{64}$/).test(file.sha256))throw new Error('Scan a valid PDF before confirming.');
 decimal(file.size,'File size',{min:1,max:MAX_PDF_BYTES,places:0});
 if(!file.name||file.name.length>255)throw new Error('Use a PDF filename of 255 characters or fewer.');
}
