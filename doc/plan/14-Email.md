# 14 – Automatischer E-Mail-Versand (UI & Workflow)

> **Abgrenzung:** Die technische Grundlage (Brevo-Anbindung, Queue, Rate-Limiter, Retry, Circuit Breaker, Templates) ist bereits entschieden und umgesetzt – siehe `3-automailer.md` §1 sowie `job_o_matic/lib/data/services/email/`. Dieses Dokument beschreibt die **Benutzeroberfläche, den Versand-Workflow und die E-Mail-Adress-Ermittlung**.

## Aktueller Stand

### Backend (implementiert)

| Komponente | Datei | Status |
|------------|-------|--------|
| Brevo-REST-Anbindung (`/v3/smtp/email`) | `lib/data/services/email/email_service.dart` | ✅ |
| Queue mit Statusmodell (`pending`/`sent`/`failed`) | `lib/data/services/email/mail_queue_service.dart` | ✅ |
| Dispatcher mit Rate-Limit & Circuit Breaker | `lib/data/services/email/mail_dispatcher.dart` | ✅ |
| E-Mail-Vorlagen (Betreff/Body) | `lib/data/services/email/email_template_service.dart` | ✅ |
| Brevo-API-Key | Hinterlegt (`ApiKeyService.brevoApiKey`, Secure Storage) | ✅ |

### Bekannte Lücken im Backend (vor der UI zu schließen)

| Nr. | Lücke | Auswirkung | Lösungsvorschlag |
|-----|-------|------------|------------------|
| 1 | `MailDispatcher._sendEmail()` übergibt **keine Anhänge** – `pdfPath` wird entgegengenommen, aber ignoriert | PDF würde nie mitgesendet | `EmailAttachment` aus Datei laden und an `EmailService.sendEmail()` durchreichen |
| 2 | **Kein Dublettenschutz** – dieselbe Bewerbung kann mehrfach in die Queue gelangen | Versehentlicher Mehrfachversand an HR | Guard: Versand nur bei Status-Übergang, `MailQueueEntry` mit `applicationId` deduplizieren |
| 3 | Standard-Absender `noreply@job-o-matic.local` ist bei Brevo **nicht verifiziert** | Ablehnung durch Brevo (401) bzw. Spam-Verdacht | ✅ **Gelöst:** verifizierte Absenderadresse `kleitmiandefoot@gmail.com` vorhanden (siehe „Absenderkonfiguration“) |
| 4 | `ApplicationStatus` kennt keinen Versand-Zustand | UI kann „gesendet“ nicht anzeigen | Neues Feld `emailStatus` an `Application` (Entscheidung: eigenes Feld, siehe „Entscheidungen“) + DB-Migration |
| 5 | Queue lebt nur in-memory (`MailQueueEntry`), App-Neustart verliert pending Einträge | Verlorene Sendungen | Persistenz der Queue in SQLite (siehe `6-Datenbank-Persistenz.md`) |

## Absenderkonfiguration (Brevo)

Verifizierte Absenderidentität (Entscheidung siehe unten):

| Parameter | Wert |
|-----------|------|
| Versand-E-Mail-Adresse | `kleitmiandefoot@gmail.com` *(zugleich Antwortadresse für Rückantworten – siehe Hinweis unten)* |
| SMTP-Relay-Server | `smtp-relay.brevo.com` |
| SMTP-Port | `587` (STARTTLS) |
| SMTP-Login | `b16d96001@smtp-brevo.com` *(vor Commit des Repos ggf. ebenfalls entfernen – Zugangsdaten gehören in die App, nicht in die Doku)* |
| SMTP-Passwort | **Nicht in diesem Dokument** – wird beim ersten Versand über `ApiKeyService` in Secure Storage abgelegt (neue Keys `brevo_smtp_login`, `brevo_smtp_password`) |

