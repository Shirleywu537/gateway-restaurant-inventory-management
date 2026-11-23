-- Safe, read-only queries for SQL Editor. Run one statement at a time to learn.

-- 1. What is currently in stock?
select name,quantity_on_hand,base_unit,reorder_point,is_low_stock
from public.inventory_levels order by name;

-- 2. What needs replenishing?
select name,quantity_on_hand,base_unit,reorder_point
from public.inventory_levels where is_low_stock order by name;

-- 3. How did tomato stock reach 17 kg?
select i.name,m.movement_type,m.quantity_change,i.base_unit,m.reason,m.created_at
from public.stock_movements m join public.inventory_items i
on i.id=m.item_id and i.restaurant_id=m.restaurant_id
where i.sku='TOMATO' order by m.created_at,m.id;

-- 4. Which purchased items have not fully arrived?
select o.order_number,i.name,p.quantity_ordered,p.quantity_received,p.quantity_outstanding,p.base_unit
from public.purchase_order_progress p
join public.purchase_orders o on o.id=p.purchase_order_id and o.restaurant_id=p.restaurant_id
join public.inventory_items i on i.id=p.item_id and i.restaurant_id=p.restaurant_id
where p.quantity_outstanding > 0 and o.status <> 'cancelled';

-- 5. Convert supplier packs into the item's base unit.
select s.name as supplier,i.name as item,si.purchase_unit,si.base_units_per_pack,i.base_unit,
si.quoted_pack_price,round(si.quoted_pack_price/si.base_units_per_pack,4) as price_per_base_unit
from public.supplier_items si
join public.suppliers s on s.id=si.supplier_id and s.restaurant_id=si.restaurant_id
join public.inventory_items i on i.id=si.item_id and i.restaurant_id=si.restaurant_id;
