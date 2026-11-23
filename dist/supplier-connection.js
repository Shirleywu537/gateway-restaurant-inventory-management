import {friendlyError} from './core.js';

export function supplierConnectionCode(value,{required=false}={}){
  const code=String(value||'').trim();
  if(!code&&!required)return '';
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(code))throw new Error('Enter the supplier’s full connection code, or leave it blank to save without connecting.');
  return code.toLowerCase();
}

// Keep the same draft ID across retries: a failed request must not create another supplier.
export async function saveSupplierWithConnection({draft,restaurantId,values,code,saveSupplier,requestConnection}){
  const accountId=supplierConnectionCode(code);
  if(accountId&&!values.is_active)throw new Error('Keep Active supplier selected to request a connection.');
  await saveSupplier(draft.id,restaurantId,values,draft.isNew);
  draft.isNew=false;
  draft.saved=true;
  if(!accountId)return {connectionRequested:false};
  try{
    await requestConnection(restaurantId,draft.id,accountId);
  }catch(error){
    throw new Error(`Supplier saved, but the connection request could not be confirmed. ${friendlyError(error)} Check the code and retry in this form; this will update the same supplier. Leave the code blank to finish without another connection request.`);
  }
  return {connectionRequested:true};
}
