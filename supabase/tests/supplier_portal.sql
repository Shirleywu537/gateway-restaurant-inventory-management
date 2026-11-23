-- Apply migration first, or include this test body before ROLLBACK in a dry run.
-- All temporary identities and fixtures are discarded by the outer transaction.
begin;
do $$
declare owner_id uuid:=gen_random_uuid(); supplier_user uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
 r uuid; r2 uuid; i uuid; private_i uuid; s uuid; other_s uuid; a uuid; outsider_a uuid; conn uuid;
 po uuid; line_id uuid; result jsonb; rejected boolean; count_value bigint; checks integer:=0; req uuid:=gen_random_uuid();
begin
 insert into auth.users(id,email,aud,role) values
 (owner_id,'portal-owner-'||owner_id||'@example.invalid','authenticated','authenticated'),
 (supplier_user,'portal-supplier-'||supplier_user||'@example.invalid','authenticated','authenticated'),
 (outsider,'portal-other-'||outsider||'@example.invalid','authenticated','authenticated');
 perform set_config('request.jwt.claim.sub',supplier_user::text,true);execute 'set local role authenticated';
 a:=public.create_supplier_account('Test produce business',req);
 if public.create_supplier_account('Test produce business',req)<>a then raise exception 'FAIL: supplier creation retry';end if;checks:=checks+1;
 if jsonb_array_length(public.supplier_portal_accounts())<>1 then raise exception 'FAIL: supplier accounts';end if;checks:=checks+1;
 execute 'reset role';perform set_config('request.jwt.claim.sub',outsider::text,true);execute 'set local role authenticated';
 outsider_a:=public.create_supplier_account('Other supplier business',gen_random_uuid());
 rejected:=false;begin perform public.supplier_portal_snapshot(a);exception when insufficient_privilege then rejected:=true;end;
 if not rejected then raise exception 'FAIL: outsider account access';end if;checks:=checks+1;
 execute 'reset role';perform set_config('request.jwt.claim.sub',owner_id::text,true);execute 'set local role authenticated';
 r:=public.create_restaurant('Portal test restaurant');r2:=public.create_restaurant('Unconnected restaurant');
 insert into public.inventory_items(restaurant_id,sku,name,base_unit,reorder_point) values(r,'ORDERED','Tomatoes','kg',10) returning id into i;
 insert into public.inventory_items(restaurant_id,sku,name,base_unit,reorder_point) values(r,'PRIVATE','Private kitchen item','kg',99) returning id into private_i;
 insert into public.suppliers(restaurant_id,name) values(r,'Produce business') returning id into s;
 insert into public.suppliers(restaurant_id,name) values(r,'Other private supplier') returning id into other_s;
 perform public.record_stock_movement(r,i,'opening',100,'Internal opening',gen_random_uuid());
 po:=public.create_purchase_order(r,s,'PORTAL-PO',jsonb_build_array(jsonb_build_object('item_id',i,'quantity',20,'unit_price',2.5)),gen_random_uuid(),null,'PRIVATE INTERNAL NOTE');
 perform public.create_purchase_order(r,other_s,'PRIVATE-PO',jsonb_build_array(jsonb_build_object('item_id',private_i,'quantity',5,'unit_price',10)),gen_random_uuid());
 select id into line_id from public.purchase_order_lines where purchase_order_id=po;
 perform public.receive_purchase_order(r,po,jsonb_build_array(jsonb_build_object('purchase_order_line_id',line_id,'quantity',12)),gen_random_uuid(),'PRIVATE DELIVERY NOTE');
 conn:=public.request_supplier_connection(r,s,a);
 if public.request_supplier_connection(r,s,a)<>conn then raise exception 'FAIL: connection retry';end if;checks:=checks+1;
 rejected:=false;begin perform public.respond_supplier_connection(conn,'accepted');exception when insufficient_privilege then rejected:=true;end;
 if not rejected then raise exception 'FAIL: restaurant self-accept';end if;checks:=checks+1;
 execute 'reset role';perform set_config('request.jwt.claim.sub',supplier_user::text,true);execute 'set local role authenticated';
 result:=public.supplier_portal_snapshot(a);
 if jsonb_array_length(result->'orders')<>0 or jsonb_array_length(result->'connections')<>1 then raise exception 'FAIL: pending exposes orders';end if;checks:=checks+1;
 perform public.respond_supplier_connection(conn,'accepted');result:=public.supplier_portal_snapshot(a);
 if jsonb_array_length(result->'orders')<>1 or jsonb_array_length(result->'lines')<>1 or jsonb_array_length(result->'deliveries')<>1 then raise exception 'FAIL: supplier order scope';end if;checks:=checks+1;
 if (result->'lines'->0->>'quantity_outstanding')::numeric<>8 then raise exception 'FAIL: receipt progress';end if;checks:=checks+1;
 if result::text ~ 'PRIVATE|reorder_point|quantity_on_hand|stock_movements|Private kitchen|Unconnected restaurant' then raise exception 'FAIL: private data projected';end if;checks:=checks+1;
 select count(*) into count_value from public.inventory_items;
 if count_value<>0 then raise exception 'FAIL: direct ingredient exposure';end if;
 select count(*) into count_value from public.inventory_levels;
 if count_value<>0 then raise exception 'FAIL: direct stock exposure';end if;
 select count(*) into count_value from public.stock_movements;
 if count_value<>0 then raise exception 'FAIL: ledger exposure';end if;
 select count(*) into count_value from public.suppliers;
 if count_value<>0 then raise exception 'FAIL: private suppliers exposure';end if;checks:=checks+1;
 rejected:=false;begin perform public.record_stock_movement(r,i,'usage',-1,'Unauthorized',gen_random_uuid());exception when insufficient_privilege then rejected:=true;end;
 if not rejected then raise exception 'FAIL: supplier can change stock';end if;checks:=checks+1;
 rejected:=false;begin insert into public.supplier_account_members(supplier_account_id,user_id) values(outsider_a,supplier_user);exception when insufficient_privilege then rejected:=true;end;
 if not rejected then raise exception 'FAIL: membership self-grant';end if;checks:=checks+1;
 execute 'reset role';perform set_config('request.jwt.claim.sub',outsider::text,true);execute 'set local role authenticated';
 rejected:=false;begin perform public.respond_supplier_connection(conn,'accepted');exception when insufficient_privilege then rejected:=true;end;
 if not rejected then raise exception 'FAIL: foreign connection approval';end if;checks:=checks+1;
 execute 'reset role';perform set_config('request.jwt.claim.sub',owner_id::text,true);execute 'set local role authenticated';
 perform public.respond_supplier_connection(conn,'revoked');
 execute 'reset role';perform set_config('request.jwt.claim.sub',supplier_user::text,true);execute 'set local role authenticated';
 result:=public.supplier_portal_snapshot(a);
 if jsonb_array_length(result->'orders')<>0 or jsonb_array_length(result->'deliveries')<>0 or jsonb_array_length(result->'lines')<>0 then raise exception 'FAIL: revoked access';end if;checks:=checks+1;
 execute 'reset role';perform set_config('request.jwt.claim.sub','',true);execute 'set local role anon';
 rejected:=false;begin perform public.supplier_portal_snapshot(a);exception when insufficient_privilege then rejected:=true;end;
 if not rejected then raise exception 'FAIL: anonymous portal access';end if;checks:=checks+1;
 execute 'reset role';
 perform set_config('gateway.portal_checks',checks::text,true);
end;
$$;
select current_setting('gateway.portal_checks') as supplier_checks_passed;
rollback;
