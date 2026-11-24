-- 08 · Keepalive: evita che il piano gratuito di Supabase metta in pausa il progetto
-- Il workflow di GitHub (.github/workflows/keepalive.yml) chiama ogni giorno public.keepalive().
-- La funzione registra l'ora dell'ultima chiamata: un vero accesso al database, non solo una richiesta a vuoto.
-- Ripetibile: si può rieseguire senza errori.

create table if not exists public.keepalive (
  id     integer     primary key default 1 check (id = 1),   -- una sola riga
  ultimo timestamptz not null default now()
);

alter table public.keepalive enable row level security;      -- nessuna regola: nessuno la legge o scrive direttamente
revoke all on public.keepalive from anon, authenticated;

create or replace function public.keepalive()
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  t timestamptz := now();
begin
  insert into public.keepalive (id, ultimo) values (1, t)
  on conflict (id) do update set ultimo = excluded.ultimo;
  return t;
end;
$$;

revoke all on function public.keepalive() from public;
grant execute on function public.keepalive() to anon, authenticated;
