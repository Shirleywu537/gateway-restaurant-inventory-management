import {escapeHtml as e,fmt,friendlyError,manager} from './core.js';
import {db,rpcWrite} from './data.js';
import {invoiceMetadata,suggestInvoiceLines,reviewedInvoiceLines,validateInvoiceHeader} from './invoice-core.js';
import {inspectPdf,scanPdf} from './invoice-scanner.js';
let active=null;
export function openInvoice({getContext,onSaved}){
 active?.stop();
 const ctx=getContext(),rid=ctx.restaurant?.id,uid=ctx.session?.user.id;
 if(ctx.portal!=='owner'||(!ctx.demo&&!manager(ctx.role)))return;
 const dialog=document.getElementById('dialog'),controller=new AbortController();
 let file,scan,meta,selected='',rows=[],busy=false,posting=false,token=0;
 const current=()=>active===flow&&!controller.signal.aborted&&getContext().portal==='owner'&&getContext().restaurant?.id===rid&&getContext().demo===ctx.demo&&(ctx.demo||getContext().session?.user.id===uid);
 const stop=()=>{token++;controller.abort();dialog.removeEventListener('close',stop);dialog.removeEventListener('cancel',cancel);};
 const cancel=event=>{if(posting)event.preventDefault();};
 const flow={stop};active=flow;
 dialog.addEventListener('close',stop,{once:true});dialog.addEventListener('cancel',cancel);
 dialog.className='invoice-dialog';
 const frame=body=>{dialog.innerHTML=`<div class="dialog-head"><div><span class="eyebrow">INVOICE TO RECEIVING</span><h2 id="dialog-title">Scan a supplier invoice</h2><p>1. Upload PDF &nbsp; → &nbsp; 2. Check quantities &nbsp; → &nbsp; 3. Confirm receipt</p></div><button class="icon-button" type="button" id="invoice-close" aria-label="Close invoice scanner">×</button></div>${body}`;dialog.querySelector('#invoice-close').onclick=()=>{if(!posting)dialog.close();};};
 const fail=error=>{if(!current())return;const box=dialog.querySelector('#invoice-error');if(box)box.textContent=friendlyError(error);};
 const unavailable=error=>['PGRST202','42P01','42883'].includes(error?.code)?new Error('Invoice receiving is not enabled on this database yet. No stock was changed.'):error;
 const upload=()=>{
  frame(`<div class="dialog-body"><div class="invoice-intro"><span class="invoice-symbol" aria-hidden="true">▤</span><h3>Turn an invoice into a checked delivery.</h3><p>Upload a supplier PDF, match it to a purchase order, and review what actually arrived. Scanning alone never changes stock.</p></div><label class="invoice-upload">Supplier invoice PDF<input id="invoice-file" type="file" accept="application/pdf,.pdf"><span>English invoices · Up to 20 MB and 10 pages</span></label><label class="check"><input id="invoice-force-ocr" type="checkbox">Use OCR on every page (for a mixed scan or a poor text layer)</label><p class="subtle-note">The PDF is processed in your browser and is not stored on the server. On confirmation, we save the checked receipt, invoice number, filename, and duplicate-check fingerprint. Keep your original invoice.</p>${ctx.demo?'<div class="demo-banner"><p><strong>Read-only sample</strong> · Try scanning a PDF and preview its effect. Nothing will be saved.</p></div>':''}<p><a class="quiet-link" href="./examples/sample-invoice.pdf" download>Download a fictional sample invoice</a> · <a class="quiet-link" href="./examples/sample-invoice-scan.pdf" download>Scanned sample PDF</a></p><div id="invoice-progress" role="status" aria-live="polite"></div><div id="invoice-error" class="form-error" role="alert"></div></div>`);
  dialog.querySelector('#invoice-file').onchange=async event=>{
   if(busy)return;const chosen=event.target.files[0];if(!chosen)return;busy=true;event.target.disabled=true;const run=++token;
   const status=message=>{if(current()&&run===token){const el=dialog.querySelector('#invoice-progress');if(el)el.textContent=message;}};
   try{
    file=await inspectPdf(chosen);if(!current())return;
    if(!ctx.demo){const {data,error}=await db.from('invoice_imports').select('invoice_number,created_at').eq('restaurant_id',rid).eq('file_sha256',file.sha256).maybeSingle();if(error)throw unavailable(error);if(data)throw new Error(`This PDF was already recorded as invoice ${data.invoice_number}. Check Receiving history. No stock was added.`);}
    scan=await scanPdf(file,{signal:controller.signal,progress:status,forceOcr:dialog.querySelector('#invoice-force-ocr').checked});
    if(!current()||run!==token)return;
    meta=invoiceMetadata(scan.text,ctx.data.purchase_orders,ctx.data.suppliers);selected=meta.orderId;review();
   }catch(error){if(error.name!=='AbortError')fail(error);}finally{busy=false;if(current()){const input=dialog.querySelector('#invoice-file');if(input)input.disabled=false;}}
  };
 };
 const review=()=>{
  const orders=ctx.data.purchase_orders.filter(o=>['ordered','partially_received'].includes(o.status));
  if(!orders.some(o=>o.id===selected))selected='';
  const order=orders.find(o=>o.id===selected),supplier=ctx.data.suppliers.find(s=>s.id===order?.supplier_id);
  rows=suggestInvoiceLines(scan.text,selected,ctx.data).filter(l=>Number(l.quantity_outstanding)>0);
  frame(`<form id="invoice-review-form"><div class="dialog-body"><div class="invoice-file-summary"><strong>${e(file.name)}</strong><span class="tag">${scan.pages.length} page${scan.pages.length>1?'s':''} · ${scan.method==='text'?'PDF text':scan.method==='mixed'?'Text + OCR':'OCR'}</span></div>${meta.creditNote?'<div class="error-banner">This appears to be a credit note. Credit notes and returns cannot be used to receive stock.</div>':''}${ctx.demo?'<div class="demo-banner"><p><strong>Read-only sample.</strong> The final step previews changes without saving.</p></div>':''}<div class="invoice-review-grid"><section><div class="form-grid"><label class="field">Invoice number<input name="invoice_number" maxlength="100" value="${e(meta.number)}" required placeholder="Check the supplier’s invoice number"></label><label class="field">Purchase order<select id="invoice-order" required><option value="">Choose the matching purchase order</option>${orders.map(o=>`<option value="${e(o.id)}" ${o.id===selected?'selected':''}>${e(o.order_number)} · ${e(ctx.data.suppliers.find(s=>s.id===o.supplier_id)?.name)}</option>`).join('')}</select></label></div><p class="subtle-note">${order?`Supplier: <strong>${e(supplier?.name)}</strong>. ${meta.supplierId&&meta.supplierId!==order.supplier_id?'The detected supplier differs — check your order selection carefully.':''}`:'Select an open order. If none matches, create a purchase order first; scanning does not create orders or ingredients.'}</p><div class="invoice-review-note">Check every quantity and unit against the physical delivery. Invoiced goods may not have arrived yet. Leave 0 for anything not received. Scans can misread numbers.</div><div id="invoice-rows">${rows.map((r,index)=>`<section class="invoice-line" data-line="${e(r.purchase_order_line_id)}"><div class="row spread"><h3>${e(r.name)}</h3><span class="tag">${fmt(r.quantity_outstanding)} ${e(r.base_unit)} outstanding</span></div><p class="invoice-source">${e(r.source||'No matching invoice text detected.')}</p><p class="subtle-note">${e(r.note)}</p><label class="field">Received now — ${e(r.name)} (${e(r.base_unit)})<input name="invoice_quantity_${index}" type="number" min="0" max="${Number(r.quantity_outstanding)}" step="0.001" value="${r.quantity??0}" required></label></section>`).join('')}</div><label class="field">Delivery notes<textarea name="invoice_notes" maxlength="1000" placeholder="Optional notes about quantities, units, or damaged goods"></textarea></label><label class="check invoice-confirm"><input id="invoice-confirmed" type="checkbox" required>I checked the supplier, invoice number, ingredient units, and quantities actually received. These goods have not already been recorded through manual Receiving.</label><p class="subtle-note">One invoice can be recorded once against one purchase order. For multiple deliveries, use a separate delivery invoice or manual Receiving. Taxes, prices, and invoice totals do not change stock or accounting records.</p></section><aside class="invoice-preview"><label class="field">PDF preview page<select id="invoice-preview-page">${scan.pages.map(p=>`<option value="${p.number}">Page ${p.number} · ${p.method==='ocr'?'OCR':'Text'}</option>`).join('')}</select></label><img id="invoice-preview-img" alt="Uploaded invoice page preview" src="${scan.pages[0].preview}"><details><summary>Extracted text — check against the PDF</summary><pre>${e(scan.text.slice(0,100000))}</pre></details><p class="subtle-note">${scan.pages.some(p=>p.confidence!==null&&p.confidence<80)?'Some OCR text has low confidence. Carefully review the preview and enter corrected quantities.':''}</p></aside></div><div id="invoice-error" class="form-error" role="alert"></div></div><div class="dialog-footer"><button type="button" class="btn" id="invoice-restart">Choose another PDF</button><button class="btn primary" type="submit" ${!rows.length||meta.creditNote?'disabled':''}>${ctx.demo?'Preview stock changes':'Confirm receipt & update stock'}</button></div></form>`);
  dialog.querySelector('#invoice-order').onchange=event=>{meta.number=dialog.querySelector('[name=invoice_number]').value;selected=event.target.value;review();};
  dialog.querySelector('#invoice-preview-page').onchange=event=>{dialog.querySelector('#invoice-preview-img').src=scan.pages[Number(event.target.value)-1].preview;};
  dialog.querySelector('#invoice-restart').onclick=upload;
  dialog.querySelector('#invoice-review-form').onsubmit=async event=>{
   event.preventDefault();if(posting||!current())return;
   const form=event.target,button=form.querySelector('[type=submit]');
   try{
    if(meta.creditNote)throw new Error('Credit notes cannot be used to receive stock.');
    const values=new FormData(form),number=String(values.get('invoice_number')||'').trim();validateInvoiceHeader(number,file);
    const inputs=[...form.querySelectorAll('.invoice-line')].map(el=>({purchase_order_line_id:el.dataset.line,quantity:el.querySelector('input').value}));
    const checked=reviewedInvoiceLines(inputs,ctx.data.purchase_order_progress.filter(l=>l.purchase_order_id===selected),form.querySelector('#invoice-confirmed').checked);
    meta.number=number;
    if(ctx.demo){previewChanges(checked,number);return;}
    if(!manager(getContext().role))throw new Error('Owner or manager access required.');
    posting=true;form.querySelectorAll('input,select,textarea,button').forEach(el=>el.disabled=true);dialog.querySelector('#invoice-close').disabled=true;form.setAttribute('aria-busy','true');
    if(!current())return;
    await rpcWrite(uid,rid,'receive_invoice',{p_restaurant_id:rid,p_order_id:order.id,p_supplier_id:order.supplier_id,p_invoice_number:number,p_file_sha256:file.sha256,p_file_name:file.name,p_file_size:file.size,p_extraction_method:scan.method,p_lines:checked,p_notes:String(values.get('invoice_notes')||'').trim()||null});
    posting=false;dialog.close();await onSaved();
   }catch(error){fail(unavailable(error));}finally{posting=false;form.querySelectorAll('input,select,textarea,button').forEach(el=>el.disabled=false);form.removeAttribute('aria-busy');const close=dialog.querySelector('#invoice-close');if(close)close.disabled=false;}
  };
 };
 const previewChanges=(lines,number)=>{
  const remaining=ctx.data.purchase_order_progress.filter(l=>l.purchase_order_id===selected).map(p=>Number(p.quantity_outstanding)-(lines.find(l=>l.purchase_order_line_id===p.purchase_order_line_id)?.quantity||0));
  frame(`<div class="dialog-body"><span class="tag">Preview only · nothing saved</span><h3 style="margin:18px 0">Invoice ${e(number)}</h3><div class="table-wrap"><table><thead><tr><th>Ingredient</th><th>Current stock</th><th>Receive</th><th>Would become</th></tr></thead><tbody>${lines.map(l=>{const p=rows.find(r=>r.purchase_order_line_id===l.purchase_order_line_id),level=ctx.data.inventory_levels.find(i=>i.item_id===p.item_id);return `<tr><td>${e(p.name)}</td><td>${fmt(level.quantity_on_hand)} ${e(p.base_unit)}</td><td>+${fmt(l.quantity)} ${e(p.base_unit)}</td><td><strong>${fmt(Number(level.quantity_on_hand)+l.quantity)} ${e(p.base_unit)}</strong></td></tr>`;}).join('')}</tbody></table></div><p class="subtle-note">Order would become <strong>${remaining.some(n=>n>0)?'Partially received':'Received'}</strong>. One delivery with ${lines.length} item line${lines.length>1?'s':''} would be added to Receiving.</p><p>The sample remains unchanged. Sign in as an owner or manager to save a real receipt.</p></div><div class="dialog-footer"><button class="btn" type="button" id="invoice-back">Back to review</button><button class="btn primary" type="button" id="invoice-done">Done</button></div>`);
  dialog.querySelector('#invoice-back').onclick=review;dialog.querySelector('#invoice-done').onclick=()=>dialog.close();
 };
 upload();if(!dialog.open)dialog.showModal();
}
