begin;
create table public.invoice_imports (
 id uuid primary key default gen_random_uuid(),
 restaurant_id uuid not null references public.restaurants(id),
 supplier_id uuid not null,
 purchase_order_id uuid not null,
 receipt_id uuid not null unique,
 invoice_number text not null check(length(trim(invoice_number)) between 1 and 100),
 invoice_key text generated always as (regexp_replace(upper(trim(invoice_number)),'[^A-Z0-9]','','g')) stored,
 file_sha256 text not null check(file_sha256 ~ '^[a-f0-9]{64}$'),
 file_name text not null check(length(file_name) between 1 and 255),
 file_size integer not null check(file_size between 1 and 20971520),
 extraction_method text not null check(extraction_method in ('text','ocr','mixed')),
 created_at timestamptz not null default now(),
 created_by uuid references auth.users(id) on delete set null,
 request_id uuid not null,
 request_payload jsonb not null,
 foreign key(restaurant_id,supplier_id) references public.suppliers(restaurant_id,id),
 foreign key(restaurant_id,purchase_order_id,receipt_id) references public.goods_receipts(restaurant_id,purchase_order_id,id),
 unique(restaurant_id,supplier_id,invoice_key),
 unique(restaurant_id,file_sha256),
 unique(restaurant_id,request_id),
 check(length(invoice_key)>0)
);
create index invoice_imports_order_idx on public.invoice_imports(restaurant_id,purchase_order_id,receipt_id);
create index invoice_imports_user_idx on public.invoice_imports(created_by);
alter table public.invoice_imports enable row level security;
revoke all on public.invoice_imports from public,anon,authenticated;
grant select on public.invoice_imports to authenticated;
create policy manager_invoice_read on public.invoice_imports for select to authenticated
 using(private.has_restaurant_role(restaurant_id,array['owner','manager']));

