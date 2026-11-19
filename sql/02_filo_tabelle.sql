-- 02 · Schema filo e tabelle: progetti, lavagne, elementi, membri
-- Condivisione per singola lavagna. Una lavagna appartiene a un solo progetto (o a nessuno).

create schema if not exists filo;
grant usage on schema filo to anon, authenticated;

create table if not exists filo.progetti (
  id        uuid        primary key default gen_random_uuid(),
  owner_id  uuid        not null default auth.uid()
                        references auth.users (id) on delete cascade,
  nome      text        not null check (length(btrim(nome)) > 0),
  creata_il timestamptz not null default now()
);

create table if not exists filo.lavagne (
  id             uuid        primary key default gen_random_uuid(),
  owner_id       uuid        not null default auth.uid()
                             references auth.users (id) on delete cascade,
  -- una sola colonna = una lavagna sta in un solo progetto; null = nessun progetto
  progetto_id    uuid        references filo.progetti (id) on delete set null,
  titolo         text        not null default 'Senza titolo',
  link_pubblico  boolean     not null default false,
  creata_il      timestamptz not null default now(),
  modificata_il  timestamptz not null default now()
);

create table if not exists filo.elementi (
  id             uuid        primary key default gen_random_uuid(),
  lavagna_id     uuid        not null references filo.lavagne (id) on delete cascade,
  dati           jsonb       not null default '{}'::jsonb,
  versione       integer     not null default 1,
  modificata_il  timestamptz not null default now()
);

create table if not exists filo.membri (
  lavagna_id  uuid not null references filo.lavagne (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  ruolo       text not null check (ruolo in ('lettore', 'editor')),
  primary key (lavagna_id, user_id)
);

create index if not exists lavagne_owner_idx     on filo.lavagne  (owner_id);
create index if not exists lavagne_progetto_idx  on filo.lavagne  (progetto_id);
create index if not exists progetti_owner_idx    on filo.progetti (owner_id);
create index if not exists elementi_lavagna_idx  on filo.elementi (lavagna_id);
create index if not exists membri_user_idx       on filo.membri   (user_id);

-- RLS attiva su ogni tabella (le regole sono nello script 04)
alter table filo.progetti enable row level security;
alter table filo.lavagne  enable row level security;
alter table filo.elementi enable row level security;
alter table filo.membri   enable row level security;

-- Permessi di base: poi le regole RLS restringono riga per riga
revoke all on filo.progetti, filo.lavagne, filo.elementi, filo.membri from anon, authenticated;
grant select, insert, update, delete on filo.progetti, filo.lavagne, filo.elementi, filo.membri to authenticated;
grant select on filo.lavagne, filo.elementi to anon;  -- solo per il link pubblico (la RLS lo limita)
