-- 07 · Eliminazione dell'account (richiesta GDPR: cancellazione dei propri dati)
-- La chiama l'utente stesso dall'app (menu utente → Elimina account).
-- Ripetibile: si può rieseguire senza errori.
--
-- Cosa fa:
--   1. elimina i dati di Filo dell'utente: progetti, lavagne (con elementi e condivisioni),
--      le sue partecipazioni alle lavagne di altri e l'iscrizione all'app "filo";
--   2. se l'utente non è iscritto a nessun'altra app, elimina anche l'account di accesso (auth.users).
--      Le app condividono lo stesso login: se ne usa altre, l'account di accesso resta.
-- Restituisce true se l'account di accesso è stato eliminato, false se resta per altre app.

create or replace function filo.elimina_account()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Non autenticato';
  end if;
  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    raise exception 'Serve la verifica in due passaggi';
  end if;

  -- dati di Filo (le lavagne eliminano a cascata elementi e membri)
  delete from filo.membri   where user_id  = v_user;
  delete from filo.lavagne  where owner_id = v_user;
  delete from filo.progetti where owner_id = v_user;
  delete from public.iscrizioni where user_id = v_user and app = 'filo';

  -- l'account di accesso si elimina solo se non resta iscritto ad altre app
  if not exists (select 1 from public.iscrizioni where user_id = v_user) then
    delete from auth.users where id = v_user;
    return true;
  end if;
  return false;
end;
$$;

revoke all on function filo.elimina_account() from public, anon;
grant execute on function filo.elimina_account() to authenticated;