> **Antwort-/Reply-Adresse:** Brevo setzt ohne explizites `replyTo` die Absenderadresse als Antwortadresse ein – Rückantworten von Arbeitgebern landen also direkt im Postfach von `kleitmiandefoot@gmail.com`. Das ist beabsichtigt, setzt aber voraus, dass dieses Postfach dem Nutzer gehört und aktiv überwacht wird (kein `noreply`-Blackhole). `EmailService.sendEmail()` setzt `replyTo` zusätzlich explizit – gleiche Adresse wie `sender`, Name aus CV-Daten (siehe Umsetzungsplan Phase A).

> **Sicherheitshinweis:** SMTP-Login/Passwort sind Zugangsdaten wie ein API-Key und dürfen nicht im Repository (auch nicht in Klartext-Docs, `.env` oder Config-Dateien) landen. In der App gilt: `flutter_secure_storage` wie bei den übrigen API-Keys (siehe `6-Datenbank-Persistenz.md` §ApiKeyService).

> **Hinweis REST vs. SMTP:** Die primäre Sendestrecke bleibt die Brevo-REST-API (`EmailService`, bereits implementiert). Das SMTP-Relay steht als Fallback-Kanal bereit (z. B. falls das REST-Tageslimit erreicht ist oder für „Als Entwurf exportieren“). Absendername: aus CV-Daten ableitbar („Vor- und Nachname via Job-O-Matic“).


## Anforderungen (Workflow)

| Nr. | Anforderung | Priorität |
|-----|-------------|-----------|
| 1 | Versenden als **separater Bildschirm** (Screen 4) mit Vorschau, Empfänger und Status je Bewerbung | 🟢 Muss |
| 2 | **Sammelversand** aller neu erstellten (noch nicht gesendeten) Bewerbungen mit einem Klick | 🟢 Muss |
| 3 | **Erneuter Versand** einzelner Bewerbungen per Auswahl in der Ergebnisübersicht (`/applications`) bzw. Detailansicht (`/applications/:id`) | 🟢 Muss |
| 4 | Option **„Erstellen & Versenden in einem Arbeitsschritt“** (Direktversand nach erfolgreicher Generierung) | 🟡 Soll |
| 5 | Automatische **E-Mail-Adress-Ermittlung** (Kaskade, siehe unten), sonst manuelle Eingabe im Versand-Dialog | 🟡 Soll |
| 6 | Automatisches Ausfüllen von Bewerberportalen | 🔴 Kann – siehe `3-automailer.md` §2 |

## Neuer Bildschirm: Versand (`/send`)

| Element | Beschreibung |
|---------|--------------|
| Route | `/send` (neu, analog Screen 3 in `2-Workflow.md` registrieren) |
| Liste | Alle Bewerbungen mit Status `completed`/`exported`, Checkbox pro Eintrag |
| Vorschau | Betreff + Body (aus `EmailTemplateService`) je Eintrag, editierbar vor dem Versand |
| Empfänger | Automatisch ermittelt oder manuell überschreibbar; Validierung (RFC 5322) |
| Aktionen | „Ausgewählte senden“, „Alle neuen senden“, „Als Entwurf exportieren“ (Fallback) |
| Statusanzeige | `MailDispatcherStats` (pending/sent/failed, Circuit-Breaker-Zustand) live via Riverpod |
| Guards | Redirect zurück, wenn keine versandfähigen Bewerbungen oder kein API-Key (→ `/settings`) |

Statusmodell je Bewerbung (Erweiterung von `2-Workflow.md`):

```
completed ──► ready ──► queued ──► sending ──► sent
                │                     └──────► failed ──► (retry) / manuell
                └── (keine Adresse) ► needs_address
```

> **Erläuterung:** `ready` und `needs_address` sind **abgeleitete UI-Zustände**, kein Teil des gespeicherten `emailStatus`. Persistiert wird nur `emailStatus` in `new`/`queued`/`sending`/`sent`/`failed`. Die E-Mail-Adresse wird beim Übergang `completed → ready` über die Kaskade (Stufen 1–3) **aus der Anzeige** ermittelt; bleibt sie leer, landet die Bewerbung in `needs_address` und die Adresse wird manuell (Stufe 4) erfasst.

## E-Mail-Adress-Ermittlung (Kaskade)

