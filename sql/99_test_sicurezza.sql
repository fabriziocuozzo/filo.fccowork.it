-- 99 · Test di sicurezza di Filo (RLS, verifica in due passaggi, link pubblico, eliminazione account)
--
-- COME SI USA
--   1. Incolla tutto nell'SQL Editor di Supabase ed esegui.
--   2. Il test crea utenti e lavagne FINTI, li usa, e alla fine ANNULLA TUTTO: non resta nessun dato.
--   3. Il risultato compare come un "errore" rosso che inizia con "RISULTATO TEST DI SICUREZZA":
--      è voluto (è il modo per annullare tutto e mostrarti il rapporto). Ogni riga è ✅ o ❌.
--   4. Tutte le righe devono essere ✅. Se ne vedi una ❌, non mettere dati veri e mandami il rapporto.
--   Se invece compare un errore diverso (prima della preparazione), mandami il messaggio.
--
-- Il test simula le sessioni come fa Supabase: ruolo "authenticated" o "anon" + i dati del token (sub, aal).

create or replace function pg_temp.claims(p_uid uuid, p_aal text) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
end $f$;

do $test$
declare
  ua uuid := gen_random_uuid();   -- A: proprietario
  ub uuid := gen_random_uuid();   -- B: invitato (iscritto a Filo)
  uc uuid := gen_random_uuid();   -- C: invitato ma NON iscritto a Filo
  p1 uuid := gen_random_uuid();
  l1 uuid := gen_random_uuid();   -- privata di A
  l2 uuid := gen_random_uuid();   -- con link pubblico
  l3 uuid := gen_random_uuid();   -- B lettore, C editor (non iscritto)
  l4 uuid := gen_random_uuid();   -- B editor
  e1 uuid := gen_random_uuid(); e2 uuid := gen_random_uuid();
  e3 uuid := gen_random_uuid(); e4 uuid := gen_random_uuid();
  n int; n2 int; rc int; ok boolean; r boolean;
  s1 uuid := gen_random_uuid(); s2 uuid := gen_random_uuid();
  rep text := '';
