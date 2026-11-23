-- Restaurant Inventory & Supply Chain: one stock pool per restaurant in v1.
-- All quantities use the item's base unit; prices use the restaurant currency.
begin;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create table public.restaurants (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 160),
  currency text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  timezone text not null default 'America/New_York',
  is_demo boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.restaurant_members (
  restaurant_id uuid not null references public.restaurants(id),
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','manager','staff','viewer')),
  created_at timestamptz not null default now(),
  primary key (restaurant_id,user_id)
);
create index restaurant_members_user_idx on public.restaurant_members(user_id,restaurant_id);

create table public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id),
  sku text not null check (length(trim(sku)) between 1 and 60),
  name text not null check (length(trim(name)) between 1 and 160),
  category text not null default 'Other',
  base_unit text not null check (base_unit in ('kg','g','l','ml','each')),
  reorder_point numeric(14,3) not null default 0
    check (reorder_point >= 0 and reorder_point <> 'NaN'::numeric),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (restaurant_id,id), unique (restaurant_id,sku)
);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id),
  name text not null check (length(trim(name)) between 1 and 160),
  contact_name text,
  contact_email text,
  contact_phone text,
  lead_time_days integer not null default 0 check (lead_time_days >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (restaurant_id,id)
);

create table public.supplier_items (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id),
  supplier_id uuid not null,
  item_id uuid not null,
  supplier_sku text,
  purchase_unit text not null default 'pack',
  base_units_per_pack numeric(14,3) not null
    check (base_units_per_pack > 0 and base_units_per_pack <> 'NaN'::numeric),
  quoted_pack_price numeric(14,4) not null
    check (quoted_pack_price >= 0 and quoted_pack_price <> 'NaN'::numeric),
  created_at timestamptz not null default now(),
  foreign key (restaurant_id,supplier_id) references public.suppliers(restaurant_id,id),
  foreign key (restaurant_id,item_id) references public.inventory_items(restaurant_id,id),
  unique (restaurant_id,supplier_id,item_id)
);
create index supplier_items_item_idx on public.supplier_items(restaurant_id,item_id);

create table public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id),
  supplier_id uuid not null,
  order_number text not null check (length(trim(order_number)) between 1 and 80),
  status text not null default 'ordered'
    check (status in ('ordered','partially_received','received','cancelled')),
  ordered_at timestamptz not null default now(),
  expected_on date,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  request_id uuid not null default gen_random_uuid(),
  request_payload jsonb not null default '{}'::jsonb,
  foreign key (restaurant_id,supplier_id) references public.suppliers(restaurant_id,id),
  unique (restaurant_id,id), unique (restaurant_id,order_number),
  unique (restaurant_id,request_id)
);
create index purchase_orders_supplier_idx on public.purchase_orders(restaurant_id,supplier_id);

create table public.purchase_order_lines (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id),
  purchase_order_id uuid not null,
  item_id uuid not null,
  quantity_ordered numeric(14,3) not null
    check (quantity_ordered > 0 and quantity_ordered <> 'NaN'::numeric),
  unit_price numeric(14,4) not null
    check (unit_price >= 0 and unit_price <> 'NaN'::numeric),
  base_unit text not null check (base_unit in ('kg','g','l','ml','each')),
  foreign key (restaurant_id,purchase_order_id) references public.purchase_orders(restaurant_id,id),
  foreign key (restaurant_id,item_id) references public.inventory_items(restaurant_id,id),
  unique (restaurant_id,purchase_order_id,item_id),
  unique (restaurant_id,purchase_order_id,id,item_id)
);
create index purchase_order_lines_item_idx on public.purchase_order_lines(restaurant_id,item_id);

create table public.goods_receipts (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id),
  purchase_order_id uuid not null,
  received_at timestamptz not null default now(),
  received_by uuid references auth.users(id) on delete set null,
  notes text,
  request_id uuid not null,
  request_payload jsonb not null,
  foreign key (restaurant_id,purchase_order_id) references public.purchase_orders(restaurant_id,id),
  unique (restaurant_id,purchase_order_id,id), unique (restaurant_id,request_id)
);
create index goods_receipts_order_idx on public.goods_receipts(restaurant_id,purchase_order_id);