Wichtig: Scraping beschränkt sich auf die **öffentlich angegebene Kontaktseite der Stellenanzeige** – kein Crawlen über die gesamte Domain, keine Massenabfragen (UWG/DSGVO-Risiko minimieren).

| Stufe | Strategie | Umsetzung |
|-------|-----------|-----------|
| 1 | Bereits erfasste Daten (`Application.companyAddress`, `jobDescription`) | Regex auf E-Mail-Muster in gespeicherten Daten – kein neuer Netzwerkzugriff |
| 2 | `mailto:`-Link der Stellenanzeige | Seite erneut laden (bestehender `JobScraperService`), `mailto:` aus HTML extrahieren |
| 3 | Kontaktseite verfolgen | Nur wenn Stufe 2 leer: genau ein weiterer Link (`Kontakt`/`Impressum`/`Karriere`) folgen und dort suchen – max. 1 Zusatz-Request mit Timeout |
| 4 | Manuell | Versand-Dialog zeigt Eingabefeld + Hinweis „Adresse nicht gefunden“; gefundene Adresse wird an der `Application` persistiert, damit Stufen 1–3 beim Wiederholungsversand entfallen |

Technische Basis: `html`-Paket ist bereits Dependency (siehe `5-API-Anbindung.md` Phase 4); bei CAPTCHA/Blocker → Abbruch und Sprung zu Stufe 4.

## Bewerberportale automatisch ausfüllen

Diese Frage ist in `3-automailer.md` §2 bereits beantwortet und entschieden:

1. **Phase 1** (dieses Dokument): E-Mail-Versand für Stellen mit direktem E-Mail-Kontakt
2. **Phase 2:** Browser-Extension – Nutzer öffnet das Portal selbst, Extension füllt vor
3. **Phase 3:** Playwright-Skripte für unterstützte Portale (nur nach rechtlicher Prüfung)

CAPTCHAs werden **nicht** umgangen (Abbruch + manuelles Eingreifen, siehe Entscheidungsmatrix in `3-automailer.md`). Für diesen Sprint ist **kein** Portal-Autofill vorgesehen.

## Fehlerbehandlung

| Fall | Reaktion |
|------|----------|
| Kein Brevo-API-Key | Redirect zu `/settings` mit Hinweis-Banner |
| Brevo HTTP 429 / Tageslimit (300/Tag Free-Tier) | Rate-Limiter greift vorab; Rest-Menge bleibt `pending`, Hinweis im Versand-Screen |
| Circuit Breaker OPEN | Versand-Aktionen deaktiviert, Status + Retry-Zeitpunkt anzeigen |
| Einer der Anhänge fehlt (z. B. `pdfPath == null`) | Eintrag überspringen und als `failed` markieren („PDF fehlt – neu generieren“) |
| Adresse nicht ermittelbar | Status `needs_address`, manuelle Eingabe im Dialog |
| Versand fehlgeschlagen (401 – Absender nicht verifiziert) | Fallback „Als Entwurf exportieren“ |
| App-Neustart mit offener Queue | Nach Queue-Persistenz: pending Einträge erneut anbieten – **kein** stiller Auto-Versand beim Start, Nutzer bestätigt erneut |

## Umsetzungsschritte

- [ ] **Backend-Gap 1:** Anhänge (CV-PDF + Anschreiben-PDF **getrennt**) + CC/BCC in `MailDispatcher`/`EmailService` verdrahten (PDF als Base64)
- [ ] **Backend-Gap 2:** Dublettenschutz per History-Prüfung gegen `sent_email_log` + Bestätigungsdialog beim Wieder-/Sammelversand
- [ ] **Backend-Gap 3:** Absender umstellen auf `kleitmiandefoot@gmail.com` (Default in `EmailService` ersetzen, SMTP-Passwort via Secure Storage – siehe „Absenderkonfiguration“)
- [ ] **Backend-Gap 4/5:** `emailStatus` (eigenes Feld, siehe Entscheidungen) an `Application` + DB-Migration; Queue in SQLite persistieren
- [ ] **Versand-Audit-Log:** Tabelle `sent_email_log` anlegen (Schema siehe Entscheidungen) und bei jedem Versand **und „Als Entwurf exportieren“** beschreiben; Retention 6 Monate + „Verlauf löschen“
- [ ] **Screen 4 `/send`** mit Riverpod-State (`mailDispatcherProvider`), Guards, Statusanzeige
- [ ] **Sammelversand** („alle neuen“) + **Wiederversand** aus `/applications` und `/applications/:id`
- [ ] **E-Mail-Kaskade** (Stufen 1–3) in einen `EmailDiscoveryService` kapseln + Tests (Mock-HTTP)
- [ ] **Option „Erstellen & Versenden“** am Ende des Generierungs-Workflows (Opt-in-Checkbox)
- [ ] **Integrationstests:** Versand-Mock (`MockClient`), Circuit-Breaker-Fall, Dublettenfall
- [ ] **DSGVO/Recht:** Hinweistext im Versand-Screen; Scraping-Ansatz auf Kontaktseiten dokumentieren

