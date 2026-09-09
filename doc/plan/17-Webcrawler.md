# 17 – Webcrawler: E-Mail-/Kontakt-Ermittlung als fokussierter Crawler

> **Stand:** Entwurf / Idee (2026-09-09). Baut auf den bereits umgesetzten
> Kontakt-Kaskaden aus `14-Email.md` und `16-Jobsuche-BA.md` auf – **kein
> Neuaufbau eines generischen Crawlers**, sondern eine Erweiterung der
> vorhandenen Bausteine um Batch-/Skalierung/Persistenz.

## Problem (präzisiert)

Die Job-Suche funktioniert, aber zu den gefundenen Stellen fehlen oft die
**Ansprechpartner und/oder passenden E-Mail-Adressen**, die für die
automatisierte Bewerbung nötig sind. In einem Test ließen sich ausgewählte
E-Mail-Adressen aus der DB zwar über eine **manuelle Websuche** nach
Jobangebot und Arbeitgeber verifizieren – dieses Vorgehen ist bei einer
größeren Menge von Bewerbungen aber **ineffektiv** (ein Fall = mehrere
manuelle Schritte, kein reproduzierbarer Prozess).

**Ziel der Idee:** Die für jeden Einzelfall nötigen Daten (E-Mail, ggf.
Ansprechpartner) möglichst automatisiert, legitim und mit kontrolliertem
Netzwerkaufwand ermitteln – statt den Menschen pro Bewerbung eine Websuche
machen zu lassen.

## Wichtig: Was bereits existiert

Ein großer Teil der „Crawler“-Logik ist **schon implementiert** und getestet.
Ein neuer, generischer Webcrawler wäre Duplikat und würde gegen die
Rechts-/Ethik-Abgrenzung der App verstoßen. Deshalb wird die Idee als
**Erweiterung der bestehenden Kaskade** formuliert.

| # | Ist-Baustein | Datei | Leistung heute |
|---|--------------|-------|----------------|
| 1 | `EmailDiscoveryService` (Stored → `mailto:` → 1 Kontaktseite) | `lib/data/services/email/email_discovery_service.dart` | E-Mail-Ermittlung zu einer Job-URL; max. 1 Zusatz-Request, Blocker-/Captcha-Erkennung, Timeout, Abbruch statt Umgehen |
| 2 | `BaContactResolver` (BA `jobdetails` → Beschreibung → externe Anzeige → Arbeitgeber-Website → manueller Fallback) | `lib/data/services/api/ba_contact_resolver.dart` | Kontakt-Kaskade zu einer BA-`refnr`; Host-Sperre für `arbeitsagentur.de` |
| 3 | `JobScraperService` | `lib/data/services/api/job_scraper_service.dart` | HTML-Extraktion einer einzelnen Stellen-URL (Titel/Firma/Ort/Beschreibung) |
| 4 | `firstEmailAddressRobust` / `normalizeObfuscatedEmailText` | `lib/data/services/email/email_address_utils.dart` | Offline-Extraktion auch bei verdeckten Schreibweisen (`(at)`, `&#64;`, Umbrüche) |
| 5 | `ApiCacheService` (LRU, TTL) | `lib/data/services/api/api_cache_service.dart` | Request-/Response-Cache für wiederholte Zugriffe |
| 6 | `ApiClient` (Timeout, Retry, Key-Handling) | `lib/data/services/api/api_client.dart` | Robuster HTTP-Unterbau |

> **Konsequenz:** `17` beschreibt **nicht** „neuen Crawler bauen“, sondern die
> **fehlenden Stücke** dieser Kaskade: skalierbare Ausführung über viele Jobs
> (Batch), Persistenz des Ergebnisses (E-Mail **und** Ansprechpartner) sowie
> einen höflichen, rate-limitierten Scheduler.

## Ansatz: Erweiterte Kaskade

