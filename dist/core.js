export const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const units = ['kg','g','l','ml','each'];
export const manager = role => ['owner','manager'].includes(role);
export const stockOperator = role => ['owner','manager','staff'].includes(role);
export const fmt = value => new Intl.NumberFormat('en-US',{maximumFractionDigits:3}).format(Number(value || 0));
export function decimal(value, label, {min=0, max=99999999999.999, places=3, positive=false}={}) {
  const raw=String(value ?? '').trim();
  if(!/^-?\d+(\.\d+)?$/.test(raw)) throw new Error(`${label} must be a number.`);
  if((raw.split('.')[1] || '').length > places) throw new Error(`${label} can have at most ${places} decimal places.`);
  const n=Number(raw);
  if(!Number.isFinite(n) || n < min || n > max || (positive && n===0)) throw new Error(`${label} must be ${positive?'greater than':'at least'} ${min} and no more than ${max}.`);
  return n;
}
export function orderLines(rows, items) {
  if(!rows.length || rows.length>100) throw new Error('Add between 1 and 100 ingredients.');
  const seen=new Set();
  return rows.map(row=>{
    const item=items.find(i=>i.id===row.item_id && i.is_active);
    if(!item) throw new Error('Choose an active ingredient for every line.');
    if(seen.has(item.id)) throw new Error('Use one line per ingredient; combine duplicate quantities.');
    seen.add(item.id);
    return {item_id:item.id,quantity:decimal(row.quantity,'Order quantity',{positive:true}),unit_price:decimal(row.unit_price,'Unit price',{places:4,max:9999999999.9999})};
  });
}
export function receiptLines(rows, progress) {
  const lines=[];
  for(const row of rows){
    const q=decimal(row.quantity || '0','Received quantity');
    if(q===0) continue;
    const p=progress.find(p=>p.purchase_order_line_id===row.purchase_order_line_id);
    if(!p || q>Number(p.quantity_outstanding)) throw new Error('A received quantity exceeds the amount still outstanding.');
    if(lines.some(l=>l.purchase_order_line_id===row.purchase_order_line_id)) throw new Error('Each order line can appear only once.');
    lines.push({purchase_order_line_id:row.purchase_order_line_id,quantity:q});
  }
  if(!lines.length) throw new Error('Enter a received quantity for at least one ingredient.');
  return lines;
}
export function movementChange(type,value,role){
  if(!stockOperator(role)) throw new Error('Your role cannot record stock transactions.');
  if(!['opening','usage','waste','adjustment'].includes(type)) throw new Error('Choose a supported transaction type.');
  if(['opening','adjustment'].includes(type) && !manager(role)) throw new Error('Only owners and managers can enter opening stock or adjustments.');
  const q=decimal(value,'Quantity',{min:type==='adjustment'?-99999999999.999:0,positive:true});
  return ['usage','waste'].includes(type)?-q:q;
}
export function requestTicket(storage,scope,action,payload){
  const key=`gateway-request:${scope}:${action}`;
  let old=null;
  try{old=JSON.parse(storage.getItem(key));}catch{}
  const serialized=JSON.stringify(payload);
  if(old && old.payload!==serialized) throw new Error('An earlier submission is still unconfirmed. Retry its original details before submitting a different transaction.');
  const ticket=old || {id:crypto.randomUUID(),payload:serialized};
  try{storage.setItem(key,JSON.stringify(ticket));}catch{}
  return {id:ticket.id,clear:()=>{try{storage.removeItem(key);}catch{}}};
}
export function friendlyError(error){
  const message=String(error?.message || error || 'Something went wrong.');
  if(error?.code==='23505') return 'This record already exists. Check the SKU, order number, or supplier–ingredient combination.';
  if(error?.code==='42501' || /permission denied/i.test(message)) return 'Your account does not have permission for this action. Check your restaurant and role.';
  if(/Failed to fetch|NetworkError|Load failed/i.test(message)) return 'The connection was interrupted. A submission may have reached the database; retry the same details before creating another entry.';
  if(/Invalid login credentials/i.test(message)) return 'The email or password is incorrect, or this account has not been created yet.';
  if(/Email not confirmed/i.test(message)) return 'Please confirm your email before signing in.';
  return message;
}