## Entscheidungen (ehem. offene Fragen)

| Frage | Entscheidung | Konsequenz |
|-------|--------------|------------|
| `emailStatus` als eigenständiges Feld oder Erweiterung von `ApplicationStatus`? | **Eigenes Feld** `emailStatus` an `Application` | Generierungs- und Versand-Lebenszyklus bleiben unabhängig; `ApplicationStatus` wird nicht verändert |
| Absenderidentität: eigene Domain oder persönliche Adresse? | **Verifizierte Brevo-Absenderadresse** `kleitmiandefoot@gmail.com` (SMTP-Relay-Daten siehe „Absenderkonfiguration“) | Backend-Gap 3 gelöst; Absendername aus CV-Daten ableitbar |
| Gesendete E-Mails auditierbar in der DB? | **Ja** | Neue Tabelle `sent_email_log` (Schema unten); Auswertung im Versand-Screen möglich |
| KI-Unterstützung beim Portal-Autofill? | **Verschoben** auf Phase 2/3 (`3-automailer.md` §2) | Kein Bestandteil dieses Sprints |
| Welche Zustände hat `emailStatus`? | Gespeichert: `new`/`queued`/`sending`/`sent`/`failed`. `ready`/`needs_address` sind **abgeleitete UI-Zustände** (aus `ApplicationStatus` + vorhandener E-Mail-Adresse) | Die Adresse stammt aus der Anzeige (Kaskade Stufen 1–3), sonst Stufe 4 manuell; `needs_address` löst beim Versand die Kaskade aus – kein zusätzliches Feld nötig |
| Aufbewahrungsfrist für Logs? | **Automatische Bereinigung** der Logs > 6 Monate (Cleanup beim App-Start) **plus** Button „Verlauf löschen“ in den Einstellungen | Log bleibt DSGVO-konform auf 6 Monate begrenzt; bewusste Gesamtlöschung jederzeit möglich |
| Lösch-Kaskade bei Bewerbungs-Löschung? | **Audit-Log bleibt erhalten** – kein `ON DELETE CASCADE` | FK bleibt (Default `NO ACTION`); Bewerbung mit Historie ist erst löschbar, nachdem die zugehörigen Logs explizit entfernt wurden |
| Wiederversand vs. Dublettenschutz? | **History-Prüfung** gegen `sent_email_log` vor jedem Versand; bei „bereits gesendet“ → **Bestätigungsdialog** | Keine versehentlichen Duplikate, bewusster Zweitversand bleibt möglich (Anforderung 3) |
| Tageslimit-Rest (300/Tag Free-Tier) persistieren? | **Ja** – persistenter Zähler (Datum + Anzahl als Key-Value in `search_filters`, Reset bei neuem Tag) | Limit wird auch nach App-Neustart eingehalten |
| „Als Entwurf exportieren“ im Log? | **Eigener Log-Eintrag** mit Status `draft_exported` | Auch der SMTP-Fallback ist auditierbar; `CHECK` erweitert |
| CC/BCC & mehrere Anhänge? | **Voll einplanen (Phase 1):** mehrere Anhänge (CV + Anschreiben getrennt) und CC/BCC; E-Mail-Vorlage erhält Anhang-Hinweissatz | `EmailService.sendEmail()` + `MailQueueEntry` um `cc`/`bcc` und `List<EmailAttachment>` erweitern |
| Bounce-Erkennung (Webhook/Polling) einführen? | **Phase 1 nicht einsetzen** – `bounced` bleibt im Enum + `CHECK` vorbereitet, wird aber nicht geschrieben und in der UI ausgeblendet. Bounce-Erkennnung erst in späterer Phase mit Server-/Webhook-Komponente | Kein Infrastruktur-Aufwand in Phase 1; `sent_email_log` lässt sich später per `messageId` nachträglich auf `bounced` aktualisieren |
| Rückantworten der Arbeitgeber (Reply-To)? | `kleitmiandefoot@gmail.com` ist Sendeadresse **und** Antwortadresse; `EmailService.sendEmail()` setzt `replyTo` explizit (gleiche Adresse, Name aus CV-Daten) | Antworten landen direkt im überwachten Postfach des Nutzers – kein `noreply`-Blackhole; Voraussetzung: Postfach gehört dem Nutzer |

