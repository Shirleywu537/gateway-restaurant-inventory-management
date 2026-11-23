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
commit;
