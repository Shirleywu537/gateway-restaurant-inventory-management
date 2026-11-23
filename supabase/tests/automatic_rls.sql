-- Targeted check after restricting the Supabase-created event-trigger function.
begin;
create table public.inventory_rls_probe (id integer primary key);
do $$
begin
  if not (select relrowsecurity from pg_class where oid='public.inventory_rls_probe'::regclass) then
    raise exception 'FAIL: automatic RLS is not enabled on new public tables';
  end if;
  if has_function_privilege('anon','public.rls_auto_enable()','execute')
    or has_function_privilege('authenticated','public.rls_auto_enable()','execute') then
    raise exception 'FAIL: automatic-RLS event function is callable by an app role';
  end if;
end;
$$;
rollback;
select 'PASS: automatic RLS still works; client execution denied; probe table rolled back.' as validation_result;
