-- 05 · Realtime sugli elementi (modifiche condivise quasi in tempo reale)
-- Realtime rispetta la RLS: ognuno riceve solo gli elementi che può leggere.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'filo' and tablename = 'elementi'
  ) then
    alter publication supabase_realtime add table filo.elementi;
  end if;
end $$;
