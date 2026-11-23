# Regole di progettazione app — fccowork.it

Istruzioni da applicare a ogni nuova app. Se una regola va cambiata, si modifica questo file, non la singola app.

---

## 1. Architettura

- **Sito vetrina:** `fccowork.it`. Pubblico, senza login. Contiene biografia e catalogo delle app, ognuna con un link al suo sottodominio.
- **App:** una per sottodominio (`filo.fccowork.it`, `taskify.fccowork.it`, ...).
- **Hosting:** GitHub Pages, un repository per ogni app, più un repository per la vetrina (`fabriziocuozzo.github.io`).
- **Dominio e DNS:** Aruba. Ogni nuova app richiede un solo record CNAME: `nomeapp` → `fabriziocuozzo.github.io`.
- **Database e login:** Supabase (Postgres + Auth).
- **Le app sono indipendenti:** non condividono sessione, cookie, home o interfaccia. Ognuna ha la sua home interna dopo il login.

## 2. Database (Supabase)

### 2.1 Modello
- Un solo progetto Supabase per tutte le app (piano gratuito).
- Un **schema Postgres per ogni app** (`filo`, `taskify`, ...). Le tabelle dell'app vivono nel suo schema.
- Se un'app diventa commerciale o ha molti utenti, si sposta in un progetto Supabase dedicato.

### 2.2 Tabelle comuni (schema `public`)
- `iscrizioni`: `user_id`, `app`, `creata_il`. Dice a quali app ha accesso un utente.
- Funzione `public.ha_app(nome_app text)`: restituisce vero se l'utente corrente è iscritto all'app.

### 2.3 Tabelle di ogni app (esempio per Filo)
- `filo.progetti`: `id`, `owner_id`, `nome`, `creata_il`. Un progetto raggruppa più lavagne (come una cartella).
- `filo.lavagne`: `id`, `owner_id`, `progetto_id` (facoltativo: una lavagna può non avere progetto), `titolo`, `link_pubblico` (booleano), `creata_il`, `modificata_il`.
- `filo.elementi`: `id`, `lavagna_id`, `dati` (JSONB), `versione`, `modificata_il`. Il contenuto della lavagna è **una riga per elemento**, non un unico JSON: così due persone che lavorano insieme su elementi diversi non si sovrascrivono.
- `filo.membri`: `lavagna_id`, `user_id`, `ruolo` (`lettore` | `editor`).
- Il contenuto variabile va in colonne JSONB. Le colonne usate per filtrare e ordinare (titolo, date, proprietario) restano colonne normali.

### 2.4 Regole RLS (obbligatorie)
- **RLS attiva su ogni tabella, senza eccezioni.** Una tabella senza RLS non va pubblicata.
- Un utente vede una riga solo se: è iscritto all'app **e** (è il proprietario **oppure** compare in `membri`).
- Ogni regola richiede anche che la sessione abbia superato la verifica in due passaggi (`aal2`, vedi sezione 3.2). Fa eccezione solo la lettura tramite link pubblico, che non richiede login.
- Un `lettore` può solo leggere. Un `editor` può leggere e modificare. Solo il proprietario può eliminare e gestire le condivisioni.
- Il link pubblico in sola lettura è consentito solo se `link_pubblico` è vero.
- Il controllo dei permessi sta nel database, mai solo nell'interfaccia.

## 3. Login e sicurezza

### 3.1 Registrazione e password
- Login con Supabase Auth, con **email e password**.
- Regole della password, impostate **nelle impostazioni di Supabase Auth** (valgono sul server, non solo nella pagina):
  - lunghezza minima **8** caratteri (consigliati 12)
  - obbligatori: **lettere maiuscole, minuscole, cifre e caratteri speciali**