Die bestehende Einzel-Job-Kaskade (`16-Jobsuche-BA.md`) wird unverändert als
Kern übernommen und um eine **Batch-/Anreicherungs-Schicht** ergänzt:

| # | Quelle | Vorgehen | Code-Basis |
|---|--------|----------|------------|
| 0 | **DB / gespeicherte Daten** | E-Mail offline aus bereits erfassten Feldern extrahieren (kein Netz) | `findEmailInStoredData` |
| 1 | **BA `jobdetails`** (REST, kein Captcha) | Beschreibung laden; E-Mail offline aus Fließtext extrahieren | `BaApiService.fetchJobDetails` + `firstEmailAddressRobust` |
| 2 | **Externe Anzeige** (`externeURL`) | `mailto:`-Link / Kontaktseite (max. wenige Requests) | `EmailDiscoveryService` |
| 3 | **Arbeitgeber-Website** | Impressum/Karriere/Kontakt durchsuchen | `EmailDiscoveryService` |
| 4 | **Suchmaschinen-API** *(optional)* | Generische Websuche nach „Jobtitel + Arbeitgeber“; nur mit eigenem Key, lose gemappte Treffer | Recherche in `16` (DuckDuckGo abgelehnt, Bing/Brave optional) |
| 5 | **Manueller Fallback** | Adresse/`externeURL`/Website anzeigen, Nutzer ergänzt E-Mail/Ansprechpartner | UI („In Zwischenablage“) |

Regeln bleiben: Hosts wie `arbeitsagentur.de` werden **nie** über die HTML-Seite
angesprochen; wird ein Blocker erkannt, wird die Netzwerk-Kaskade **abgebrochen**.

## Machbarkeit

| Quelle | Befund / Verifikation | Machbar? |
|--------|------------------------|----------|
| BA `jobdetails` (Stufe 1) | REST frei von Captcha, live verifiziert; liefert aber **kein** E-Mail-Feld – Text-Extraktion nötig | ✅ umgesetzt (`16`) |
| Externe Anzeige / Arbeitgeber-Website (Stufe 2–3) | Kontaktseiten sind die real zuverlässigste Quelle; selektorenfragil, aber pro Job nur 1–3 Requests | ✅ umgesetzt (`16`), höflicher Betrieb nötig |
| Beschreibungstext (Stufe 1) | Robust gegen verdeckte Schreibweisen; deckt aber nur Adressen ab, die der Arbeitgeber druckt | ✅ offline |
| Suchmaschinen (Stufe 4) | DuckDuckGo: kein freier Web-Ergebnis-Zugang (live geprüft) → abgelehnt. Bing/Brave: nur optional mit eigenem Key; Treffer lose gemappt | ➖ optional, **nicht** Standard |
| Batch über viele Jobs | Bisher nur „ein Job auf Knopfdruck“ (`SendScreen`) | 🔄 **das fehlende Stück** von `17` |

**Politeness / Betrieb:** pro Job wenige Requests (0–3), pro Host
Rate-Limit + minimale Verzögerung (Jitter), robots.txt respektieren, Timeouts,
Circuit-Breaker (analog `MailDispatcher`), Ergebnis-Cache.

## Probleme & Risiken

| Bereich | Risiko | Gegenmaßnahme (vorhandene Bausteine) |
|---------|--------|---------------------------------------|
| Technisch | CAPTCHA, HTTP 403/429/503, fragile CSS-Selektoren, Layout-Änderungen | `_looksBlocked`/`_blockMarkers` + Abbruch statt Umgehen; Selektoren-Listen mit Fallbacks (`JobScraperService._tryExtract`); Timeouts |
| Rechtlich | AGB/Urheberrecht, robots.txt, Scraping-Rechtsprechung | Nur wenige Requests auf Kontakt-/Impressum-Seiten; Höflichkeits-Scheduler; kein BA-HTML-Scraping |
| Datenschutz | DSGVO bei Speicherung von Kontaktdaten | Zweckbindung (nur Bewerbung), Speicherung in lokaler SQLite, Audit-/Lösch-Fähigkeit wie Mail-Log |
| Operativ | Rate-Limits, IP-Sperren, Datenqualität/Dubletten | Pro-Host-Rate-Limit + Jitter, `ApiCacheService`, stabile ID via `fnv1a32` (Muster in `JobScraperService`), Dedup bei erneuten Läufen |
| Datenqualität | Falsche/veraltete E-Mail, keine persönliche Zuordnung | Quelle + Fundstelle (`evidenceUrl`) immer mitspeichern; menschliche Bestätigung vor Versand; Ansprechpartner nur als Zusatzinfo |

