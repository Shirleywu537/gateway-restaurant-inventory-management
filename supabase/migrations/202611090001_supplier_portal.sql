-- Add supplier identities and explicit restaurant connections. Existing restaurant RLS is unchanged.
begin;
create table public.supplier_accounts (
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(trim(name)) between 1 and 160),
 created_by uuid not null references auth.users(id),
 request_id uuid not null,
 created_at timestamptz not null default now(),
 unique(created_by,request_id)
);
create table public.supplier_account_members (
 supplier_account_id uuid not null references public.supplier_accounts(id),
 user_id uuid not null references auth.users(id) on delete cascade,
 role text not null default 'owner' check(role in ('owner','member')),
 primary key(supplier_account_id,user_id)
);
create index supplier_account_members_user_idx on public.supplier_account_members(user_id,supplier_account_id);
create table public.restaurant_supplier_connections (
 id uuid primary key default gen_random_uuid(),
 restaurant_id uuid not null references public.restaurants(id),
 supplier_id uuid not null,
 supplier_account_id uuid not null references public.supplier_accounts(id),
 status text not null default 'pending' check(status in ('pending','accepted','declined','revoked')),
 requested_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 foreign key(restaurant_id,supplier_id) references public.suppliers(restaurant_id,id),
 unique(restaurant_id,supplier_id),
 unique(restaurant_id,supplier_account_id)
);
create index restaurant_supplier_connections_account_idx on public.restaurant_supplier_connections(supplier_account_id,status);
create index supplier_accounts_creator_idx on public.supplier_accounts(created_by);
create index restaurant_supplier_connections_requester_idx on public.restaurant_supplier_connections(requested_by);

create function private.is_supplier_member(p_account uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.supplier_account_members m where m.supplier_account_id=p_account and m.user_id=(select auth.uid()));
$$;
revoke all on function private.is_supplier_member(uuid) from public,anon,authenticated;
grant execute on function private.is_supplier_member(uuid) to authenticated;
alter table public.supplier_accounts enable row level security;
alter table public.supplier_account_members enable row level security;
alter table public.restaurant_supplier_connections enable row level security;
revoke all on public.supplier_accounts,public.supplier_account_members,public.restaurant_supplier_connections from public,anon,authenticated;
grant select on public.supplier_accounts,public.supplier_account_members,public.restaurant_supplier_connections to authenticated;
create policy own_supplier_account on public.supplier_accounts for select to authenticated using(private.is_supplier_member(id));
create policy own_supplier_membership on public.supplier_account_members for select to authenticated using(user_id=(select auth.uid()));
create policy connection_participants on public.restaurant_supplier_connections for select to authenticated using(
 private.is_supplier_member(supplier_account_id) or private.has_restaurant_role(restaurant_id,array['owner','manager']));

create function public.create_supplier_account(p_name text,p_request_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_name text;
begin
 if auth.uid() is null then raise exception 'Sign in first' using errcode='42501'; end if;
 if p_request_id is null or p_name is null or length(trim(p_name)) not between 1 and 160 then raise exception 'Supply a business name and request ID'; end if;
 -- Serializes same-user creation/retry without introducing membership based on user metadata.
 perform 1 from auth.users where id=auth.uid() for update;
 select id,name into v_id,v_name from public.supplier_accounts where created_by=auth.uid() and request_id=p_request_id;
 if found then
  if v_name<>trim(p_name) then raise exception 'Request ID reused with different content'; end if;
  return v_id;
 end if;
 insert into public.supplier_accounts(name,created_by,request_id) values(trim(p_name),auth.uid(),p_request_id) returning id into v_id;
 insert into public.supplier_account_members(supplier_account_id,user_id) values(v_id,auth.uid());
 return v_id;
end;
$$;
create function public.supplier_portal_accounts() returns jsonb
language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'name',a.name) order by a.name),'[]'::jsonb) from public.supplier_accounts a;
$$;

