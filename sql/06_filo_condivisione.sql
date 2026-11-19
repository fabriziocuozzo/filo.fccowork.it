-- 06 · Condivisione per email (solo il proprietario della lavagna)
-- Dal client non si può cercare un utente per email: queste funzioni lo fanno lato database.

-- Aggiunge o aggiorna un membro della lavagna.
create or replace function filo.condividi(p_lavagna uuid, p_email text, p_ruolo text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
begin
  if not filo.sessione_ok() or filo.ruolo_lavagna(p_lavagna) is distinct from 'proprietario' then
    raise exception 'Non autorizzato';
  end if;
  if p_ruolo not in ('lettore', 'editor') then
    raise exception 'Ruolo non valido';
  end if;

  select u.id into v_user from auth.users u
  where lower(u.email) = lower(btrim(p_email));

  if v_user is null then
    raise exception 'Nessun utente registrato con questa email';
  end if;
  if v_user = auth.uid() then
    raise exception 'Sei già il proprietario di questa lavagna';
  end if;

  insert into filo.membri (lavagna_id, user_id, ruolo)
  values (p_lavagna, v_user, p_ruolo)
  on conflict (lavagna_id, user_id) do update set ruolo = excluded.ruolo;
end;
$$;

-- Elenco delle persone con accesso, con email (per la finestra "Condividi").
create or replace function filo.membri_lavagna(p_lavagna uuid)
returns table (user_id uuid, email text, ruolo text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not filo.sessione_ok() or filo.ruolo_lavagna(p_lavagna) is distinct from 'proprietario' then
    raise exception 'Non autorizzato';
  end if;
  return query
    select m.user_id, u.email::text, m.ruolo
    from filo.membri m
    join auth.users u on u.id = m.user_id
    where m.lavagna_id = p_lavagna
    order by u.email;
end;
$$;

revoke all on function filo.condividi(uuid, text, text), filo.membri_lavagna(uuid) from public;
grant execute on function filo.condividi(uuid, text, text), filo.membri_lavagna(uuid) to authenticated;
