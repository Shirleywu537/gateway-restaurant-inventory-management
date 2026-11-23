begin;

create function public.create_restaurant(p_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode='42501'; end if;
  insert into public.restaurants(name) values(trim(p_name)) returning id into v_id;
  insert into public.restaurant_members(restaurant_id,user_id,role) values(v_id,auth.uid(),'owner');
  return v_id;
end;
$$;

-- Creation is atomic; retrying the same request does not duplicate an order.
-- p_lines: [{"item_id":"uuid","quantity":20,"unit_price":2.50}]
create function public.create_purchase_order(
  p_restaurant_id uuid, p_supplier_id uuid, p_order_number text,
  p_lines jsonb, p_request_id uuid, p_expected_on date default null, p_notes text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_existing public.purchase_orders; v_payload jsonb;
  v_line record; v_item public.inventory_items;
begin
  if not private.has_restaurant_role(p_restaurant_id,array['owner','manager']) then
    raise exception 'Owner or manager access required' using errcode='42501';
  end if;
  if p_request_id is null or p_lines is null or jsonb_typeof(p_lines) <> 'array' then
    raise exception 'A request ID and a JSON array of lines are required';
  end if;
  if jsonb_array_length(p_lines) not between 1 and 100 then raise exception 'Use 1 to 100 order lines'; end if;
  v_payload := jsonb_build_object('supplier_id',p_supplier_id,'order_number',trim(p_order_number),
    'lines',p_lines,'expected_on',p_expected_on,'notes',p_notes);
  perform 1 from public.restaurants where id=p_restaurant_id for update;
  select * into v_existing from public.purchase_orders
    where restaurant_id=p_restaurant_id and request_id=p_request_id;
  if found then
    if v_existing.request_payload <> v_payload then raise exception 'Request ID reused with different content'; end if;
    return v_existing.id;
  end if;
  if not exists(select 1 from public.suppliers where id=p_supplier_id and restaurant_id=p_restaurant_id and is_active) then
    raise exception 'Choose an active supplier belonging to this restaurant';
  end if;
  insert into public.purchase_orders(restaurant_id,supplier_id,order_number,expected_on,notes,created_by,request_id,request_payload)
    values(p_restaurant_id,p_supplier_id,trim(p_order_number),p_expected_on,p_notes,auth.uid(),p_request_id,v_payload)
    returning id into v_id;
  for v_line in select * from jsonb_to_recordset(p_lines) as x(item_id uuid,quantity numeric,unit_price numeric) loop
    if v_line.quantity is null or v_line.quantity <= 0 or v_line.quantity='NaN'::numeric
      or v_line.quantity <> round(v_line.quantity,3) or v_line.unit_price is null
      or v_line.unit_price < 0 or v_line.unit_price='NaN'::numeric
      or v_line.unit_price <> round(v_line.unit_price,4) then
      raise exception 'Use positive quantities (3 decimals) and nonnegative prices (4 decimals)';
    end if;
    select * into v_item from public.inventory_items where id=v_line.item_id and restaurant_id=p_restaurant_id and is_active;
    if not found then raise exception 'Choose an active item belonging to this restaurant'; end if;
    insert into public.purchase_order_lines(restaurant_id,purchase_order_id,item_id,quantity_ordered,unit_price,base_unit)
      values(p_restaurant_id,v_id,v_item.id,v_line.quantity,v_line.unit_price,v_item.base_unit);
  end loop;
  return v_id;
end;
$$;

-- All app inventory changes lock the item row, serializing concurrent deductions.
-- Opening/adjustment: owner or manager. Usage/waste: owner, manager, or staff.
create function public.record_stock_movement(
  p_restaurant_id uuid, p_item_id uuid, p_type text, p_quantity_change numeric,
  p_reason text, p_request_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_balance numeric; v_existing public.stock_movements;
begin
  if not private.has_restaurant_role(p_restaurant_id,array['owner','manager','staff']) then
    raise exception 'Stock operator access required' using errcode='42501';
  end if;
  if p_type is null or p_type not in ('opening','usage','waste','adjustment') then
    raise exception 'Use opening, usage, waste, or adjustment; receive purchases with receive_purchase_order';
  end if;
  if p_type in ('opening','adjustment') and not private.has_restaurant_role(p_restaurant_id,array['owner','manager']) then
    raise exception 'Opening balances and adjustments require a manager' using errcode='42501';
  end if;
  if p_request_id is null or p_quantity_change is null or p_quantity_change=0 or p_quantity_change='NaN'::numeric
    or p_quantity_change <> round(p_quantity_change,3) then raise exception 'Supply a request ID and nonzero quantity with at most 3 decimals'; end if;
  if (p_type='opening' and p_quantity_change<0) or (p_type in ('usage','waste') and p_quantity_change>0) then
    raise exception 'Opening must add stock; usage and waste must subtract stock';
  end if;
  perform 1 from public.inventory_items where id=p_item_id and restaurant_id=p_restaurant_id and is_active for update;
  if not found then raise exception 'Active item not found in this restaurant'; end if;
  select * into v_existing from public.stock_movements where restaurant_id=p_restaurant_id and request_id=p_request_id;
  if found then
    if v_existing.item_id <> p_item_id or v_existing.movement_type <> p_type
      or v_existing.quantity_change <> p_quantity_change or v_existing.reason is distinct from trim(p_reason) then
      raise exception 'Request ID reused with different content';
    end if;
    return v_existing.id;
  end if;
  if p_type='opening' and exists(select 1 from public.stock_movements where restaurant_id=p_restaurant_id and item_id=p_item_id) then
    raise exception 'Opening balance must be the first movement for an item';
  end if;
  select coalesce(sum(quantity_change),0) into v_balance from public.stock_movements
    where restaurant_id=p_restaurant_id and item_id=p_item_id;
  if v_balance+p_quantity_change < 0 then raise exception 'Insufficient stock'; end if;
  insert into public.stock_movements(restaurant_id,item_id,movement_type,quantity_change,reason,request_id,created_by)
    values(p_restaurant_id,p_item_id,p_type,p_quantity_change,trim(p_reason),p_request_id,auth.uid()) returning id into v_id;
  return v_id;
end;
$$;

-- Each delivery can contain only part of an order. All inserts and status changes
-- commit together. A failed line rolls back the entire delivery.
-- p_lines: [{"purchase_order_line_id":"uuid","quantity":12}]
create function public.receive_purchase_order(
  p_restaurant_id uuid,p_order_id uuid,p_lines jsonb,p_request_id uuid,p_notes text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_order public.purchase_orders; v_existing public.goods_receipts;
  v_receipt uuid; v_line record; v_order_line public.purchase_order_lines;
  v_received numeric; v_receipt_line uuid; v_payload jsonb;
begin
  if not private.has_restaurant_role(p_restaurant_id,array['owner','manager']) then
    raise exception 'Owner or manager access required' using errcode='42501';
  end if;
  if p_request_id is null or p_lines is null or jsonb_typeof(p_lines) <> 'array' then
    raise exception 'A request ID and a JSON array of receipt lines are required';
  end if;
  if jsonb_array_length(p_lines) not between 1 and 100 then raise exception 'Use 1 to 100 receipt lines'; end if;
  v_payload := jsonb_build_object('order_id',p_order_id,'lines',p_lines,'notes',p_notes);
  select * into v_order from public.purchase_orders where id=p_order_id and restaurant_id=p_restaurant_id for update;
  if not found then raise exception 'Purchase order not found in this restaurant'; end if;
  select * into v_existing from public.goods_receipts where restaurant_id=p_restaurant_id and request_id=p_request_id;
  if found then
    if v_existing.request_payload <> v_payload then raise exception 'Request ID reused with different content'; end if;
    return v_existing.id;
  end if;
  if v_order.status not in ('ordered','partially_received') then raise exception 'Order is not open for receiving'; end if;
  -- Lock item rows in stable order so different orders cannot deadlock one another.
  perform 1 from public.inventory_items i where i.restaurant_id=p_restaurant_id and i.id in
    (select l.item_id from public.purchase_order_lines l where l.restaurant_id=p_restaurant_id and l.purchase_order_id=p_order_id)
    order by i.id for update;
  insert into public.goods_receipts(restaurant_id,purchase_order_id,received_by,notes,request_id,request_payload)
    values(p_restaurant_id,p_order_id,auth.uid(),p_notes,p_request_id,v_payload) returning id into v_receipt;
  for v_line in select * from jsonb_to_recordset(p_lines) as x(purchase_order_line_id uuid,quantity numeric) loop
    if v_line.quantity is null or v_line.quantity <= 0 or v_line.quantity='NaN'::numeric
      or v_line.quantity <> round(v_line.quantity,3) then raise exception 'Receipt quantities must be positive with at most 3 decimals'; end if;
    select * into v_order_line from public.purchase_order_lines
      where id=v_line.purchase_order_line_id and restaurant_id=p_restaurant_id and purchase_order_id=p_order_id;
    if not found then raise exception 'Receipt line does not belong to this purchase order'; end if;
    select coalesce(sum(quantity_received),0) into v_received from public.goods_receipt_lines
      where restaurant_id=p_restaurant_id and purchase_order_line_id=v_order_line.id;
    if v_received+v_line.quantity > v_order_line.quantity_ordered then raise exception 'Received quantity exceeds the ordered quantity'; end if;
    insert into public.goods_receipt_lines(restaurant_id,receipt_id,purchase_order_id,purchase_order_line_id,item_id,quantity_received)
      values(p_restaurant_id,v_receipt,p_order_id,v_order_line.id,v_order_line.item_id,v_line.quantity) returning id into v_receipt_line;
    insert into public.stock_movements(restaurant_id,item_id,movement_type,quantity_change,receipt_line_id,reason,request_id,created_by)
      values(p_restaurant_id,v_order_line.item_id,'receipt',v_line.quantity,v_receipt_line,
        'Received purchase order ' || v_order.order_number,gen_random_uuid(),auth.uid());
  end loop;
  update public.purchase_orders set status=case when exists(
    select 1 from public.purchase_order_lines l where l.restaurant_id=p_restaurant_id and l.purchase_order_id=p_order_id
      and l.quantity_ordered > (select coalesce(sum(r.quantity_received),0) from public.goods_receipt_lines r
        where r.restaurant_id=p_restaurant_id and r.purchase_order_line_id=l.id))
    then 'partially_received' else 'received' end where id=p_order_id;
  return v_receipt;
end;
$$;

create function public.cancel_purchase_order(p_restaurant_id uuid,p_order_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_order public.purchase_orders;
begin
  if not private.has_restaurant_role(p_restaurant_id,array['owner','manager']) then
    raise exception 'Owner or manager access required' using errcode='42501';
  end if;
  select * into v_order from public.purchase_orders where id=p_order_id and restaurant_id=p_restaurant_id for update;
  if not found then raise exception 'Order not found'; end if;
  if v_order.status='cancelled' then return; end if;
  if v_order.status <> 'ordered' or exists(select 1 from public.goods_receipts where restaurant_id=p_restaurant_id and purchase_order_id=p_order_id) then
    raise exception 'Only an unreceived order can be cancelled in v1';
  end if;
  update public.purchase_orders set status='cancelled' where id=p_order_id;
end;
$$;

revoke all on function public.create_restaurant(text) from public,anon,authenticated;
revoke all on function public.create_purchase_order(uuid,uuid,text,jsonb,uuid,date,text) from public,anon,authenticated;
revoke all on function public.record_stock_movement(uuid,uuid,text,numeric,text,uuid) from public,anon,authenticated;
revoke all on function public.receive_purchase_order(uuid,uuid,jsonb,uuid,text) from public,anon,authenticated;
revoke all on function public.cancel_purchase_order(uuid,uuid) from public,anon,authenticated;
grant execute on function public.create_restaurant(text) to authenticated;
grant execute on function public.create_purchase_order(uuid,uuid,text,jsonb,uuid,date,text) to authenticated;
grant execute on function public.record_stock_movement(uuid,uuid,text,numeric,text,uuid) to authenticated;
grant execute on function public.receive_purchase_order(uuid,uuid,jsonb,uuid,text) to authenticated;
grant execute on function public.cancel_purchase_order(uuid,uuid) to authenticated;
commit;