### DB-Schema: `sent_email_log`

```sql
CREATE TABLE sent_email_log (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  application_id   INTEGER NOT NULL REFERENCES applications(id),  -- bewusst KEIN ON DELETE CASCADE (Audit-Log bleibt erhalten)
  recipient_email  TEXT    NOT NULL,                              -- RFC 5322-validiert
  subject          TEXT    NOT NULL,
  message_id       TEXT,                                          -- messageId aus Brevo-Response (nur bei 'sent')
  status           TEXT    NOT NULL
                   CHECK(status IN ('sent','failed','bounced','draft_exported')),
  error_message    TEXT,                                          -- Ursache bei 'failed'/'bounced'
  sent_at          TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))  -- UTC ISO 8601
);

-- „Zuletzt gesendet am“ je Bewerbung (Ergebnisübersicht + Versand-Screen)
CREATE INDEX idx_sent_email_log_application_sent ON sent_email_log(application_id, sent_at);
```

Jeder Versandversuch (auch Wiederholungen) erhält einen eigenen Eintrag – so lässt sich nachvollziehen, wann wie oft an dieselbe Stelle gesendet wurde. Auswertung: „Zuletzt gesendet am“ in der Ergebnisübersicht und im Versand-Screen.

> **Aufbewahrung (DSGVO):** Einträge älter als **6 Monate** werden automatisch beim App-Start bereinigt; zusätzlich gibt es den Button „Verlauf löschen“ in den Einstellungen. Da **kein** `ON DELETE CASCADE` gesetzt ist, müssen die Log-Einträge einer zu löschenden Bewerbung vorher explizit entfernt werden („Verlauf löschen“), sonst verhindert der Fremdschlüssel das Löschen der `Application`.

### Weitere offenen Fragen

_Keine offenen Fragen mehr – alle Punkte sind geklärt, siehe „Entscheidungen“._

### Umsetzungsplan

Die Umsetzung erfolgt in **sechs Phasen** (angelehnt an `6-Datenbank-Persistenz.md`). Jede Phase endet mit einem lauffähigen, testbaren Zustand. Die Checkliste „Umsetzungsschritte“ oben wird hier in eine Reihenfolge mit Aufwandsschätzung überführt.

### Phase A: Backend-Basis & Absender (1–2 Tage) ✅