create function public.request_supplier_connection(p_restaurant_id uuid,p_supplier_id uuid,p_supplier_account_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare v public.restaurant_supplier_connections; v_id uuid;
begin
 if not private.has_restaurant_role(p_restaurant_id,array['owner','manager']) then raise exception 'Restaurant manager access required' using errcode='42501'; end if;
 perform 1 from public.suppliers where id=p_supplier_id and restaurant_id=p_restaurant_id and is_active for update;
 if not found then raise exception 'Choose an active supplier belonging to your restaurant'; end if;
 if not exists(select 1 from public.supplier_accounts where id=p_supplier_account_id) then raise exception 'Supplier connection code not found'; end if;
 select * into v from public.restaurant_supplier_connections where restaurant_id=p_restaurant_id and supplier_id=p_supplier_id for update;
 if found then
  if v.supplier_account_id=p_supplier_account_id and v.status in ('pending','accepted') then return v.id; end if;
  if v.status in ('pending','accepted') then raise exception 'Disconnect the existing account before requesting another connection'; end if;
  update public.restaurant_supplier_connections set supplier_account_id=p_supplier_account_id,status='pending',requested_by=auth.uid(),updated_at=now() where id=v.id;
  return v.id;
 end if;
 insert into public.restaurant_supplier_connections(restaurant_id,supplier_id,supplier_account_id,requested_by)
 values(p_restaurant_id,p_supplier_id,p_supplier_account_id,auth.uid()) returning id into v_id;
 return v_id;
end;
$$;
create function public.respond_supplier_connection(p_connection_id uuid,p_status text) returns void
language plpgsql security definer set search_path='' as $$
declare v public.restaurant_supplier_connections; v_supplier boolean; v_restaurant boolean;
begin
 select * into v from public.restaurant_supplier_connections where id=p_connection_id for update;
 if not found then raise exception 'Connection unavailable' using errcode='42501'; end if;
 v_supplier:=private.is_supplier_member(v.supplier_account_id);
 v_restaurant:=private.has_restaurant_role(v.restaurant_id,array['owner','manager']);
 if not (v_supplier or v_restaurant) then raise exception 'Connection unavailable' using errcode='42501'; end if;
 if p_status='revoked' then
  update public.restaurant_supplier_connections set status='revoked',updated_at=now() where id=v.id;return;
 end if;
 if not v_supplier or p_status not in ('accepted','declined') or p_status is null then raise exception 'Supplier approval required' using errcode='42501'; end if;
 if v.status=p_status then return; end if;
 if v.status<>'pending' then raise exception 'Only pending requests can be accepted or declined'; end if;
 update public.restaurant_supplier_connections set status=p_status,updated_at=now() where id=v.id;
end;
$$;

-- Narrow, server-filtered projection: NEVER return stock balances, reorder points,
-- internal notes, usage/waste, other suppliers, or unrelated ingredient records.
create function public.supplier_portal_snapshot(p_supplier_account_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.is_supplier_member(p_supplier_account_id) then raise exception 'Supplier membership required' using errcode='42501'; end if;
 with connections as (
  select c.id,c.restaurant_id,c.supplier_id,c.status,c.created_at,r.name as restaurant_name,r.currency
  from public.restaurant_supplier_connections c join public.restaurants r on r.id=c.restaurant_id
  where c.supplier_account_id=p_supplier_account_id
 ), visible_orders as (
  select o.id,o.restaurant_id,o.order_number,o.status,o.ordered_at,o.expected_on,c.restaurant_name,c.currency
  from public.purchase_orders o join connections c on c.restaurant_id=o.restaurant_id and c.supplier_id=o.supplier_id and c.status='accepted'
 ), visible_lines as (
  select l.id as line_id,l.purchase_order_id as order_id,i.name as product_name,l.base_unit,l.quantity_ordered,l.unit_price,
   coalesce((select sum(g.quantity_received) from public.goods_receipt_lines g where g.restaurant_id=l.restaurant_id and g.purchase_order_line_id=l.id),0) as quantity_received
  from public.purchase_order_lines l join visible_orders o on o.id=l.purchase_order_id and o.restaurant_id=l.restaurant_id
  join public.inventory_items i on i.id=l.item_id and i.restaurant_id=l.restaurant_id
 )
 select jsonb_build_object(
  'account',(select jsonb_build_object('id',a.id,'name',a.name) from public.supplier_accounts a where a.id=p_supplier_account_id),
  'connections',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'restaurant_id',c.restaurant_id,'restaurant_name',c.restaurant_name,'currency',c.currency,'status',c.status,'created_at',c.created_at) order by c.restaurant_name) from connections c),'[]'::jsonb),
  'orders',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'restaurant_id',o.restaurant_id,'restaurant_name',o.restaurant_name,'currency',o.currency,'order_number',o.order_number,'status',o.status,'ordered_at',o.ordered_at,'expected_on',o.expected_on,'total_amount',coalesce((select sum(l.quantity_ordered*l.unit_price) from visible_lines l where l.order_id=o.id),0)) order by o.ordered_at desc) from visible_orders o),'[]'::jsonb),
  'lines',coalesce((select jsonb_agg(jsonb_build_object('line_id',l.line_id,'order_id',l.order_id,'product_name',l.product_name,'base_unit',l.base_unit,'quantity_ordered',l.quantity_ordered,'quantity_received',l.quantity_received,'quantity_outstanding',l.quantity_ordered-l.quantity_received,'unit_price',l.unit_price)) from visible_lines l),'[]'::jsonb),
  'deliveries',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'order_id',o.id,'order_number',o.order_number,'restaurant_id',o.restaurant_id,'restaurant_name',o.restaurant_name,'received_at',g.received_at,'lines',coalesce((select jsonb_agg(jsonb_build_object('product_name',l.product_name,'base_unit',l.base_unit,'quantity_received',gl.quantity_received)) from public.goods_receipt_lines gl join visible_lines l on l.line_id=gl.purchase_order_line_id where gl.receipt_id=g.id),'[]'::jsonb)) order by g.received_at desc) from public.goods_receipts g join visible_orders o on o.id=g.purchase_order_id and o.restaurant_id=g.restaurant_id),'[]'::jsonb)
 ) into result;
 return result;
end;
$$;
revoke all on function public.create_supplier_account(text,uuid),public.supplier_portal_accounts(),public.request_supplier_connection(uuid,uuid,uuid),public.respond_supplier_connection(uuid,text),public.supplier_portal_snapshot(uuid) from public,anon,authenticated;
grant execute on function public.create_supplier_account(text,uuid),public.supplier_portal_accounts(),public.request_supplier_connection(uuid,uuid,uuid),public.respond_supplier_connection(uuid,text),public.supplier_portal_snapshot(uuid) to authenticated;
comment on function public.supplier_portal_snapshot(uuid) is 'Supplier-member-only projection of explicitly accepted restaurant connections and own orders/receipts. Does not grant restaurant membership or inventory access.';
notify pgrst,'reload schema';
commit;