## Konkreter Umsetzungsvorschlag (Architektur)

1. **`ContactEnrichmentService` (Batch)** – nimmt eine Liste von Jobs
   (aus `Application`/Suche) und lässt pro Job die **bestehende** Kaskade
   (`BaContactResolver`/`EmailDiscoveryService`) laufen; kapselt das Ergebnis
   in ein Modell `ContactEnrichmentResult` (`email`, `emailSource`,
   `evidenceUrl`, `ansprechpartner?`, `foundAt`).
2. **Höflicher Scheduler** – serialisiert Requests, Pro-Host-Fenster
   (z. B. min. 1–2 s Abstand, Jitter), Abbruch bei Blocker; Wiederverwendung
   von `ApiCacheService`.
3. **Persistenz** – DB-Migration: Spalten `email_source`/`evidence_url` und
   optional `contact_person` an `Application` (analog `email_address`);
   erneute Läufe aktualisieren statt doppelt einzufügen (Dedup über stabile
   Job-`id`/URL).
4. **Transparenz** – Ergebnis je Job als Liste in der UI (analog
   „In Zwischenablage“-Fallback), Quelle/Fundstelle sichtbar, manuell
   bestätigbar vor Versand.
5. **Fehlerbehandlung** – Retry/Backoff + Circuit-Breaker je Host nach Vorbild
   `MailDispatcher`; Fehler pro Job geloggt (nicht als Ganzes abgebrochen).

## Test-Strategie

- Unit-Tests mit `MockClient` (Hausmuster): jede Kaskaden-Stufe, Blocker
  (403/429/503/Marker), Timeout, Dedup bei Wiederholung, Politeness (Reihenfolge
  & Mindestabstand), `robots.txt`-Auswertung.
- Extraktions-Tests für `firstEmailAddressRobust` inkl. verdeckter
  Schreibweisen (bestehend) erweitern.
- Migrations-Test für die neuen `Application`-Spalten (Muster: v6→v7 in `14`).

## Nächste Schritte / offen

- [x] **Scope klären:** Nur fehlende Kontaktdaten *bestehender* Jobs
      anreichern (Batch) vs. zusätzlich neue Stellen finden (→ bleibt `16`,
      kein `17`).
      **Entscheidung:** Nur **bestehende** Jobs anreichern (Batch). Das Finden
      neuer Stellen bleibt Aufgabe der Such-Kaskade (`16`), kein neuer Crawler.
- [x] **Politeness-Parameter festlegen** (Requests/Minute, pro Host, robots.txt).
      **Umgesetzt:** `ContactEnrichmentService` – `minDelayPerHost` (Default
      ~1,2 s), optional `enableJitter` (0–250 ms), serielle Abarbeitung und
      Pro-Host-Pacing (`_pace`); Blocker/Timeout führen zu Abbruch statt
      Umgehen (kein Umgehen von Schutzmechanismen).