- [x] **Gap 1 – Anhänge & CC/BCC verdrahten:** `MailDispatcher._sendEmail()` lädt die Bewerbungs-PDF (`pdfPath`) als `List<EmailAttachment>` und reicht sie an `EmailService.sendEmail(attachments:)` durch; `cc`/`bcc`/`replyTo` in `EmailService.sendEmail()` und `MailQueueEntry` ergänzt – **MVP: kombinierte PDF** aus `pdfPath`; getrennte CV-/Anschreiben-PDFs folgen als eigenes Arbeitspaket (Umbau `PdfGenerator`)
- [x] **Gap 3 – Absender umstellen:** Default in `EmailService` auf `kleitmiandefoot@gmail.com` (verifiziert) ersetzt (`defaultSenderEmail`/`defaultSenderName`); Absendername über `enqueueApplicationEmail(senderName:)` ableitbar
- [x] **Reply-To setzen:** `EmailService.sendEmail()` setzt `replyTo` explizit – gleiche Adresse wie `sender` (Name aus CV-Daten),damit Rückantworten der Arbeitgeber im überwachten Postfach landen
- [x] **Brevo-Response korrekt parsen:** `messageId` wird aus dem JSON-Body extrahiert statt `response.body` komplett als `messageId` zu speichern (`email_service.dart`)
- [x] **Fehlerklassifikation:** `EmailFailure`-Enum (401 `unverifiedSender` / 429 `rateLimited` / 5xx `server` / Netzwerk `network`) – Grundlage für den „Als Entwurf exportieren“-Fallback
- [x] **Template mit Anhang-Hinweis:** Standard-Body enthält bereits den Anhang-Hinweissatz („…finden Sie im Anhang dieser E-Mail“) – passt zur angehängten PDF
- [x] **Nebenbei behobene Bugs in `MailQueueService.processQueue()`:** (a) Pending-Einträge wurden wegen invertierter Zustandsprüfung **nie versendet**; (b) `_updateEntry` suchte per Objekt-Identität und verlor nach `copyWith`-Updates den Index → Status-Updates gingen ins Leere. Beides durch die neuen Dispatcher-Tests aufgedeckt und gefixt
- [x] **Tests:** `email_service_test.dart` (8 Tests: Payload/ReplyTo/CC/BCC/Anhang, Default-Absender, messageId-Parsing, 401/429/500/Netzwerk/Key fehlt) + `mail_dispatcher_test.dart` (3 Tests: Anhang+ReplyTo/CC/BCC-Send, fehlende PDF → failed, 401 → failed) – **alle 128 Tests der Suite grün**

### Phase B: Versand-Zustand & Persistenz (2–3 Tage) ✅

- [x] **Gap 4 – `emailStatus` an `Application`:** `EmailStatus`-Enum (`new`/`queued`/`sending`/`sent`/`failed`, `storeValue` + `fromStoreValue`) + Feld + `copyWith`/`toJson`/`fromJson` + DB-Konverter (`database_repository.dart`); `ready`/`needs_address` bleiben abgeleitete UI-Zustände (kein Speicher)
- [x] **Gap 5 + Audit-Log – DB-Migration auf Version 7:** `email_status` (+ `email_address`) an `applications`; Tabelle `sent_email_log` (CHECK `sent`/`failed`/`bounced`/`draft_exported`, UTC-Default `strftime('%Y-%m-%dT%H:%M:%fZ','now')`, Index `application_id, sent_at`); `_onCreate` + `_onUpgrade` synchron
- [x] **`SentEmailLogRepository`:** `insert` (ein Eintrag pro Versuch – auch `failed`/`draft_exported`, inkl. `error_message`), `latestSentAt` („Zuletzt gesendet am“), `hasSent` (History-Prüfung), `deleteOlderThan` (Retention), `deleteByApplication`, `deleteAll`
- [x] **Queue-Persistenz:** `SqliteMailQueueStore` (Insert/Update/Status/Pending/Counter/Cleanup) an die `mail_queue`-Tabelle gebunden; `MailQueueService.requeuePendingEmails()` lädt offene `pending`/`queued` (+ abgelaufene `failed`) beim App-Start – **kein stiller Auto-Versand** (Nutzer bestätigt erneut)
- [x] **Dublettenschutz-Basis:** `SentEmailLogRepository.hasSent()` liefert die History-Prüfung („bereits gesendet?“); der **Bestätigungsdialog** beim Wiederversand folgt in Phase D (UI)
- [x] **Retention-Basis:** `deleteOlderThan(cutoff)` im Repository; Cleanup-Job beim App-Start + Button „Verlauf löschen“ folgen in Phase D/E (Einstellungen)
- [x] **Persistenter Tageslimit-Zähler:** Datum + Zähler als Key-Value in `search_filters` (`mail_sent_date`/`mail_sent_count`, automatischer Reset bei neuem Tag) via `DatabaseRepository`; `MailDispatcher` prüft **300/Tag** vor dem Versand und erhöht den Zähler bei Erfolg
- [x] **Tests (17 neue, Suite gesamt 145 grün):** `sent_email_log_repository_test.dart` (6: insert/UTC, MAX sent_at, hasSent, Retention, deleteByApplication, deleteAll), `database_repository_test.dart` (6: Tageslimit-Zähler inkl. Persistenz über neue Instanz, emailStatus-Roundtrip), `mail_queue_store_test.dart` (5: Roundtrip, updateStatus, loadPending-Filter, countByStatus, deleteAllCompleted) – alle gegen In-Memory-SQLite mit echter Schema-Definition (`createSchemaForTesting`)