create function public.receive_invoice(
 p_restaurant_id uuid,p_order_id uuid,p_supplier_id uuid,p_invoice_number text,
 p_file_sha256 text,p_file_name text,p_file_size integer,p_extraction_method text,
 p_lines jsonb,p_request_id uuid,p_notes text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_order public.purchase_orders;v_prior public.invoice_imports;v_payload jsonb;v_receipt uuid;v_key text;
begin
 if not private.has_restaurant_role(p_restaurant_id,array['owner','manager']) then
  raise exception 'Owner or manager access required' using errcode='42501';
 end if;
 v_key:=regexp_replace(upper(trim(p_invoice_number)),'[^A-Z0-9]','','g');
 if p_invoice_number is null or length(trim(p_invoice_number)) not between 1 and 100 or length(v_key)=0
  or p_file_sha256 is null or p_file_sha256 !~ '^[a-f0-9]{64}$'
  or p_file_name is null or length(p_file_name) not between 1 and 255
  or p_file_size is null or p_file_size not between 1 and 20971520
  or p_extraction_method is null or p_extraction_method not in ('text','ocr','mixed')
  or p_request_id is null or p_supplier_id is null or p_order_id is null
  or (p_notes is not null and length(p_notes)>1000) then
  raise exception 'Supply a valid invoice number, PDF details, supplier, order, and request ID';
 end if;
 v_payload:=jsonb_build_object('order_id',p_order_id,'supplier_id',p_supplier_id,'invoice_number',trim(p_invoice_number),
  'file_sha256',p_file_sha256,'file_name',p_file_name,'file_size',p_file_size,'method',p_extraction_method,'lines',p_lines,'notes',p_notes);
 -- Serialize duplicate checks across every order of this restaurant, not only one PO.
 perform 1 from public.restaurants where id=p_restaurant_id for update;
 select * into v_prior from public.invoice_imports where restaurant_id=p_restaurant_id and request_id=p_request_id;
 if found then
  if v_prior.request_payload is distinct from v_payload then raise exception 'Request ID reused with different invoice details';end if;
  return v_prior.receipt_id;
 end if;
 if exists(select 1 from public.invoice_imports where restaurant_id=p_restaurant_id and
  (file_sha256=p_file_sha256 or (supplier_id=p_supplier_id and invoice_key=v_key))) then
  raise exception 'This invoice has already been recorded. Check Receiving history; no stock was added.';
 end if;
 select * into v_order from public.purchase_orders where restaurant_id=p_restaurant_id and id=p_order_id;
 if not found or v_order.supplier_id<>p_supplier_id then raise exception 'The order does not belong to this restaurant and supplier';end if;
 if exists(select 1 from public.goods_receipts where restaurant_id=p_restaurant_id and request_id=p_request_id) then
  raise exception 'This request ID belongs to a different receipt';
 end if;
 -- Existing receipt workflow validates quantities and locks PO/items, then updates
 -- receipt lines, stock ledger, and partial/complete status in this same transaction.
 v_receipt:=public.receive_purchase_order(p_restaurant_id,p_order_id,p_lines,p_request_id,
  'Invoice '||trim(p_invoice_number)||' | '||p_file_name||case when coalesce(p_notes,'')<>'' then E'\n'||p_notes else '' end);
 insert into public.invoice_imports(restaurant_id,supplier_id,purchase_order_id,receipt_id,invoice_number,
  file_sha256,file_name,file_size,extraction_method,created_by,request_id,request_payload)
 values(p_restaurant_id,p_supplier_id,p_order_id,v_receipt,trim(p_invoice_number),p_file_sha256,p_file_name,p_file_size,
  p_extraction_method,auth.uid(),p_request_id,v_payload);
 return v_receipt;
end;
$$;
revoke all on function public.receive_invoice(uuid,uuid,uuid,text,text,text,integer,text,jsonb,uuid,text) from public,anon,authenticated;
grant execute on function public.receive_invoice(uuid,uuid,uuid,text,text,text,integer,text,jsonb,uuid,text) to authenticated;
comment on table public.invoice_imports is 'Append-only invoice receipt provenance. No original PDF or raw OCR text is stored. Owners/managers only. Supplier portal receives only normal order/receipt projections.';
notify pgrst,'reload schema';

do $$
declare owner_id uuid:=gen_random_uuid();other_id uuid:=gen_random_uuid();staff_id uuid:=gen_random_uuid();supplier_user uuid:=gen_random_uuid();
 r uuid;r2 uuid;s uuid;s2 uuid;i uuid;i2 uuid;po uuid;l uuid;l2 uuid;rec uuid;req uuid:=gen_random_uuid();a uuid;conn uuid;
 payload jsonb;rejected boolean;checks integer:=0;n numeric;result jsonb;
begin
 insert into auth.users(id,email,role,aud) values(owner_id,'invoice-owner-'||owner_id||'@example.invalid','authenticated','authenticated'),
 (other_id,'invoice-other-'||other_id||'@example.invalid','authenticated','authenticated'),
 (staff_id,'invoice-staff-'||staff_id||'@example.invalid','authenticated','authenticated'),
 (supplier_user,'invoice-supplier-'||supplier_user||'@example.invalid','authenticated','authenticated');
 perform set_config('request.jwt.claim.sub',owner_id::text,true);execute 'set local role authenticated';
 r:=public.create_restaurant('Invoice QA rollback');r2:=public.create_restaurant('Other invoice QA');
 insert into public.suppliers(restaurant_id,name) values(r,'Invoice supplier') returning id into s;
 insert into public.suppliers(restaurant_id,name) values(r,'Wrong supplier') returning id into s2;
 insert into public.inventory_items(restaurant_id,sku,name,base_unit) values(r,'TOM','Tomatoes','kg') returning id into i;
 insert into public.inventory_items(restaurant_id,sku,name,base_unit) values(r,'RICE','Rice','kg') returning id into i2;
 perform public.record_stock_movement(r,i,'opening',10,'Test opening',gen_random_uuid());
 po:=public.create_purchase_order(r,s,'INV-QA-PO',jsonb_build_array(jsonb_build_object('item_id',i,'quantity',20,'unit_price',2.5),jsonb_build_object('item_id',i2,'quantity',10,'unit_price',3)),gen_random_uuid());
 select id into l from public.purchase_order_lines where purchase_order_id=po and item_id=i;
 select id into l2 from public.purchase_order_lines where purchase_order_id=po and item_id=i2;
 payload:=jsonb_build_array(jsonb_build_object('purchase_order_line_id',l,'quantity',3));
 rec:=public.receive_invoice(r,po,s,'INV-001',repeat('a',64),'invoice.pdf',12345,'ocr',payload,req,'Checked actual goods');
 select quantity_on_hand into n from public.inventory_levels where item_id=i;
 if n<>13 then raise exception 'FAIL: stock increment';end if;checks:=checks+1;
 if (select status from public.purchase_orders where id=po)<>'partially_received' then raise exception 'FAIL: partial order status';end if;checks:=checks+1;
 if (select quantity_outstanding from public.purchase_order_progress where purchase_order_line_id=l)<>17 then raise exception 'FAIL: outstanding';end if;checks:=checks+1;
 if (select count(*) from public.goods_receipts where id=rec)<>1 or (select count(*) from public.invoice_imports where receipt_id=rec)<>1 then raise exception 'FAIL: receipt provenance';end if;checks:=checks+1;
 if public.receive_invoice(r,po,s,'INV-001',repeat('a',64),'invoice.pdf',12345,'ocr',payload,req,'Checked actual goods')<>rec then raise exception 'FAIL: retry result';end if;
 if (select quantity_on_hand from public.inventory_levels where item_id=i)<>13 then raise exception 'FAIL: duplicate retry';end if;checks:=checks+1;
 rejected:=false;begin perform public.receive_invoice(r,po,s,'INV-001',repeat('a',64),'invoice.pdf',12345,'ocr',payload,req,'Changed');exception when others then rejected:=true;end;
 if not rejected then raise exception 'FAIL: changed retry content';end if;checks:=checks+1;
 rejected:=false;begin perform public.receive_invoice(r,po,s,'INV-999',repeat('a',64),'renamed.pdf',12345,'text',payload,gen_random_uuid());exception when others then rejected:=true;end;
 if not rejected then raise exception 'FAIL: duplicate file';end if;checks:=checks+1;
 rejected:=false;begin perform public.receive_invoice(r,po,s,'inv / 001',repeat('b',64),'new-scan.pdf',12345,'ocr',payload,gen_random_uuid());exception when others then rejected:=true;end;
 if not rejected then raise exception 'FAIL: duplicate invoice number';end if;checks:=checks+1;
 rejected:=false;begin perform public.receive_invoice(r,po,s2,'INV-002',repeat('c',64),'invoice.pdf',12345,'ocr',payload,gen_random_uuid());exception when others then rejected:=true;end;
 if not rejected then raise exception 'FAIL: supplier mismatch';end if;checks:=checks+1;
 rejected:=false;begin perform public.receive_invoice(r2,po,s,'INV-002',repeat('c',64),'invoice.pdf',12345,'ocr',payload,gen_random_uuid());exception when others then rejected:=true;end;
 if not rejected then raise exception 'FAIL: restaurant mismatch';end if;checks:=checks+1;
 rejected:=false;begin perform public.receive_invoice(r,po,s,'INV-002',repeat('c',64),'invoice.pdf',12345,'ocr',jsonb_build_array(jsonb_build_object('purchase_order_line_id',l,'quantity',25)),gen_random_uuid());exception when others then rejected:=true;end;
 if not rejected then raise exception 'FAIL: over-receiving';end if;checks:=checks+1;
 rejected:=false;begin perform public.receive_invoice(r,po,s,'INV-002',repeat('c',64),'invoice.pdf',12345,'ocr',jsonb_build_array(jsonb_build_object('purchase_order_line_id',l,'quantity',1),jsonb_build_object('purchase_order_line_id',l2,'quantity',99)),gen_random_uuid());exception when others then rejected:=true;end;
 if not rejected or (select quantity_on_hand from public.inventory_levels where item_id=i)<>13 or (select count(*) from public.invoice_imports where restaurant_id=r)<>1 then raise exception 'FAIL: atomic rollback';end if;checks:=checks+1;
 rejected:=false;begin perform public.receive_invoice(r,po,s,'---',repeat('c',64),'invoice.pdf',12345,'ocr',payload,gen_random_uuid());exception when others then rejected:=true;end;
 if not rejected then raise exception 'FAIL: empty normalized invoice number';end if;checks:=checks+1;
 rejected:=false;begin perform public.receive_invoice(r,po,s,'INV-002',repeat('c',64),'invoice.pdf',30000000,'ocr',payload,gen_random_uuid());exception when others then rejected:=true;end;
 if not rejected then raise exception 'FAIL: oversized document';end if;checks:=checks+1;
 perform public.receive_invoice(r,po,s,'INV-002',repeat('c',64),'invoice2.pdf',12345,'mixed',jsonb_build_array(jsonb_build_object('purchase_order_line_id',l,'quantity',17),jsonb_build_object('purchase_order_line_id',l2,'quantity',10)),gen_random_uuid());
 if (select status from public.purchase_orders where id=po)<>'received' or (select quantity_on_hand from public.inventory_levels where item_id=i)<>30 or (select count(*) from public.goods_receipts where purchase_order_id=po)<>2 then raise exception 'FAIL: completion';end if;checks:=checks+1;
 execute 'reset role';insert into public.restaurant_members values(r,staff_id,'staff',now());
 perform set_config('request.jwt.claim.sub',staff_id::text,true);execute 'set local role authenticated';
 rejected:=false;begin perform public.receive_invoice(r,po,s,'INV-003',repeat('d',64),'invoice.pdf',12345,'ocr',payload,gen_random_uuid());exception when insufficient_privilege then rejected:=true;end;
 if not rejected or (select count(*) from public.invoice_imports)<>0 then raise exception 'FAIL: staff restriction';end if;checks:=checks+1;
 execute 'reset role';perform set_config('request.jwt.claim.sub',other_id::text,true);execute 'set local role authenticated';
 if (select count(*) from public.invoice_imports)<>0 then raise exception 'FAIL: outsider invoice read';end if;
 rejected:=false;begin perform public.receive_invoice(r,po,s,'INV-003',repeat('d',64),'invoice.pdf',12345,'ocr',payload,gen_random_uuid());exception when insufficient_privilege then rejected:=true;end;
 if not rejected then raise exception 'FAIL: outsider write';end if;checks:=checks+1;
 execute 'reset role';perform set_config('request.jwt.claim.sub',supplier_user::text,true);execute 'set local role authenticated';
 a:=public.create_supplier_account('Invoice supplier account',gen_random_uuid());
 execute 'reset role';perform set_config('request.jwt.claim.sub',owner_id::text,true);execute 'set local role authenticated';conn:=public.request_supplier_connection(r,s,a);
 execute 'reset role';perform set_config('request.jwt.claim.sub',supplier_user::text,true);execute 'set local role authenticated';perform public.respond_supplier_connection(conn,'accepted');result:=public.supplier_portal_snapshot(a);
 if jsonb_array_length(result->'deliveries')<>2 or (result->'orders'->0->>'status')<>'received' then raise exception 'FAIL: supplier delivery projection';end if;
 if (select count(*) from public.invoice_imports)<>0 or result::text ~ 'file_sha256|invoice.pdf|Checked actual goods|quantity_on_hand' then raise exception 'FAIL: supplier private fields';end if;checks:=checks+1;
 execute 'reset role';perform set_config('request.jwt.claim.sub','',true);execute 'set local role anon';
 rejected:=false;begin perform public.receive_invoice(r,po,s,'INV-003',repeat('d',64),'invoice.pdf',12345,'ocr',payload,gen_random_uuid());exception when insufficient_privilege then rejected:=true;end;
 if not rejected then raise exception 'FAIL: anonymous write';end if;checks:=checks+1;
 execute 'reset role';perform set_config('gateway.invoice_checks',checks::text,true);
end;
$$;
select current_setting('gateway.invoice_checks') as invoice_checks_passed;
rollback;