- [x] **Batch-`ContactEnrichmentService`** bauen (Wiederverwendung der
      vorhandenen Kaskade).
      **Umgesetzt:** `lib/data/services/email/contact_enrichment_service.dart`
      – `enrich(List<Application>, {force})` nutzt je Job `BaContactResolver`
      (BA, URL-basiert) bzw. `EmailDiscoveryService` (generisch); Ergebnis als
      `ContactEnrichmentOutcome` (email/Quelle/Fundstelle/Ansprechpartner).
      Wiederverwendet `EmailDiscoveryResult.evidenceUrl` (neu: Job-/Kontakt-URL).
      Provider `contactEnrichmentServiceProvider`. Höflichkeit + Fehler je Job
      (kein Batch-Abbruch) + Session-`stats`. Tests:
      `test/services/contact_enrichment_service_test.dart` (MockClients).
- [x] **DB-Migration** (E-Mail-Quelle, `evidence_url`, optional
      `contact_person`) + Tests.
      **Umgesetzt (2026-09-09):** DB-Schema auf **Version 8** angehoben
      (`DatabaseHelper.schemaVersion`). Neue Spalten an `applications`:
      `email_source`, `email_evidence_url`, `contact_person` (alle schlicht
      `TEXT` ohne CHECK – Quell-Werte liefern die bestehenden
      `EmailDiscoverySource`/`BaContactSource`-Enums bzw. `manual`). Modell
      `Application` (+ `copyWith`/`toJson`/`fromJson`), Converter in
      `DatabaseRepository` sowie neue Methode `updateContactInfo(...)` (schreibt
      nur übergebene Felder); `JobRepository.updateApplicationEmail(...)` um die
      drei Felder erweitert (aufrufkompatibel). Tests: Migrationstest
      `v7 → v8` (Daten bleiben erhalten, neue Spalten + beschreibbar) und
      v8-Roundtrip/-`updateContactInfo` in `database_repository_test.dart`.
      **Hinweis:** v6→v7-Migrationsbeispiel in `14-Email.md`/`6-Datenbank-
      Persistenz.md` ist weiterhin korrekt – `_onUpgrade` wendet je open nur die
      Branches `oldVersion < N` an.
- [x] **UI**: Batch-Ergebnisliste mit Quelle/Fundstelle, manueller Bestätigung.
      **Umgesetzt:** `SendScreen` – AppBar-Button „Kontakte ermitteln“
      (`Icons.find_in_page`). Lässt `ContactEnrichmentService` für alle
      versandfähigen Bewerbungen ohne gültige Adresse laufen und zeigt Treffer
      je Job (E-Mail, Quelle, Ansprechpartner, Fundstellen-URL) mit Checkbox
      zur Bestätigung. „Übernehmen“ persistiert via
      `JobRepository.updateApplicationEmail(…, emailSource/emailEvidenceUrl/
      contactPerson)` und füllt das Empfänger-Feld.
- [x] **Live-Verifikation:** Trefferquote je Stufe messen (analog
      `BaMarketStats`), ggf. `Ansprechpartner`-Extraktion aus der Beschreibung
      ergänzen (`16`, offener Punkt).
      **Umgesetzt:** Session-Statistik `ContactEnrichmentService.stats`
      (versucht/gefunden je Quelle, übersprungen, blockiert, Fehler), nach
      jedem Batch als Zusammenfassung im Dialog + Log sichtbar. Neuer Helper
      `firstContactPersonIn` (`contact_person_utils.dart`) extrahiert
      best-effort einen Ansprechpartner und wird im Outcome/`contact_person`
      persistiert. Tests: `contact_person_utils_test.dart` + im Service-Test.
- [x] **Optional: Suchmaschinen-API (Stufe 4)** – bewertet und als
      **Entscheidung geschlossen (kein Code):** Recherche in `16` zeigt
      DuckDuckGo = kein freier Web-Ergebnis-Zugang (abgelehnt), Bing/Brave nur
      optional mit eigenem Key und lose gemappten Treffern. Nicht Standardweg;
      die real zuverlässigsten Quellen bleiben Anzeige + Arbeitgeber-Website.
      Stufe 4 bleibt im Ansatz-Dokument als „optional“ markiert.
