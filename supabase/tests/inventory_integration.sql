-- Execute as postgres in SQL Editor. Fixtures, users, and mutations are rolled back.
begin;
do $$
declare u uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); staff uuid:=gen_random_uuid(); viewer uuid:=gen_random_uuid();
  r uuid; r2 uuid; item uuid; item2 uuid; supplier uuid; supplier2 uuid; po uuid; line uuid; delivery uuid;
  rid uuid; result_id uuid; req uuid; request_lines jsonb; n bigint; qty numeric; rejected boolean; checked integer:=0;
begin
  insert into auth.users(id,email,aud,role) values
    (u,'inventory-owner-'||u||'@example.invalid','authenticated','authenticated'),
    (outsider,'inventory-other-'||outsider||'@example.invalid','authenticated','authenticated'),
    (staff,'inventory-staff-'||staff||'@example.invalid','authenticated','authenticated'),
    (viewer,'inventory-viewer-'||viewer||'@example.invalid','authenticated','authenticated');
  perform set_config('request.jwt.claim.sub',u::text,true);
  execute 'set local role authenticated';
  r:=public.create_restaurant('Temporary integration test A');
  insert into public.inventory_items(restaurant_id,sku,name,base_unit,reorder_point)
    values(r,'TEST','Test tomatoes','kg',10) returning id into item;
  insert into public.suppliers(restaurant_id,name) values(r,'Test supplier A') returning id into supplier;
  execute 'reset role';
  insert into public.restaurant_members(restaurant_id,user_id,role) values(r,staff,'staff'),(r,viewer,'viewer');
  perform set_config('request.jwt.claim.sub',outsider::text,true);
  execute 'set local role authenticated';
  r2:=public.create_restaurant('Temporary integration test B');
  insert into public.inventory_items(restaurant_id,sku,name,base_unit) values(r2,'OTHER','Other item','kg') returning id into item2;
  insert into public.suppliers(restaurant_id,name) values(r2,'Test supplier B') returning id into supplier2;
  select count(*) into n from public.restaurants;
  if n<>1 then raise exception 'FAIL: restaurant isolation'; end if;
  select count(*) into n from public.inventory_levels;
  if n<>1 then raise exception 'FAIL: view isolation'; end if;
  checked:=checked+1;
  rejected:=false;
  begin perform public.record_stock_movement(r,item,'opening',10,'Forbidden',gen_random_uuid());
  exception when insufficient_privilege then rejected:=true; end;
  if not rejected then raise exception 'FAIL: cross-restaurant RPC'; end if;
  checked:=checked+1;

  execute 'reset role';
  perform set_config('request.jwt.claim.sub',u::text,true);
  execute 'set local role authenticated';
  rejected:=false;
  begin insert into public.supplier_items(restaurant_id,supplier_id,item_id,base_units_per_pack,quoted_pack_price)
    values(r,supplier,item2,1,1);
  exception when foreign_key_violation then rejected:=true; end;
  if not rejected then raise exception 'FAIL: cross-restaurant foreign key'; end if;
  checked:=checked+1;

  req:=gen_random_uuid();
  rid:=public.record_stock_movement(r,item,'opening',10,'Test opening',req);
  result_id:=public.record_stock_movement(r,item,'opening',10,'Test opening',req);
  select quantity_on_hand into qty from public.inventory_levels where item_id=item;
  if rid<>result_id or qty<>10 then raise exception 'FAIL: opening retry'; end if;
  checked:=checked+1;
  rejected:=false;
  begin perform public.record_stock_movement(r,item,'opening',11,'Test opening',req);
  exception when raise_exception then rejected:=true; end;
  if not rejected then raise exception 'FAIL: request ID content conflict'; end if;
  checked:=checked+1;

  req:=gen_random_uuid(); request_lines:=jsonb_build_array(jsonb_build_object('item_id',item,'quantity',20,'unit_price',2.5));
  po:=public.create_purchase_order(r,supplier,'TEST-PO',request_lines,req);
  result_id:=public.create_purchase_order(r,supplier,'TEST-PO',request_lines,req);
  select quantity_on_hand into qty from public.inventory_levels where item_id=item;
  if po<>result_id or qty<>10 then raise exception 'FAIL: ordering changed stock or duplicated order'; end if;
  checked:=checked+1;
  select id into line from public.purchase_order_lines where purchase_order_id=po;
  req:=gen_random_uuid(); request_lines:=jsonb_build_array(jsonb_build_object('purchase_order_line_id',line,'quantity',12));
  delivery:=public.receive_purchase_order(r,po,request_lines,req);
  result_id:=public.receive_purchase_order(r,po,request_lines,req);
  select quantity_on_hand into qty from public.inventory_levels where item_id=item;
  if delivery<>result_id or qty<>22 or (select status from public.purchase_orders where id=po)<>'partially_received' then
    raise exception 'FAIL: partial receiving or receipt retry'; end if;
  checked:=checked+1;

  rejected:=false;
  begin perform public.receive_purchase_order(r,po,jsonb_build_array(jsonb_build_object('purchase_order_line_id',line,'quantity',9)),gen_random_uuid());
  exception when raise_exception then rejected:=true; end;
  select count(*) into n from public.goods_receipts where purchase_order_id=po;
  if not rejected or n<>1 then raise exception 'FAIL: over-receipt rollback'; end if;
  checked:=checked+1;

  rejected:=false;
  begin perform public.receive_purchase_order(r,po,jsonb_build_array(
    jsonb_build_object('purchase_order_line_id',line,'quantity',1),
    jsonb_build_object('purchase_order_line_id',gen_random_uuid(),'quantity',1)),gen_random_uuid());
  exception when raise_exception then rejected:=true; end;
  select quantity_on_hand into qty from public.inventory_levels where item_id=item;
  select count(*) into n from public.goods_receipts where purchase_order_id=po;
  if not rejected or qty<>22 or n<>1 then raise exception 'FAIL: multi-line receipt atomicity'; end if;
  checked:=checked+1;

  perform public.receive_purchase_order(r,po,jsonb_build_array(jsonb_build_object('purchase_order_line_id',line,'quantity',8)),gen_random_uuid());
  if (select status from public.purchase_orders where id=po)<>'received' then raise exception 'FAIL: completed order status'; end if;
  checked:=checked+1;
  rejected:=false;
  begin perform public.record_stock_movement(r,item,'usage',-100,'Too much',gen_random_uuid());
  exception when raise_exception then rejected:=true; end;
  if not rejected then raise exception 'FAIL: negative-stock rejection'; end if;
  checked:=checked+1;

  rejected:=false;
  begin update public.stock_movements set quantity_change=999 where id=rid;
  exception when insufficient_privilege then rejected:=true; end;
  if not rejected then raise exception 'FAIL: direct ledger update allowed'; end if;
  checked:=checked+1;
  rejected:=false;
  begin insert into public.stock_movements(restaurant_id,item_id,movement_type,quantity_change,reason,request_id)
    values(r,item,'adjustment',1,'Direct insert',gen_random_uuid());
  exception when insufficient_privilege then rejected:=true; end;
  if not rejected then raise exception 'FAIL: direct ledger insert allowed'; end if;
  checked:=checked+1;

  execute 'reset role';
  perform set_config('request.jwt.claim.sub',staff::text,true);
  execute 'set local role authenticated';
  perform public.record_stock_movement(r,item,'usage',-4,'Kitchen test',gen_random_uuid());
  perform public.record_stock_movement(r,item,'waste',-1,'Waste test',gen_random_uuid());
  select quantity_on_hand into qty from public.inventory_levels where item_id=item;
  if qty<>25 then raise exception 'FAIL: staff usage and waste'; end if;
  rejected:=false;
  begin perform public.record_stock_movement(r,item,'adjustment',1,'Forbidden',gen_random_uuid());
  exception when insufficient_privilege then rejected:=true; end;
  if not rejected then raise exception 'FAIL: staff adjustment allowed'; end if;
  checked:=checked+1;

  execute 'reset role';
  perform set_config('request.jwt.claim.sub',viewer::text,true);
  execute 'set local role authenticated';
  select quantity_on_hand into qty from public.inventory_levels where item_id=item;
  if qty<>25 then raise exception 'FAIL: viewer read'; end if;
  rejected:=false;
  begin perform public.record_stock_movement(r,item,'usage',-1,'Forbidden',gen_random_uuid());
  exception when insufficient_privilege then rejected:=true; end;
  if not rejected then raise exception 'FAIL: viewer write allowed'; end if;
  checked:=checked+1;

  execute 'reset role';
  perform set_config('request.jwt.claim.sub','',true);
  execute 'set local role anon';
  rejected:=false;
  begin select count(*) into n from public.inventory_items;
  exception when insufficient_privilege then rejected:=true; end;
  if not rejected then raise exception 'FAIL: anonymous table read allowed'; end if;
  rejected:=false;
  begin perform public.create_restaurant('Forbidden');
  exception when insufficient_privilege then rejected:=true; end;
  if not rejected then raise exception 'FAIL: anonymous RPC allowed'; end if;
  checked:=checked+1;
  execute 'reset role';
  select count(*) into n from pg_class c join pg_namespace ns on ns.oid=c.relnamespace
    where ns.nspname='public' and c.relkind='r' and c.relname in ('restaurants','restaurant_members',
    'inventory_items','suppliers','supplier_items','purchase_orders','purchase_order_lines','goods_receipts','goods_receipt_lines','stock_movements')
    and c.relrowsecurity;
  if n<>10 then raise exception 'FAIL: RLS missing'; end if;
  checked:=checked+1;
  if checked<>17 then raise exception 'FAIL: incomplete test run %',checked; end if;
end;
$$;
rollback;
select 'PASS: 17 integration checks; all temporary users and data rolled back.' as validation_result;
