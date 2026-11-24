-- 09 · Misure del cronometro sul campo: filo.misure
-- Ogni riga è il tempo reale di un passo (un box) in una rilevazione. Le righe di una stessa rilevazione
-- condividono "sessione". Possono registrare e leggere il proprietario e gli editor della lavagna; i lettori no.
-- Ripetibile: si può rieseguire senza errori.

create table if not exists filo.misure (
  id          uuid        primary key default gen_random_uuid(),
  lavagna_id  uuid        not null references filo.lavagne (id) on delete cascade,
  user_id     uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  sessione    uuid        not null,
  nodo_id     text        not null,
  nodo_testo  text,
  percorso    text,
  inizio      timestamptz not null,
  fine        timestamptz not null,
  durata_s    numeric     not null check (durata_s >= 0),
  creata_il   timestamptz not null default now(),
  unique (sessione, nodo_id, inizio)      -- rende sicuro rinviare le stesse misure (sincronizzazione dopo il lavoro offline)
);

create index if not exists misure_lavagna_idx on filo.misure (lavagna_id);
create index if not exists misure_user_idx    on filo.misure (user_id);

alter table filo.misure enable row level security;
revoke all on filo.misure from anon, authenticated;
grant select, insert, delete on filo.misure to authenticated;

drop policy if exists misure_select on filo.misure;
create policy misure_select on filo.misure for select to authenticated
  using (filo.sessione_ok() and filo.ruolo_lavagna(lavagna_id) in ('proprietario', 'editor'));

drop policy if exists misure_insert on filo.misure;
create policy misure_insert on filo.misure for insert to authenticated
  with check (filo.sessione_ok() and user_id = auth.uid()
              and filo.ruolo_lavagna(lavagna_id) in ('proprietario', 'editor'));

-- si cancella una propria misura; il proprietario della lavagna può cancellarle tutte
drop policy if exists misure_delete on filo.misure;
create policy misure_delete on filo.misure for delete to authenticated
  using (filo.sessione_ok() and (user_id = auth.uid() or filo.ruolo_lavagna(lavagna_id) = 'proprietario'));
