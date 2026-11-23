import {SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY} from './config.js';
import {requestTicket} from './core.js';
export const db = window.supabase?.createClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY,{
  auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true,flowType:'implicit',storageKey:'gateway-inventory-auth'}
});
const columns={
  inventory_items:'id,restaurant_id,sku,name,category,base_unit,reorder_point,is_active',
  inventory_levels:'restaurant_id,item_id,sku,name,category,base_unit,reorder_point,is_active,quantity_on_hand,is_low_stock',
  suppliers:'id,restaurant_id,name,contact_name,contact_email,contact_phone,lead_time_days,is_active',
  supplier_items:'id,restaurant_id,supplier_id,item_id,supplier_sku,purchase_unit,base_units_per_pack,quoted_pack_price',
  purchase_orders:'id,restaurant_id,supplier_id,order_number,status,ordered_at,expected_on,notes,created_by',
  purchase_order_lines:'id,restaurant_id,purchase_order_id,item_id,quantity_ordered,unit_price,base_unit',
  purchase_order_progress:'restaurant_id,purchase_order_id,purchase_order_line_id,item_id,quantity_ordered,base_unit,unit_price,quantity_received,quantity_outstanding',
  goods_receipts:'id,restaurant_id,purchase_order_id,received_at,received_by,notes',
  goods_receipt_lines:'id,restaurant_id,receipt_id,purchase_order_id,purchase_order_line_id,item_id,quantity_received',
  restaurant_members:'restaurant_id,user_id,role,created_at'
};
export async function readAll(table,restaurantId){
  const result=[];
  for(let offset=0;offset<50000;offset+=1000){
    const order=table==='inventory_levels'?'item_id':table==='purchase_order_progress'?'purchase_order_line_id':table==='restaurant_members'?'user_id':'id';
    const {data,error}=await db.from(table).select(columns[table]).eq('restaurant_id',restaurantId).order(order).range(offset,offset+999);
    if(error) throw error;
    result.push(...data);
    if(data.length<1000) return result;
  }
  throw new Error('This workspace is too large to load in one view. Please contact the project administrator.');
}
export async function loadWorkspace(restaurantId){
  const tables=Object.keys(columns);
  const values=await Promise.all(tables.map(t=>readAll(t,restaurantId)));
  return Object.fromEntries(tables.map((t,i)=>[t,values[i]]));
}
export async function getTransactions(restaurantId,{page=0,item='',type=''}={}){
  let query=db.from('stock_movements').select('id,restaurant_id,item_id,movement_type,quantity_change,receipt_line_id,reason,created_by,created_at',{count:'exact'}).eq('restaurant_id',restaurantId);
  if(item) query=query.eq('item_id',item);
  if(type) query=query.eq('movement_type',type);
  const {data,error,count}=await query.order('created_at',{ascending:false}).order('id').range(page*25,page*25+24);
  if(error) throw error;
  return {rows:data,count};
}
export async function rpcWrite(userId,restaurantId,action,payload){
  const ticket=requestTicket(sessionStorage,`${userId}:${restaurantId}`,action,payload);
  const {data,error}=await db.rpc(action,{...payload,p_request_id:ticket.id});
  if(error){
    // SQL errors are definitive rollbacks. Transport failures retain the ticket for a safe retry.
    if(error.code && /^[0-9A-Z]{5}$/.test(error.code)) ticket.clear();
    throw error;
  }
  ticket.clear(); return data;
}
export async function saveRecord(table,id,restaurantId,values,isNew){
  const query=isNew ? db.from(table).insert({id,restaurant_id:restaurantId,...values}) : db.from(table).update(values).eq('id',id).eq('restaurant_id',restaurantId);
  const {data,error}=await query.select('id').single();
  if(error){
    if(isNew && error.code==='23505'){
      const prior=await db.from(table).select('id').eq('id',id).eq('restaurant_id',restaurantId).maybeSingle();
      if(!prior.error && prior.data) return prior.data;
    }
    throw error;
  }
  return data;
}
