-- Final read-only summary. No credentials or personal Auth records are returned.
select 'business_tables_with_rls' as check_name,count(*)::text as result
from pg_tables where schemaname='public' and rowsecurity and tablename in
('restaurants','restaurant_members','inventory_items','suppliers','supplier_items','purchase_orders',
'purchase_order_lines','goods_receipts','goods_receipt_lines','stock_movements')
union all select 'restaurants',count(*)::text from public.restaurants
union all select 'demo_items',count(*)::text from public.inventory_items
union all select 'suppliers',count(*)::text from public.suppliers
union all select 'stock_movements',count(*)::text from public.stock_movements
union all select 'application_auth_users',count(*)::text from auth.users
union all select 'application_memberships',count(*)::text from public.restaurant_members
union all select 'low_stock_items',count(*)::text from public.inventory_levels where is_low_stock
union all select 'tomatoes_outstanding_kg',quantity_outstanding::text
from public.purchase_order_progress p join public.inventory_items i on i.id=p.item_id
where i.sku='TOMATO';