begin
  ---------------------------------------------------------------- preparazione (amministratore)
  insert into auth.users (id, email) values
    (ua, 'test-a@example.invalid'), (ub, 'test-b@example.invalid'), (uc, 'test-c@example.invalid');
  insert into public.iscrizioni (user_id, app) values (ua, 'filo'), (ub, 'filo');
  insert into filo.progetti (id, owner_id, nome) values (p1, ua, 'Progetto A');
  insert into filo.lavagne (id, owner_id, titolo, link_pubblico) values
    (l1, ua, 'privata', false), (l2, ua, 'pubblica', true), (l3, ua, 'lettore', false), (l4, ua, 'editor', false);
  insert into filo.membri (lavagna_id, user_id, ruolo) values
    (l3, ub, 'lettore'), (l3, uc, 'editor'), (l4, ub, 'editor');
  insert into filo.elementi (id, lavagna_id, dati) values
    (e1, l1, '{"id":"x1"}'), (e2, l2, '{"id":"x2"}'), (e3, l3, '{"id":"x3"}'), (e4, l4, '{"id":"x4"}');

  ---------------------------------------------------------------- 1) C: invitato ma non iscritto a Filo (aal2)
  execute 'reset role'; perform pg_temp.claims(uc, 'aal2'); execute 'set local role authenticated';
  select count(*) into n from filo.lavagne where not link_pubblico;
  rep := rep || case when n = 0 then '✅ ' else '❌ ' end || 'Utente non iscritto (anche se invitato): non vede lavagne private' || E'\n';
  select count(*) into n from filo.elementi where lavagna_id in (l1, l3, l4);
  rep := rep || case when n = 0 then '✅ ' else '❌ ' end || 'Utente non iscritto: non vede elementi di lavagne private' || E'\n';
  select count(*) into n from filo.progetti;
  rep := rep || case when n = 0 then '✅ ' else '❌ ' end || 'Utente non iscritto: non vede progetti' || E'\n';
  begin insert into filo.lavagne (titolo) values ('intruso'); ok := false; exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Utente non iscritto: non può creare lavagne' || E'\n';
  begin update filo.elementi set dati = '{"id":"hack"}' where id = e3; get diagnostics rc = row_count; ok := (rc = 0); exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Utente non iscritto: non può modificare elementi (anche se è editor)' || E'\n';

  ---------------------------------------------------------------- 2) A con la sola password (aal1)
  execute 'reset role'; perform pg_temp.claims(ua, 'aal1'); execute 'set local role authenticated';
  select count(*) into n from filo.lavagne where not link_pubblico;
  rep := rep || case when n = 0 then '✅ ' else '❌ ' end || 'Solo password (senza codice): il proprietario non legge le sue lavagne' || E'\n';
  select count(*) into n from filo.progetti;
  rep := rep || case when n = 0 then '✅ ' else '❌ ' end || 'Solo password: non legge i progetti' || E'\n';
  begin insert into filo.lavagne (titolo) values ('senza 2FA'); ok := false; exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Solo password: non può creare lavagne' || E'\n';
  begin update filo.elementi set dati = '{"id":"hack"}' where id = e1; get diagnostics rc = row_count; ok := (rc = 0); exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Solo password: non può modificare elementi' || E'\n';
  begin delete from filo.lavagne where id = l1; get diagnostics rc = row_count; ok := (rc = 0); exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Solo password: non può eliminare lavagne' || E'\n';

  ---------------------------------------------------------------- 3) B lettore su l3, editor su l4 (aal2)
  execute 'reset role'; perform pg_temp.claims(ub, 'aal2'); execute 'set local role authenticated';
  select count(*) into n from filo.lavagne where id = l1;
  rep := rep || case when n = 0 then '✅ ' else '❌ ' end || 'Invitato: non vede una lavagna privata non condivisa con lui' || E'\n';
  select count(*) into n from filo.elementi where lavagna_id = l1;
  rep := rep || case when n = 0 then '✅ ' else '❌ ' end || 'Invitato: non vede gli elementi di quella lavagna' || E'\n';
  select count(*) into n from filo.lavagne where id in (l3, l4);
  rep := rep || case when n = 2 then '✅ ' else '❌ ' end || 'Invitato: vede le due lavagne condivise con lui' || E'\n';
  select count(*) into n from filo.progetti;
  rep := rep || case when n = 0 then '✅ ' else '❌ ' end || 'Invitato: non vede i progetti del proprietario' || E'\n';
  select count(*) into n from filo.membri where user_id = uc;
  rep := rep || case when n = 0 then '✅ ' else '❌ ' end || 'Invitato: non vede gli altri membri delle lavagne' || E'\n';
  -- lettore (l3)
  begin update filo.elementi set dati = '{"id":"hack"}' where id = e3; get diagnostics rc = row_count; ok := (rc = 0); exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Lettore: non può modificare elementi' || E'\n';
  begin insert into filo.elementi (lavagna_id, dati) values (l3, '{"id":"nuovo"}'); ok := false; exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Lettore: non può aggiungere elementi' || E'\n';
  begin delete from filo.elementi where id = e3; get diagnostics rc = row_count; ok := (rc = 0); exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Lettore: non può eliminare elementi' || E'\n';
  begin update filo.lavagne set titolo = 'hack' where id = l3; get diagnostics rc = row_count; ok := (rc = 0); exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Lettore: non può cambiare il titolo' || E'\n';
  -- editor (l4)
  begin update filo.elementi set dati = '{"id":"x4","m":1}' where id = e4; get diagnostics rc = row_count; ok := (rc = 1); exception when others then ok := false; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Editor: può modificare gli elementi' || E'\n';
  begin insert into filo.elementi (lavagna_id, dati) values (l4, '{"id":"nuovo"}'); ok := true; exception when others then ok := false; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Editor: può aggiungere elementi' || E'\n';
  begin update filo.lavagne set titolo = 'ok' where id = l4; get diagnostics rc = row_count; ok := (rc = 1); exception when others then ok := false; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Editor: può cambiare il titolo' || E'\n';
  begin update filo.lavagne set link_pubblico = true where id = l4; ok := false; exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Editor: non può attivare il link pubblico' || E'\n';
  begin update filo.lavagne set owner_id = ub where id = l4; ok := false; exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Editor: non può diventare proprietario' || E'\n';
  begin update filo.lavagne set progetto_id = p1 where id = l4; ok := false; exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Editor: non può spostare la lavagna nel progetto del proprietario' || E'\n';
  begin delete from filo.lavagne where id = l4; get diagnostics rc = row_count; ok := (rc = 0); exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Editor: non può eliminare la lavagna' || E'\n';
  begin insert into filo.membri (lavagna_id, user_id, ruolo) values (l4, uc, 'lettore'); ok := false; exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Editor: non può condividere la lavagna con altri' || E'\n';
  begin update filo.membri set ruolo = 'editor' where lavagna_id = l3 and user_id = ub; get diagnostics rc = row_count; ok := (rc = 0); exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Lettore: non può promuoversi a editor' || E'\n';
  begin perform filo.condividi(l4, 'test-c@example.invalid', 'lettore'); ok := false; exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Editor: la funzione di condivisione per email è negata' || E'\n';
  -- B con la sola password sulla lavagna dove è editor
  execute 'reset role'; perform pg_temp.claims(ub, 'aal1'); execute 'set local role authenticated';
  begin update filo.elementi set dati = '{"id":"hack"}' where id = e4; get diagnostics rc = row_count; ok := (rc = 0); exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Editor con sola password: non può modificare' || E'\n';
  select count(*) into n from filo.elementi where lavagna_id = l4;
  rep := rep || case when n = 0 then '✅ ' else '❌ ' end || 'Editor con sola password: non legge gli elementi' || E'\n';

  ---------------------------------------------------------------- 4) visitatore anonimo (link pubblico)
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
  select count(*) into n from filo.lavagne;
  rep := rep || case when n = 1 then '✅ ' else '❌ ' end || 'Anonimo: vede solo la lavagna con link pubblico (' || n || ')' || E'\n';
  select count(*) into n from filo.elementi where lavagna_id <> l2;
  rep := rep || case when n = 0 then '✅ ' else '❌ ' end || 'Anonimo: non vede gli elementi delle altre lavagne' || E'\n';
  select count(*) into n from filo.elementi where lavagna_id = l2;
  rep := rep || case when n = 1 then '✅ ' else '❌ ' end || 'Anonimo: legge gli elementi della lavagna pubblica' || E'\n';
  begin perform 1 from filo.membri; ok := false; exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Anonimo: non legge le condivisioni' || E'\n';
  begin perform 1 from filo.progetti; ok := false; exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Anonimo: non legge i progetti' || E'\n';
  begin update filo.elementi set dati = '{"id":"hack"}' where id = e2; ok := false; exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Anonimo: non può modificare la lavagna pubblica' || E'\n';
  begin insert into filo.elementi (lavagna_id, dati) values (l2, '{"id":"nuovo"}'); ok := false; exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Anonimo: non può aggiungere elementi' || E'\n';
  begin perform 1 from public.iscrizioni; ok := false; exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Anonimo: non legge le iscrizioni' || E'\n';

  ---------------------------------------------------------------- 5) A (proprietario, aal2): normale, poi disattiva il link
  execute 'reset role'; perform pg_temp.claims(ua, 'aal2'); execute 'set local role authenticated';
  select count(*) into n from filo.lavagne where owner_id = ua;
  rep := rep || case when n = 4 then '✅ ' else '❌ ' end || 'Proprietario con 2FA: vede tutte le sue lavagne' || E'\n';
  begin update filo.lavagne set link_pubblico = false where id = l2; get diagnostics rc = row_count; ok := (rc = 1); exception when others then ok := false; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Proprietario: può disattivare il link pubblico' || E'\n';
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
  select count(*) into n from filo.lavagne;
  rep := rep || case when n = 0 then '✅ ' else '❌ ' end || 'Anonimo: dopo la disattivazione il link non mostra più nulla' || E'\n';

  ---------------------------------------------------------------- 5b) misure del cronometro (si eseguono solo se lo script 09 è stato lanciato)
  execute 'reset role';
  if to_regclass('filo.misure') is null then
    rep := rep || '⚠️ Misure del cronometro: script 09 non ancora eseguito (test saltati)' || E'\n';
  else
    insert into filo.misure (lavagna_id, user_id, sessione, nodo_id, inizio, fine, durata_s) values
      (l4, ub, s1, 'n1', now(), now(), 5),     -- misura di B (editor) su l4
      (l3, ua, s2, 'n2', now(), now(), 7);     -- misura di A su l3 (dove B è solo lettore)
    -- C: invitato ma non iscritto
    execute 'reset role'; perform pg_temp.claims(uc, 'aal2'); execute 'set local role authenticated';
    select count(*) into n from filo.misure;
    rep := rep || case when n = 0 then '✅ ' else '❌ ' end || 'Misure: utente non iscritto non le legge' || E'\n';
    begin insert into filo.misure (lavagna_id, sessione, nodo_id, inizio, fine, durata_s) values (l3, s2, 'x', now(), now(), 1); ok := false; exception when others then ok := true; end;
    rep := rep || case when ok then '✅ ' else '❌ ' end || 'Misure: utente non iscritto non può registrare' || E'\n';
    -- B: editor su l4, lettore su l3
    execute 'reset role'; perform pg_temp.claims(ub, 'aal2'); execute 'set local role authenticated';
    select count(*) into n from filo.misure where lavagna_id = l4;
    rep := rep || case when n = 1 then '✅ ' else '❌ ' end || 'Misure: l''editor legge le misure della sua lavagna' || E'\n';
    select count(*) into n from filo.misure where lavagna_id = l3;
    rep := rep || case when n = 0 then '✅ ' else '❌ ' end || 'Misure: il lettore non legge le misure' || E'\n';
    begin insert into filo.misure (lavagna_id, sessione, nodo_id, inizio, fine, durata_s) values (l4, s1, 'n9', now(), now(), 3); ok := true; exception when others then ok := false; end;
    rep := rep || case when ok then '✅ ' else '❌ ' end || 'Misure: l''editor può registrare' || E'\n';
    begin insert into filo.misure (lavagna_id, sessione, nodo_id, inizio, fine, durata_s) values (l3, s1, 'n8', now(), now(), 3); ok := false; exception when others then ok := true; end;
    rep := rep || case when ok then '✅ ' else '❌ ' end || 'Misure: il lettore non può registrare' || E'\n';
    begin insert into filo.misure (lavagna_id, user_id, sessione, nodo_id, inizio, fine, durata_s) values (l4, ua, s1, 'n7', now(), now(), 3); ok := false; exception when others then ok := true; end;
    rep := rep || case when ok then '✅ ' else '❌ ' end || 'Misure: non si possono registrare misure a nome di un altro utente' || E'\n';
    begin update filo.misure set durata_s = 1 where lavagna_id = l4; ok := false; exception when others then ok := true; end;
    rep := rep || case when ok then '✅ ' else '❌ ' end || 'Misure: le misure non si modificano' || E'\n';
    -- B con la sola password
    execute 'reset role'; perform pg_temp.claims(ub, 'aal1'); execute 'set local role authenticated';
    select count(*) into n from filo.misure;
    rep := rep || case when n = 0 then '✅ ' else '❌ ' end || 'Misure: con la sola password non si leggono' || E'\n';
    -- anonimo
    execute 'reset role';
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    begin perform 1 from filo.misure; ok := false; exception when others then ok := true; end;
    rep := rep || case when ok then '✅ ' else '❌ ' end || 'Misure: l''anonimo non le legge' || E'\n';
    -- A proprietario: legge tutto e può cancellare
    execute 'reset role'; perform pg_temp.claims(ua, 'aal2'); execute 'set local role authenticated';
    select count(*) into n from filo.misure where lavagna_id in (l3, l4);
    rep := rep || case when n >= 3 then '✅ ' else '❌ ' end || 'Misure: il proprietario legge quelle delle sue lavagne' || E'\n';
    begin delete from filo.misure where lavagna_id = l4; get diagnostics rc = row_count; ok := (rc >= 2); exception when others then ok := false; end;
    rep := rep || case when ok then '✅ ' else '❌ ' end || 'Misure: il proprietario può cancellarle' || E'\n';
  end if;

  ---------------------------------------------------------------- 6) eliminazione account
  execute 'reset role'; perform pg_temp.claims(ua, 'aal1'); execute 'set local role authenticated';
  begin perform filo.elimina_account(); ok := false; exception when others then ok := true; end;
  rep := rep || case when ok then '✅ ' else '❌ ' end || 'Eliminazione account: negata con la sola password' || E'\n';
  execute 'reset role'; perform pg_temp.claims(ua, 'aal2'); execute 'set local role authenticated';
  begin r := filo.elimina_account(); ok := coalesce(r, false); exception when others then ok := false; end;
  execute 'reset role';
  select count(*) into n from filo.lavagne where owner_id = ua;
  select count(*) into n2 from auth.users where id = ua;
  rep := rep || case when ok and n = 0 and n2 = 0 then '✅ ' else '❌ ' end || 'Eliminazione account: cancella lavagne e utente' || E'\n';
  select count(*) into n from filo.elementi where lavagna_id in (l1, l2, l3, l4);
  rep := rep || case when n = 0 then '✅ ' else '❌ ' end || 'Eliminazione account: cancella anche gli elementi' || E'\n';
  select count(*) into n from filo.membri where lavagna_id in (l3, l4);
  rep := rep || case when n = 0 then '✅ ' else '❌ ' end || 'Eliminazione account: cancella anche le condivisioni' || E'\n';

  ---------------------------------------------------------------- rapporto (l'errore annulla TUTTO, compresi i dati finti)
  raise exception E'\n\nRISULTATO TEST DI SICUREZZA\n===========================\n%\n(Questo "errore" è voluto: serve ad annullare i dati di prova. Tutte le righe devono essere ✅.)\n', rep;
end
$test$;
