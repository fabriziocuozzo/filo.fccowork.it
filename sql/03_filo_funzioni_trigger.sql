-- 03 · Funzioni di supporto e trigger dello schema filo

-- Sessione valida: utente iscritto a Filo E verifica in due passaggi superata (aal2).
create or replace function filo.sessione_ok()
returns boolean
language sql
stable
as $$
  select public.ha_app('filo') and coalesce(auth.jwt() ->> 'aal', '') = 'aal2';
$$;

-- Ruolo dell'utente corrente su una lavagna: 'proprietario' | 'editor' | 'lettore' | null.
-- SECURITY DEFINER per non creare ricorsioni tra le regole RLS di lavagne e membri.
create or replace function filo.ruolo_lavagna(p_lavagna uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when l.owner_id = auth.uid() then 'proprietario'
    else (select m.ruolo from filo.membri m
          where m.lavagna_id = l.id and m.user_id = auth.uid())
  end
  from filo.lavagne l
  where l.id = p_lavagna;
$$;

create or replace function filo.lavagna_pubblica(p_lavagna uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select l.link_pubblico from filo.lavagne l where l.id = p_lavagna), false);
$$;

create or replace function filo.progetto_mio(p_progetto uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from filo.progetti p
                 where p.id = p_progetto and p.owner_id = auth.uid());
$$;

revoke all on function filo.sessione_ok(), filo.ruolo_lavagna(uuid),
                       filo.lavagna_pubblica(uuid), filo.progetto_mio(uuid) from public;
grant execute on function filo.sessione_ok(), filo.ruolo_lavagna(uuid),
                          filo.progetto_mio(uuid) to authenticated;
grant execute on function filo.lavagna_pubblica(uuid) to anon, authenticated;

-- Lavagne: data di modifica; un editor non può cambiare proprietario, progetto o link pubblico;
-- il progetto assegnato deve essere del proprietario della lavagna.
create or replace function filo.trg_lavagne()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    new.modificata_il := now();
    if auth.uid() is not null and auth.uid() is distinct from old.owner_id then
      if new.owner_id      is distinct from old.owner_id
      or new.progetto_id   is distinct from old.progetto_id
      or new.link_pubblico is distinct from old.link_pubblico then
        raise exception 'Solo il proprietario può cambiare proprietario, progetto o link pubblico';
      end if;
    end if;
  end if;

  if auth.uid() is not null and new.progetto_id is not null
     and (tg_op = 'INSERT' or new.progetto_id is distinct from old.progetto_id)
     and not filo.progetto_mio(new.progetto_id) then
    raise exception 'Il progetto non esiste o non è tuo';
  end if;
  return new;
end;
$$;

drop trigger if exists lavagne_biu on filo.lavagne;
create trigger lavagne_biu before insert or update on filo.lavagne
  for each row execute function filo.trg_lavagne();

-- Elementi: versione e data; non si sposta un elemento su un'altra lavagna.
create or replace function filo.trg_elementi_before()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.lavagna_id is distinct from old.lavagna_id then
      raise exception 'Non si può spostare un elemento su un''altra lavagna';
    end if;
    new.versione := old.versione + 1;
  end if;
  new.modificata_il := now();
  return new;
end;
$$;

drop trigger if exists elementi_biu on filo.elementi;
create trigger elementi_biu before insert or update on filo.elementi
  for each row execute function filo.trg_elementi_before();

-- Ogni modifica agli elementi aggiorna "modificata_il" della lavagna (per la sezione Recenti).
create or replace function filo.trg_elementi_after()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update filo.lavagne set modificata_il = now()
  where id = coalesce(new.lavagna_id, old.lavagna_id);
  return null;
end;
$$;

drop trigger if exists elementi_aiud on filo.elementi;
create trigger elementi_aiud after insert or update or delete on filo.elementi
  for each row execute function filo.trg_elementi_after();