- La pagina mostra le stesse regole mentre l'utente scrive, solo per aiutarlo: il controllo vero è quello di Supabase.
- Conferma dell'indirizzo email obbligatoria alla registrazione.
- Funzione "Password dimenticata" con link via email e pagina per scegliere la nuova password (l'indirizzo va nei Redirect URLs di Supabase).
- Alla prima registrazione in un'app, l'utente viene aggiunto a `iscrizioni` per quell'app.
- Le email di sistema (conferma registrazione, recupero password) partono da `noreply@fccowork.it` tramite SMTP personalizzato (Resend, dominio verificato su Aruba). I modelli si impostano in Authentication → Emails → Templates e sono **unici per tutto il progetto Supabase**: con più app vanno resi neutri o differenziati. I modelli di Filo sono nella cartella `email/`.

### 3.2 Verifica in due passaggi (obbligatoria)
- Tipo: app di autenticazione (TOTP), con **QR code** da inquadrare con Google Authenticator, Microsoft Authenticator o simili.
- **Obbligatoria per tutti gli utenti.** Chi ha fatto solo email e password (livello `aal1`) non entra nell'app: viene portato alla configurazione o al codice.
- **Almeno un dispositivo per utente, consigliati due:** uno principale (obbligatorio) e uno di riserva (facoltativo, ma raccomandato). La configurazione guida a registrare il principale e propone la riserva, con pulsante "Salta, lo faccio dopo". Ogni dispositivo ha il suo QR code e un primo codice di conferma. Finché c'è un solo dispositivo, la home mostra un promemoria per aggiungere la riserva.
- Flusso:
  1. Registrazione → conferma email.
  2. Primo accesso → configurazione dispositivo 1 (QR, codice di conferma) → proposta del dispositivo 2 (si può saltare).
  3. Accessi successivi → email e password → codice a 6 cifre (da uno dei due dispositivi) → home.
- Scheda "Sicurezza account" nell'app: elenco dei dispositivi registrati, aggiunta e rimozione. Non si può rimuovere l'ultimo dispositivo.
- **Obbligo nel database:** ogni regola RLS delle tabelle con dati richiede la sessione di livello `aal2` (controllo `auth.jwt()->>'aal' = 'aal2'`). Così, anche chiamando il database senza passare dall'app, la sola password non basta.
- Telefono perso o cambiato: si usa il dispositivo di riserva, se registrato. Se non c'è una riserva o sono persi tutti i dispositivi, **reset manuale da amministratore** (rimozione dei dispositivi dalla dashboard di Supabase) dopo aver verificato l'identità dell'utente.
- L'autenticazione a più fattori con app (TOTP) va attivata nelle impostazioni di Authentication di Supabase.

### 3.3 Regole generali di sicurezza
- Non si implementano sistemi di login propri: si usa sempre Supabase Auth.
- Nel codice delle pagine si usa **solo la chiave pubblica `anon`**. La chiave `service_role` non compare mai in nessun file, repository o chat.
- Repository GitHub Pages pubblici: niente password, token o dati personali nel codice.
- Prima di mettere dati reali, test di sicurezza: un utente non iscritto o non invitato non deve riuscire a leggere né scrivere nulla.

## 4. Home interna dell'app

Dopo il login si arriva sulla home dell'app, non sull'editor.
- Sezioni: **Recenti**, **Progetti** (le cartelle: un click le apre e mostra le lavagne dentro), **Condivise con me**.
- Pulsanti **Nuova lavagna** (con scelta del progetto) e **Nuovo progetto**.
- Collaborazione: più utenti possono aprire la stessa lavagna e vedere le modifiche degli altri quasi in tempo reale (Supabase Realtime). Chi ha il permesso di sola lettura vede gli aggiornamenti ma non può modificare.
- Ogni elemento mostra titolo, ultima modifica e un badge del permesso (`può leggere` / `può modificare`) se condiviso.
- Ricerca testuale e pulsante **Nuovo**.
- Un click apre l'elemento nell'editor.
- Condivisione: finestra "Condividi" con email e scelta tra *Può leggere* e *Può modificare*; il permesso si cambia o si toglie in qualsiasi momento.

## 5. Layout e grafica

- **Tema chiaro** di default, con accento **azzurro/blu**.
- Palette di base (variabili CSS, da usare sempre al posto di colori scritti a mano):
  - `--accento: #2563eb`
  - `--accento-chiaro: #dbeafe`
  - `--sfondo: #f8fafc`
  - `--superficie: #ffffff`
  - `--testo: #0f172a`
  - `--testo-secondario: #64748b`
  - `--bordo: #e2e8f0`
- Font di sistema (nessun font esterno), angoli arrotondati a 8–12 px, ombre leggere.
- Componenti ricorrenti uguali in tutte le app: barra superiore con nome app e menu utente, schede (card) per gli elementi, finestre modali, notifiche in alto a destra.
- Layout **responsive**: pensato per il telefono prima, poi per desktop.
- Testi dell'interfaccia in italiano.
- **Prima di sviluppare una schermata nuova si prepara un mockup**, da approvare.

## 6. Struttura del codice

- Ogni app è una pagina HTML con CSS e JavaScript nello stesso file, salvo che la complessità non richieda di dividerla.
- Un file `config` in cima alla pagina con URL Supabase, chiave `anon` e nome dell'app (schema).
- Versione dell'app visibile in un punto fisso (es. nel menu utente).
- I file devono funzionare al primo avvio, senza passaggi di installazione per l'utente.
- Esportazione e importazione JSON sempre disponibili, per avere una copia dei propri dati.

## 7. Privacy e uso commerciale

- Ogni app aperta a utenti esterni ha privacy policy, informativa e consenso al trattamento dei dati (GDPR).
- Funzione per eliminare l'account e i propri dati.
- Per l'uso commerciale i testi legali vanno fatti controllare da un professionista.
- Il piano gratuito di Supabase mette in pausa i progetti dopo 1 settimana di inattività: con utenti reali si passa al piano Pro.

## 8. Come si lavora con Claude Code

1. Questo file sta nella radice di ogni repository, come `CLAUDE.md` o `REGOLE.md`, così viene letto a ogni sessione.
2. Per una nuova app: si descrive l'idea, si approva il mockup, si crea lo schema SQL, poi il codice.
3. Ogni modifica al database passa da uno script SQL salvato nel repository, in una cartella `sql/`.
4. Al termine di ogni app si esegue la checklist qui sotto.

## 9. Checklist nuova app

- [x] Repository GitHub creato e Pages attivo
- [x] Record CNAME su Aruba e dominio personalizzato su GitHub
- [x] HTTPS attivo
- [x] Schema Postgres dell'app creato
- [x] RLS attiva su tutte le tabelle e testata con un secondo utente
- [x] Iscrizione all'app alla registrazione
- [x] Regole password impostate in Supabase (min. 8, maiuscole, minuscole, cifre, simboli)
- [x] Conferma email e "password dimenticata" funzionanti
- [x] Verifica in due passaggi obbligatoria, con almeno 1 dispositivo (QR code) e riserva consigliata
- [x] RLS con controllo `aal2` su tutte le tabelle con dati
- [x] Prova: un utente con la sola password non legge né scrive nulla
- [x] Home interna con Recenti / Creati da me / Condivisi con me
- [x] Condivisione con permessi lettura/modifica
- [x] Tema, palette e componenti come da sezione 5
- [x] Verifica da telefono
- [x] App aggiunta al catalogo della vetrina