create table public.goods_receipt_lines (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id),
  receipt_id uuid not null,
  purchase_order_id uuid not null,
  purchase_order_line_id uuid not null,
  item_id uuid not null,
  quantity_received numeric(14,3) not null
    check (quantity_received > 0 and quantity_received <> 'NaN'::numeric),
  foreign key (restaurant_id,purchase_order_id,receipt_id)
    references public.goods_receipts(restaurant_id,purchase_order_id,id),
  foreign key (restaurant_id,purchase_order_id,purchase_order_line_id,item_id)
    references public.purchase_order_lines(restaurant_id,purchase_order_id,id,item_id),
  unique (receipt_id,purchase_order_line_id), unique (restaurant_id,item_id,id)
);
create index goods_receipt_lines_order_line_idx
  on public.goods_receipt_lines(restaurant_id,purchase_order_line_id);

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id),
  item_id uuid not null,
  movement_type text not null check (movement_type in ('opening','receipt','usage','waste','adjustment')),
  quantity_change numeric(14,3) not null
    check (quantity_change <> 0 and quantity_change <> 'NaN'::numeric),
  receipt_line_id uuid,
  reason text not null check (length(trim(reason)) between 1 and 500),
  request_id uuid not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  foreign key (restaurant_id,item_id) references public.inventory_items(restaurant_id,id),
  foreign key (restaurant_id,item_id,receipt_line_id)
    references public.goods_receipt_lines(restaurant_id,item_id,id),
  check ((movement_type in ('opening','receipt') and quantity_change > 0)
    or (movement_type in ('usage','waste') and quantity_change < 0)
    or movement_type = 'adjustment'),
  check ((movement_type = 'receipt') = (receipt_line_id is not null)),
  unique (receipt_line_id), unique (restaurant_id,request_id)
);
create index stock_movements_item_time_idx on public.stock_movements(restaurant_id,item_id,created_at);
create unique index stock_movements_one_opening_idx on public.stock_movements(restaurant_id,item_id)
  where movement_type = 'opening';

-- Membership checks bypass only this helper's own table RLS, preventing recursion.
create function private.has_restaurant_role(p_restaurant_id uuid, p_roles text[])
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.restaurant_members m
    where m.restaurant_id = p_restaurant_id and m.user_id = (select auth.uid())
      and m.role = any(p_roles));
$$;
revoke all on function private.has_restaurant_role(uuid,text[]) from public,anon,authenticated;
grant execute on function private.has_restaurant_role(uuid,text[]) to authenticated;

do $$
declare t text;
begin
  foreach t in array array['restaurants','restaurant_members','inventory_items','suppliers',
    'supplier_items','purchase_orders','purchase_order_lines','goods_receipts','goods_receipt_lines','stock_movements']
  loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from anon, authenticated',t);
    execute format('grant select on table public.%I to authenticated',t);
    execute format('create policy member_read on public.%I for select to authenticated using '
      || '(private.has_restaurant_role(%I, array[''owner'',''manager'',''staff'',''viewer'']))',
      t, case when t = 'restaurants' then 'id' else 'restaurant_id' end);
  end loop;
  foreach t in array array['inventory_items','suppliers','supplier_items'] loop
    execute format('grant insert on table public.%I to authenticated',t);
    execute format('create policy manager_insert on public.%I for insert to authenticated with check '
      || '(private.has_restaurant_role(restaurant_id, array[''owner'',''manager'']))',t);
    execute format('create policy manager_update on public.%I for update to authenticated using '
      || '(private.has_restaurant_role(restaurant_id, array[''owner'',''manager''])) with check '
      || '(private.has_restaurant_role(restaurant_id, array[''owner'',''manager'']))',t);
  end loop;
end;
$$;
grant update (name,category,reorder_point,is_active) on public.inventory_items to authenticated;
grant update (name,contact_name,contact_email,contact_phone,lead_time_days,is_active)
  on public.suppliers to authenticated;
grant update (supplier_sku,purchase_unit,base_units_per_pack,quoted_pack_price)
  on public.supplier_items to authenticated;

-- security_invoker ensures aggregations obey the caller's RLS policies.
create view public.inventory_levels with (security_invoker = true) as
select i.restaurant_id, i.id as item_id, i.sku, i.name, i.category, i.base_unit,
  i.reorder_point, i.is_active,
  coalesce(sum(m.quantity_change),0)::numeric(14,3) as quantity_on_hand,
  (coalesce(sum(m.quantity_change),0) < i.reorder_point and i.is_active) as is_low_stock
from public.inventory_items i left join public.stock_movements m
  on m.restaurant_id = i.restaurant_id and m.item_id = i.id
group by i.id;

create view public.purchase_order_progress with (security_invoker = true) as
select l.restaurant_id, l.purchase_order_id, l.id as purchase_order_line_id, l.item_id,
  l.quantity_ordered, l.base_unit, l.unit_price,
  coalesce(sum(r.quantity_received),0)::numeric(14,3) as quantity_received,
  (l.quantity_ordered - coalesce(sum(r.quantity_received),0))::numeric(14,3) as quantity_outstanding
from public.purchase_order_lines l left join public.goods_receipt_lines r
  on r.restaurant_id = l.restaurant_id and r.purchase_order_line_id = l.id
group by l.id;
revoke all on public.inventory_levels, public.purchase_order_progress from anon,authenticated;
grant select on public.inventory_levels,public.purchase_order_progress to authenticated;

comment on table public.inventory_items is 'Item master. Stock is calculated from stock_movements; do not store an editable stock balance here.';
comment on table public.stock_movements is 'Append-only inventory ledger. App users write via validated RPC functions only.';
comment on column public.purchase_order_lines.quantity_ordered is 'Quantity in base_unit, never a mixture of packs and base units.';
comment on column public.purchase_order_lines.unit_price is 'Historical price per base unit in the restaurant currency.';
comment on column public.supplier_items.base_units_per_pack is 'Example: a 5 kg case has base_units_per_pack=5 when the item base_unit is kg.';
comment on view public.inventory_levels is 'RLS-aware stock totals and low-stock flag. No valuation or demand forecasting in v1.';
commit;
