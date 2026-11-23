begin;
-- Cover all foreign-key lookups flagged by the project's Performance Advisor.
create index goods_receipt_lines_receipt_fk_idx
  on public.goods_receipt_lines(restaurant_id,purchase_order_id,receipt_id);
create index goods_receipt_lines_order_line_fk_idx
  on public.goods_receipt_lines(restaurant_id,purchase_order_id,purchase_order_line_id,item_id);
create index goods_receipts_actor_idx on public.goods_receipts(received_by);
create index purchase_orders_actor_idx on public.purchase_orders(created_by);
create index stock_movements_actor_idx on public.stock_movements(created_by);
create index stock_movements_receipt_fk_idx on public.stock_movements(restaurant_id,item_id,receipt_line_id);

-- This Supabase-created event trigger is for DDL, not a client API endpoint.
-- Keep the trigger itself enabled while removing unnecessary client execution.
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke all on function public.rls_auto_enable() from public,anon,authenticated;
  end if;
end;
$$;
commit;
