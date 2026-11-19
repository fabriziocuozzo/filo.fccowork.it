-- 01 · Tabella comune public.iscrizioni + funzione public.ha_app()
-- Ripetibile: si può rieseguire senza errori.

create table if not exists public.iscrizioni (
  user_id   uuid        not null default auth.uid()
                        references auth.users (id) on delete cascade,
  app       text        not null check (app ~ '^[a-z][a-z0-9_]*$'),
  creata_il timestamptz not null default now(),
  primary key (user_id, app)
);

alter table public.iscrizioni enable row level security;

revoke all on public.iscrizioni from anon, authenticated;
grant select, insert on public.iscrizioni to authenticated;

-- Ognuno vede e crea solo le proprie iscrizioni, e solo con sessione aal2.
-- (L'iscrizione si crea dopo la configurazione del secondo fattore, quindi in aal2.)
drop policy if exists iscrizioni_select on public.iscrizioni;
create policy iscrizioni_select on public.iscrizioni
  for select to authenticated
  using (user_id = auth.uid() and (auth.jwt() ->> 'aal') = 'aal2');

drop policy if exists iscrizioni_insert on public.iscrizioni;
create policy iscrizioni_insert on public.iscrizioni
  for insert to authenticated
  with check (user_id = auth.uid() and (auth.jwt() ->> 'aal') = 'aal2');

-- Vero se l'utente corrente è iscritto all'app indicata.
-- SECURITY DEFINER per poter essere usata dentro le regole RLS delle altre tabelle.
create or replace function public.ha_app(nome_app text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.iscrizioni i
    where i.user_id = auth.uid() and i.app = nome_app
  );
$$;

revoke all on function public.ha_app(text) from public;
grant execute on function public.ha_app(text) to authenticated;