> **Hinweis zu Phase B:** Das DB-Schema (v7) enthält `bounced` im CHECK und im Enum, wird in Phase 1 aber noch **nicht** geschrieben (Entscheidung „Bounce-Erkennung“). Der `emailStatus` wird von `MailDispatcher` bisher nur im Queue-Lebenszyklus verfolgt; das Schreiben an die `applications`-Tabelle (State je Bewerbung) wird mit Phase D verdrahtet, sobald der Versand-Screen die Werte braucht.

### Phase C: E-Mail-Adress-Ermittlung (2 Tage)

- [ ] **`EmailDiscoveryService`** – Kaskade Stufen 1–3 (Regex auf Bestandsdaten → `mailto:` → genau 1 Kontaktseite mit Timeout)
- [ ] **Stufe 4 + Persistenz:** manuelle Eingabe im Versand-Dialog; gefundene Adresse als `application.emailAddress` speichern
- [ ] **Validierung:** RFC-5322-Prüfung; CAPTCHA-/Blocker-Abbruch → Sprung zu Stufe 4
- [ ] **Unit-Tests mit Mock-HTTP:** `mailto:`-Treffer, Kontaktseiten-Follow, CAPTCHA-Abbruch, Regex-Positiv/Negativ

### Phase D: Versand-Screen `/send` (2–3 Tage)

- [ ] Route `/send` registrieren (analog Screen 3 in `2-Workflow.md`)
- [ ] Riverpod-Provider: `mailDispatcherProvider` + Stream für `MailDispatcherStats`
- [ ] Liste versandfähiger Bewerbungen (`completed`/`exported`) mit Checkbox, editierbarer Vorschau sowie Empfänger-/CC-/BCC-Feldern
- [ ] Guards: kein API-Key → `/settings` mit Hinweis-Banner; keine versandfähigen Bewerbungen → zurück
- [ ] Statusanzeige: `pending`/`sent`/`failed` + Circuit-Breaker-Zustand mit Retry-Zeitpunkt
- [ ] „Zuletzt gesendet am“ aus `sent_email_log` (MAX(`sent_at`) je `application_id`)

### Phase E: Versand-Workflows (1–2 Tage)

- [ ] Sammelversand „Alle neuen senden“
- [ ] Wiederversand einzelner Bewerbungen aus `/applications` und `/applications/:id`
- [ ] Option „Erstellen & Versenden“ (Opt-in-Checkbox am Ende des Generierungs-Workflows)
- [ ] Fallback „Als Entwurf exportieren“ bei 401 (Absender nicht verifiziert)

### Phase F: Tests, Qualität & Recht (1–2 Tage)

- [ ] Integrationstests mit `MockClient`: Erfolgsfall (mit Anhängen + CC/BCC), HTTP 429/Tageslimit (persistenter Zähler), Circuit-Breaker-OPEN, Dublettenfall (History-Prüfung + Bestätigungsdialog)
- [ ] Retention-Test: Cleanup > 6 Monate + „Verlauf löschen“-Button; Migrationstest v6 → v7 (bestehende Daten bleiben erhalten; Fremdschlüssel-Verhalten prüfen)
- [ ] DSGVO-Hinweistext im Versand-Screen; Scraping-Ansatz (nur Kontaktseite, max. 1 Zusatz-Request) dokumentieren
