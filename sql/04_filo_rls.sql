-- 04 · Regole RLS dello schema filo
-- Ogni regola per utenti loggati richiede filo.sessione_ok() = iscritto a Filo + aal2.
-- Unica eccezione: lettura tramite link pubblico (anon), solo se link_pubblico = true.

-- ---------- progetti: solo il proprietario ----------
drop policy if exists progetti_select on filo.progetti;
create policy progetti_select on filo.progetti for select to authenticated
  using (filo.sessione_ok() and owner_id = auth.uid());

drop policy if exists progetti_insert on filo.progetti;
create policy progetti_insert on filo.progetti for insert to authenticated
  with check (filo.sessione_ok() and owner_id = auth.uid());

drop policy if exists progetti_update on filo.progetti;
create policy progetti_update on filo.progetti for update to authenticated
  using (filo.sessione_ok() and owner_id = auth.uid())
  with check (filo.sessione_ok() and owner_id = auth.uid());

drop policy if exists progetti_delete on filo.progetti;
create policy progetti_delete on filo.progetti for delete to authenticated
  using (filo.sessione_ok() and owner_id = auth.uid());

-- ---------- lavagne ----------
drop policy if exists lavagne_select on filo.lavagne;
create policy lavagne_select on filo.lavagne for select to authenticated
  using (filo.sessione_ok() and filo.ruolo_lavagna(id) is not null);

drop policy if exists lavagne_select_pubblico on filo.lavagne;
create policy lavagne_select_pubblico on filo.lavagne for select to anon, authenticated
  using (link_pubblico);

drop policy if exists lavagne_insert on filo.lavagne;
create policy lavagne_insert on filo.lavagne for insert to authenticated
  with check (filo.sessione_ok() and owner_id = auth.uid());

-- proprietario ed editor modificano; i campi riservati sono protetti dal trigger
drop policy if exists lavagne_update on filo.lavagne;
create policy lavagne_update on filo.lavagne for update to authenticated
  using (filo.sessione_ok() and filo.ruolo_lavagna(id) in ('proprietario', 'editor'))
  with check (filo.sessione_ok() and filo.ruolo_lavagna(id) in ('proprietario', 'editor'));

drop policy if exists lavagne_delete on filo.lavagne;
create policy lavagne_delete on filo.lavagne for delete to authenticated
  using (filo.sessione_ok() and owner_id = auth.uid());

-- ---------- elementi ----------
drop policy if exists elementi_select on filo.elementi;
create policy elementi_select on filo.elementi for select to authenticated
  using (filo.sessione_ok() and filo.ruolo_lavagna(lavagna_id) is not null);

drop policy if exists elementi_select_pubblico on filo.elementi;
create policy elementi_select_pubblico on filo.elementi for select to anon, authenticated
  using (filo.lavagna_pubblica(lavagna_id));

drop policy if exists elementi_insert on filo.elementi;
create policy elementi_insert on filo.elementi for insert to authenticated
  with check (filo.sessione_ok() and filo.ruolo_lavagna(lavagna_id) in ('proprietario', 'editor'));

drop policy if exists elementi_update on filo.elementi;
create policy elementi_update on filo.elementi for update to authenticated
  using (filo.sessione_ok() and filo.ruolo_lavagna(lavagna_id) in ('proprietario', 'editor'))
  with check (filo.sessione_ok() and filo.ruolo_lavagna(lavagna_id) in ('proprietario', 'editor'));

-- Cancellare un elemento è una normale modifica del contenuto: consentito anche all'editor.
drop policy if exists elementi_delete on filo.elementi;
create policy elementi_delete on filo.elementi for delete to authenticated
  using (filo.sessione_ok() and filo.ruolo_lavagna(lavagna_id) in ('proprietario', 'editor'));

-- ---------- membri: solo il proprietario gestisce; ognuno vede la propria riga ----------
drop policy if exists membri_select on filo.membri;
create policy membri_select on filo.membri for select to authenticated
  using (filo.sessione_ok()
         and (user_id = auth.uid() or filo.ruolo_lavagna(lavagna_id) = 'proprietario'));

drop policy if exists membri_insert on filo.membri;
create policy membri_insert on filo.membri for insert to authenticated
  with check (filo.sessione_ok() and filo.ruolo_lavagna(lavagna_id) = 'proprietario');

drop policy if exists membri_update on filo.membri;
create policy membri_update on filo.membri for update to authenticated
  using (filo.sessione_ok() and filo.ruolo_lavagna(lavagna_id) = 'proprietario')
  with check (filo.sessione_ok() and filo.ruolo_lavagna(lavagna_id) = 'proprietario');

drop policy if exists membri_delete on filo.membri;
create policy membri_delete on filo.membri for delete to authenticated
  using (filo.sessione_ok() and filo.ruolo_lavagna(lavagna_id) = 'proprietario');
