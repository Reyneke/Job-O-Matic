# Kontaktdaten aus der BA-Jobsuche auslesen (ohne Captcha)

## Problem (präzisiert)

Beim Übernehmen eines gefundenen Jobs aus der BA-JOBBÖRSE fehlen oft die
Kontaktdaten (E-Mail/Ansprechpartner), die für die automatisierte Bewerbung
nötig sind. Die menschenlesbare Seite `arbeitsagentur.de/jobsuche` zeigt sie
erst nach Login und stellt dafür ein **Captcha** aus – eine bewusste
Schutzmaßnahme der BA.

**Wichtige Erkenntnis (Stand: 2026-09-07, live verifiziert):**
- Die bereits in `BaApiService` integrierte, dokumentierte BA-REST-API
  (`rest.arbeitsagentur.de`, Header `X-API-Key: jobboerse-jobsuche`) ist
  **frei von Captcha** und liefert strukturierte Daten.
- Die `jobdetails`-Antwort (`/pc/v4/jobdetails/{base64(refnr)}`) enthält aber
  **kein** Feld für eine direkte Arbeitgeber-E-Mail (`email`/`kontakt`
  existieren nicht). Geprüft für eine interne (EDEKA IT) und eine externe
  Anzeige (zollsoft/get-in-it).
- Externe/Allianz-Anzeigen liefern stattdessen `externeURL` +
  `allianzpartnerName`; Kontaktdaten stehen sonst – wenn überhaupt – im
  **Fließtext der `stellenangebotsBeschreibung`** oder auf der externen
  Anzeige/Arbeitgeber-Website.

**Konsequenz:** „Captcha umgehen“ ist **nicht** der Lösungsweg – weder rechtlich
(AGB einer Behörde, Scraping-Rechtsprechung) noch technisch (fragil,
wartungsintensiv) noch ethisch (untergräbt das Automatisierungs-/
Accessibility-Ziel der App). Es gibt legitime Quellen ohne Captcha.

## Ziel

Legitim an die Kontaktdaten eines BA-Jobs kommen – mit möglichst hoher
Automatisierung und transparentem manuellem Fallback. **Kein** Headless-
Browsing, kein Captcha-Solver, kein Login-Umgehen auf arbeitsagentur.de.

## Ansatz (Kaskade)

| # | Quelle | Vorgehen | Code |
|---|--------|----------|------|
| 1 | **`jobdetails`** (REST, kein Captcha) | Anzeige-Details laden (Beschreibung, Adresse, `externeURL`, Website) | `BaApiService.fetchJobDetails` |
| 2 | **Beschreibungstext** | E-Mail/Telefon offline aus `stellenangebotsBeschreibung` extrahieren (robust gegen `(at)`/`&#64;`/Umbrüche) | `firstEmailAddressRobust` |
| 3 | **Externe Anzeige** (`externeURL`) | Partner-/Arbeitgeber-Seite durchsuchen (`mailto:`/Kontaktseite), max. wenige Requests | `EmailDiscoveryService` |
| 4 | **Arbeitgeber-Website** | Impressum/Karriere/Kontakt der Website durchsuchen | `EmailDiscoveryService` |
| 5 | **Manueller Fallback** | Adresse/`externeURL`/Website anzeigen, Nutzer ergänzt E-Mail | UI („In Zwischenablage“) |

Regel: Hosts wie `arbeitsagentur.de` werden **nie** über die HTML-Seite
angesprochen – das erzwingt die Host-Sperre im Resolver.

## Umgesetzt (2026-09-07)

- `lib/data/services/api/ba_job_details.dart` – neuer Werttyp `BaJobDetails`
  (tolerantes Parsen, Adress-Aufbereitung).
- `lib/data/services/api/ba_api_service.dart` – neuer Endpunkt
  `fetchJobDetails(refnr)` + Helfer `base64EncodeRefnr`.
- `lib/data/services/api/ba_contact_resolver.dart` – neue Kontakt-Kaskade
  `BaContactResolver.resolve(refnr)` → `BaContactResolution`
  (E-Mail + Fundstelle + Adresse/URLs), Host-Sperre für arbeitsagentur.de.
- Tests: `test/services/ba_api_service_test.dart` (Details + Base64),
  `test/services/ba_contact_resolver_test.dart` (Beschreibung, externe Anzeige,
  Website, Host-Sperre, manueller Fallback) – alle gegen MockClients.

## Nächste Schritte / offen

- [x] UI-Verdrahtung: Bei einem übernommenen BA-Job `BaContactResolver` aufrufen
      und Ergebnis (E-Mail/Quelle/manueller Hinweis) in den E-Mail-Workflow
      (`SendScreen`/`EmailDiscoveryService`) einspeisen.
      **Umgesetzt:** Der „Ermitteln“-Button im `SendScreen` erkennt BA-Anzeigen
      über die Job-URL (`baRefnrFromJobUrl`) und ruft statt der generischen
      HTML-Kaskade den `BaContactResolver` (`baContactResolverProvider`) auf –
      Beschreibungstext → externe Anzeige → Arbeitgeber-Website → manueller
      Fallback mit Anschrift/URLs. arbeitsagentur.de wird weiterhin nie über die
      HTML-Seite angefragt (Host-Sperre). Detektion ist URL-basiert und
      übersteht App-Neustarts.
- [x] Ansprechpartner-Extraktion aus der Beschreibung – **umgesetzt in `17`**:
      `contact_person_utils.dart` (`firstContactPersonIn`, best effort) +
      persistiert in `Application.contact_person` (DB v8). Hängt an der
      gespeicherten `jobDescription` der Bewerbung.
- [ ] Optional: Telefon-Extraktion aus der Beschreibung (noch offen).
- [x] Beobachten: Wie viele BA-Anzeigen sind extern (`externeURL`) vs. intern?
      **Umgesetzt (2026-09-08):** Session-Statistik `BaMarketStats` in
      `BaApiService` (`marketStats`-Getter). Erfassung **ohne Extra-Requests**:
      direkt in `_parseJobOffers` (Such-Items) mit schreibweisen-toleranter
      Erkennung `externeUrl`/`externeURL`/`allianzpartnerName`
      (Doku- vs. Live-API; `arbeitgeberdarstellungUrl` ist bewusst NICHT
      extern) sowie in `fetchJobDetails` (`externalUrl != null`). Kompaktes
      Info-Log nach jeder Suche (`BA-Suche: … Session: … extern (x%) / intern`).
      Sichtbar als Karte „BA-Markt-Beobachtung“ im Einstellungen-Screen
      (`ApiKeySettingsScreen`). Werte sind bewusst in-memory (seit App-Start);
      gemessene Marktwerte hier eintragen, sobald einige Suchläufe erfolgt sind.

## Frage

Welche Jobsuchmaschinen wurden bereits implementiert?

## Antwort (Stand: 2026-09-08)

Die in der Jobsuche-Kaskade (`JobSearchService`, `job_search_service.dart`)
verdrahteten Suchmaschinen:

| # | Quelle | Service | Rolle | Auth |
|---|--------|---------|-------|------|
| 1 | **BA-JOBBÖRSE** (Bundesagentur für Arbeit) | `BaApiService` | **primär** | fester, öffentlicher Key (`X-API-Key: jobboerse-jobsuche`) |
| 2 | **Adzuna** | `AdzunaApiService` | sekundär (nur falls BA < 10 Ergebnisse) | App-ID + API-Key (`ApiKeyService`) |
| 3 | **SerpAPI / Google Jobs** | `SerpApiService` | letzter Fallback | kostenpflichtiger SerpAPI-Key |

Zusätzlich (keine Suche im engeren Sinn):
- **`JobScraperService`** – HTML-Scraping einer **einzelnen, eingegebenen
  Stellen-URL** (im `JobInputScreen`); extrahiert Titel/Firma/Ort.
- **`BaContactResolver` / `EmailDiscoveryService`** – Kontaktdaten-Kaskade zu
  BA-Anzeigen bzw. generische E-Mail-Findung (siehe oben); kein Jobfinder.

**Nicht implementiert:** Indeed (API 2024 eingestellt), LinkedIn (nur
Enterprise), StepStone/Monster (keine öffentliche API, nur Scraping), Jooble.

> **Hinweis:** `doc/plan/10-aktueller_Stand.md` führte SerpAPI fälschlich als
> „nicht implementiert“ (nur Key-Konstante). Das ist **inzwischen überholt**:
> `SerpApiService` ist implementiert
> (`job_o_matic/lib/data/services/api/serp_api_service.dart`) und über
> `serpApiServiceProvider` als letzter Fallback in `JobSearchService`
> eingebunden. Der Plan-Status wurde korrigiert.

## Frage 
Was sind die Probleme bei Jooble?

## Antwort 1 (Stand: 2026-09-08)

Aus Sicht der Such-Kaskade (BA → Adzuna → SerpAPI) überwiegen die Probleme
gegenüber dem Mehrwert – **nicht einbinden**:

1. **Sehr niedriges Request-Limit.** Free-Tier ~100 Requests/Monat
   (`doc/plan/10`). Als *Suchquelle* zu wenig – eine Nutzersuche mit Pagination
   verbraucht mehrere Requests. Nur mit aggressivem Caching (`ApiCacheService`,
   TTL 30 min) ansatzweise nutzbar, was den Nutzen weiter senkt.
2. **Aggregator-Duplikate.** Jooble bündelt Anzeigen anderer Börsen (überschneidet
   sich mit BA/Adzuna/Google-Jobs). Kaum *neue* Abdeckung, dafür mehr
   Deduplizierungsaufwand in `JobSearchService`.
3. **Flache/uneinheitliche Daten.** Oft nur Titel/Firma/Ort ohne Beschreibung,
   Gehalt oder Arbeitszeitmodell → viele „Nicht bewertbar“-Fälle in den Filtern
   (Vollzeit/Teilzeit/Remote).
4. **Kein Kontakt-/E-Mail-Feld.** Wie die BA liefert Jooble keine
   Arbeitgeber-E-Mail; die `BaContactResolver`-Kaskade (doc/plan/16) müsste
   erneut greifen, die Beschreibung liefert aber meist zu wenig Fließtext.
5. **Regionale Ausrichtung.** In `doc/plan/5` mit „🇺🇦 UA“ markiert – für den
   deutschen Markt limitiert.
6. **Rechtlich/AGB.** Nutzung über die eigenen Limits (bzw. Scraping) wäre genau
   die rechtlich fragwürdige Route, die das Projekt („kein Captcha umgehen“)
   bewusst vermeidet.

**Fazit:** Google-Jobs/SerpAPI deckt Jooble-Inhalte weitgehend mit ab → geringer
Zusatznutzen bei Mini-Limit und schwacher Datenqualität.

## Frage
Was für ein Aufwand wäre es Stepstone / Monster miteinzubinden

## Antwort 2 (Stand: 2026-09-08)

**Kontext:** Beide haben **keine öffentliche, frei nutzbare Such-API** für
Verbraucher. StepStone bietet nur B2B-Partnerlösungen (Job-Posting-Feeds);
Monster hat nach der Randstad-Übernahme (2024) keinen offenen Such-API-Zugang
für DACH. Öffentlicher Zugang hieße faktisch **HTML-Scraping** (fragile,
JS-lastige Seiten; intern genutzte/private JSON-Endpunkte) – rechtlich offen
(`doc/plan/10`, Topic 8 „Ist Scraping für StepStone/Monster rechtlich
zulässig? Prüfung läuft“), kollidiert mit dem Legitim-Quellen-Prinzip der App.

**Aufwandsschätzung (falls via Scraping):**

| Portal | Implementierung | Tests | Laufende Wartung | Datenqualität |
|--------|-----------------|-------|------------------|---------------|
| **StepStone** | ~2–4 Tage | ~1 Tag | hoch (Selektoren/CAPTCHA/Rate-Limit) | gut (oft Gehalt & Beschäftigungsart) |
| **Monster** | ~2–4 Tage | ~1 Tag | hoch | für DACH eher schwach |

Plus ~1 Tag Architektur: In `JobSearchService` andocken als weitere Quelle
(`source: 'stepstone'/'monster'`, gleicher `search()`-Vertrag → `List<JobOffer>`),
mit Selektor-Konfiguration, Fehler-/CAPTCHA-Behandlung und bestehender
Deduplizierung. **Gesamt ~1–2 Wochen pro Portal bis produktiv**
(deckt sich mit `doc/plan/5`, Phase-4-Schätzung „1–2 Wochen“).

**Geringer Mehrwert:** SerpAPI / Google Jobs (bereits letzter Fallback) indexiert
einen erheblichen Teil der StepStone- und Monster-Anzeigen mit. Direkte Anbindung
brächte wenig *neue* Abdeckung, dafür viel fragilen Wartungsaufwand und
rechtliches Risiko. Die saubere Alternative (offizielle B2B-Partnerschaft) ist
ein Vertrags-/Kosten-/Zulassungsthema, für ein kleines Bewerbungs-Tool
unverhältnismäßig.

**Fazit:** **Nicht direkt integrieren** (hoher Aufwand, niedriger Zusatznutzen).
Coverage läuft bereits indirekt über SerpAPI. Falls doch, wäre StepStone
(bessere Daten) der sinnvollere Kandidat als Monster.

### Addendum: Stand bei StepStone/Monster, da SerpAPI kostenpflichtig ist

Die obige Empfehlung („Coverage via SerpAPI“) hängt an einem **kostenpflichtigen**
Baustein. Als *kostenlose* Alternative scheiden StepStone & Monster aus:

1. **StepStone** – offizieller Zugang nur über **B2B-Partner-/Feed-Verträge**
   (kostenpflichtig, Zulassung); **kein kostenloser Verbraucher-Zugang** zur
   Suche. „Kostenlos“ gäbe es nur über Scraping der öffentlichen Website bzw.
   der internen (privaten) JSON-Endpunkte – rechtlich/technisch fragil.
2. **Monster** – nach der **Randstad-Übernahme (2024)** kein offener
   Such-API-Zugang für DACH mehr; übrig bleibt Partner-B2B oder Scraping;
   zudem schwächere Datenqualität auf dem deutschen Markt.
3. **Google Jobs selbst** ist für Endnutzer kostenlos, aber **programmatisch nur
   über bezahlte Aggregatoren (SerpAPI) oder ToS-widriges Scraping** erreichbar.

**Einordnung in der App:** Die wirklich **kostenlosen + legitimen** REST-Quellen
sind bereits eingebunden – BA-JOBBÖRSE (primär, öffentlicher fester Key) und
Adzuna Free-Tier (~50 Calls/Tag, sekundär), optional Jooble (~100/Monat). SerpAPI
ist in `JobSearchService` nur der **letzte Fallback**, wenn BA **und** Adzuna
zusammen zu wenige Ergebnisse liefern – es kostet also nicht im Normalbetrieb,
sondern nur beim Lücken-Füllen. StepStone/Monster würden diese Lücke **nicht
kostenlos schließen**, sondern nur die Wahl B2B-kostenpflichtig-oder-Scraping
erneut aufmachen.

**Fazit Addendum:** Nicht integrieren. Sollte der Kostendruck durch SerpAPI real
werden, ist die sinnvollere Stellschraube, die Adzuna-Freischicht auszuschöpfen
(ggf. Rate-Limit/Höherstufung) – nicht ein fragiles StepStone/Monster-Scraping
aufzubauen.

## Frage
Was für Jobbörsen, -suchmaschinen oder Wege an Angebote zu kommen gibt es noch, die kostenlos sind?

## Antwort 3 (Stand: 2026-09-08)

**Einordnung:** Unter den Maßstäben der App (kostenlos **und** legitim/maschinenlesbar,
kein Captcha-Umgehen, kein fragiles HTML-Scraping) ist das Feld *echter* zusätzlicher
Suchquellen klein. Die ergiebigsten kostenlosen REST-Quellen sind bereits eingebunden
(BA-JOBBÖRSE primär, Adzuna Free sekundär). Was übrig bleibt, zerfällt in drei Gruppen:
**(A)** weitere offene/Feed-basierte APIs mit niedrigen Limits, **(B)** Nischen-/
Spezialportale, die im Browser kostenlos sind, aber programmatisch nur via Scraping
(→ bewusst abgelehnt), und **(C)** „Wege an Angebote zu kommen“, die keine Börse sind.

### A) Weitere offene, legitime Such-APIs / Feeds (bewerten & live verifizieren)

| # | Quelle | Zugang | Kosten | Abdeckung DACH | Anmerkung | Status |
|---|--------|--------|--------|----------------|-----------|--------|
| 1 | **Careerjet API** | REST `search.api.careerjet.net/v4/query`, Basic Auth mit Publisher-Key | Publisher-Konto (Such-API historisch frei/kostenlos; **Fair-Use-Limits live prüfen**) | `de_DE` via `careerjet.de` | Aggregator → überlappt mit BA/Adzuna. Felder: Titel/Firma/Ort/Beschreibungs-Ausschnitt/Gehalt/`url`. **Kein** Arbeitgeber-E-Mail-Feld; `url` ist Tracking-Redirect (`jobviewtrack.com`) → gleiche Kontakt-Kaskaden-Lücke wie bei der BA. | ❌ Kandidat |
| 2 | **Jooble API** | REST | Free ~100 Req/Monat | DE | Bereits in dieser Datei abgelehnt (Mini-Limit, Aggregator-Duplikate, flache Daten). | ❌ bewusst nicht |
| 3 | **BA-JOBBÖRSE** | REST | frei | DE | Bereits primär. | ✅ |
| 4 | **Adzuna** | REST | Free 50 Calls/Tag | DE (+`gb`…) | Bereits sekundär. | ✅ |
| 5 | **Google Jobs** | nur über bezahlte Aggregatoren | kostenpflichtig | DE | Bereits letzter Fallback via SerpAPI. | ✅ (Fallback) |

> **Zu 1 (live verifiziert, 2026-09-08):** Der Careerjet-Endpunkt und das JSON-Schema
> sind real und abrufbar (Endpunkt `/v4/query`, `locale_code=de_DE`, Parameter
> `keywords`/`location`/`contract_type`/`work_hours`/`page`/`radius`, `user_ip` +
> `user_agent` sind Pflicht). Careerjet ist ein **Aggregator** (fremde Anzeigen
> gebündelt) und kein *echter* Abdeckungs-Gewinn gegenüber BA+Adzuna; sinnvoll wäre er
> höchstens als günstiger Ersatz für den kostenpflichtigen SerpAPI-Fallback. Das
> *kostenlose* Fair-Use-Kontingent ist in der Doku nicht fest beziffert → wie bei der BA
> erst mit einem Test-Key verifizieren, bevor eingebunden wird.

### B) Nischen-/Spezialportale (im Browser kostenlos, programmatisch nur Scraping → abgelehnt)

- **Öffentlicher Dienst:** `interamt.de`, `karriere.bund.de`, kommunale Portale,
  Hochschul-Karriereportale. Kein offener, frei nutzbarer
  Verbraucher-Such-Endpunkt dokumentiert; Abdeckung läuft teils schon über BA
  (Behörden schalten dort) und Google Jobs/SerpAPI.
- **Startup-/Remote-Nischen:** Freelancer-/Remote-Börsen sind teils für Endnutzer
  kostenlos, haben aber keine öffentliche REST-Suche → nur HTML/Scraping
  (rechtlich offen, siehe `doc/plan/10`, Topic 8). Gleiche Ablehnungslogik wie bei
  StepStone/Monster in dieser Datei.
- **Indeed / LinkedIn / StepStone / Monster / XING:** keine kostenlose
  Verbraucher-Such-API (Indeed-API 2024 eingestellt, LinkedIn nur Enterprise,
  StepStone/Monster nur B2B-Vertrag oder Scraping). → keine neue Erkenntnis,
  bereits in `doc/plan/10` und oben dokumentiert.

### C) „Wege an Angebote zu kommen“ (keine neue Börse, kostenlos & legitim)

| # | Weg | Wo in der App | Aufwand | Anmerkung |
|---|-----|---------------|---------|-----------|
| 1 | **Direkte Karriereseiten / Impressum von Wunscharbeitgebern** | `JobScraperService` (Detail-URL) + `EmailDiscoveryService` (Kontakt) | gering | Kein neuer Code nötig; funktioniert für *einzelne, bekannte* URLs. Nicht für *proaktives* Finden neuer Stellen. |
| 2 | **Externe Anzeigen/ATS, auf die die BA verlinkt** | `BaApiService.fetchJobDetails` → `externeURL`; `BaContactResolver`-Kaskade | erledigt | Viele BA-Treffer sind extern (`BaMarketStats` misst den Anteil). |
| 3 | **RSS-/Atom-Job-Feeds** von Nischen-/Karriere-/Unternehmensseiten | kein Service | mittel (optionaler Feed-Parser) | RSS ist für maschinelles Lesen gedacht → legitim. Coverage aber schmal und sehr uneinheitlich; nur als optionale Zusatzquelle für Spezial-Nischen sinnvoll. |
| 4 | **Offene Job-Daten/-Exporte öffentlicher Stellen** (z. B. Interamt-Exporte, falls vorhanden) | kein Service | zu prüfen | Erst verifizieren, ob es einen offiziellen, frei nutzbaren Export/Feed gibt; sonst Scraping-Falle. |

### Fazit

- **Einziger vielversprechender *neuer* REST-Kandidat: Careerjet-API** als
  kostenloser Ersatz für den kostenpflichtigen SerpAPI-Fallback. Einbindung analog zu
  den bestehenden Quellen: neuer `CareerjetApiService` mit gleichem `search()`-Vertrag
  → `List<JobOffer>`, in `JobSearchService` nach Adzuna (vor SerpAPI) einklinken,
  `source: 'careerjet'`, bestehende URL-Dedup/Cache wiederverwenden, Tracking-URLs über
  `_normalizeUrlKey` normalisieren. **~0,5–1 Tag.** Vorher live verifizieren:
  kostenloses Kontingent, `de_DE`-Abdeckung, Tracking-Redirect-Verhalten.
- **Alle übrigen „Börsen“ sind entweder kostenpflichtig, Scraping-pflichtig oder
  bereits indirekt über Google Jobs/SerpAPI und die BA abgedeckt** – kein
  Zusatznutzen, der den Aufwand (bzw. das rechtliche Risiko) rechtfertigt. Das deckt
  sich mit dem Addendum oben: Der sinnvollste kostenlose Hebel bleibt, die
  Adzuna-Freischicht auszuschöpfen, nicht ein fragiles Portal-Scraping aufzubauen.
- **Der größte reale „Coaching“-Hebel** ist nicht eine weitere Börse, sondern die
  vorhandene Kontakt-Kaskade (Stufe 2–4 in dieser Datei): gezielt auf
  Arbeitgeber-Websites/Impressen zugreifen statt weitere Anzeigen-Aggregatoren zu
  suchen.

## Frage
Was heißt das konkret: Careerjet vor SerpAPI einbinden (SerpAPI behalten)? Und was ergab die Recherche zu offenen Job-Daten öffentlicher Stellen und zu Suchmaschinen-Anfragen?

## Antwort 4 (Stand: 2026-09-08)

**Kaskade danach:** BA → Adzuna → **Careerjet** → SerpAPI (bleibt als letzter
kostenpflichtiger Fallback). Careerjet ist eingebunden als kostenloser Lückenfüller
zwischen Adzuna und SerpAPI; SerpAPI wird bewusst behalten.

### Umgesetzt (Careerjet)

- Neu `lib/data/services/api/careerjet_api_service.dart` – `CareerjetApiService`
  mit gleichem `search()`-Vertrag wie Adzuna/SerpAPI
  (`query/location/radius/employmentType/page/size` → `List<JobOffer>`,
  `source: 'careerjet'`). Endpunkt `search.api.careerjet.net/v4/query`,
  `locale_code=de_DE`, Basic-Auth mit Publisher-Key (via `ApiKeyService`).
  Tolerantes Parsen (Firma/Orte als String **oder** Objekt/Liste), Gehalt aus
  `salary_min/max` + Währung, stable id via `fnv1a32(url)`.
- **`user_ip`-Pflichtfeld:** Careerjet verlangt pro Request `user_ip` +
  `user_agent`. `user_ip` wird einmal pro Prozess über `api.ipify.org` ermittelt
  (Fallback `0.0.0.0`). → **Offener Verifikationspunkt:** Mit einem echten
  Publisher-Key prüfen, ob Careerjet diesen Client-IP-Mechanismus akzeptiert.
- `ApiKeyService.careerjetApiKey` (`'careerjet'`), Key-Feld + Konnektivitäts-Check
  (`_checkCareerjet`) im Einstellungen-Screen.
- Verdrahtet in `JobSearchService` als Schritt 3 (nur falls BA+Adzuna < 10
  Treffer) und in `providers.dart` (`careerjetApiServiceProvider`).
- Tests grün: `careerjet_api_service_test.dart` (Request/Auth/Parsing/Fehler/IP-
  Fallback), `job_search_service_test.dart` (Kaskaden-Reihenfolge + „SerpAPI bleibt
  letzter Fallback“), `api_connectivity_service_test.dart`.
- Hinweis: Careerjet ist Aggregator → keine echte Zusatz-Abdeckung, **kein**
  Arbeitgeber-E-Mail-Feld; nur als (kostenloser) Ersatz für den SerpAPI-Fallback
  sinnvoll.

### Recherche: offene Job-Daten öffentlicher Stellen + Suchmaschinen

| Quelle | Befund | Konsequenz |
|--------|--------|------------|
| **BA-JOBBÖRSE / bundesAPI** | Einziger offizieller, freier, maschinenlesbarer Zugang zu (auch öffentlichen) Stellen ist die bereits integrierte BA-REST-API (`rest.arbeitsagentur.de`). `bundesAPI` (`github.com/bundesAPI`) dokumentiert `jobsuche-api`; `bewerberboerse-api` ist nicht-öffentlich. Achtung: Die **bund.dev-Proxies** sind aktuell wegen Überlastung offline – die App spricht `rest.arbeitsagentur.de` direkt an (kein Problem). | ✅ abgedeckt; keine Code-Änderung |
| **Interamt / karriere.bund.de / kommunale Portale** | Kein öffentlicher, frei nutzbarer API/Export dokumentiert; nur B2B-Integrationen oder Scraping. Öffentliche Stellen laufen bereits weitgehend über die BA (Behörden sind dort meldepflichtig) und Google Jobs/SerpAPI. | ❌ kein legitimer Zugang → nicht einbinden |
| **DuckDuckGo** | Instant-Answer-API liefert **keine Web-Ergebnisse** (live geprüft: `Results: []` für generische Query); volle Web-Suche nur über kostenpflichtige Business-API; `html.duckduckgo.com`-Scraping → Captcha. | ❌ nicht nutzbar |
| **Bing Web Search API (Azure)** | Offiziell, Key nötig; Free-F1 ≈ 1.000 Transaktionen/Monat; nur „Suche“-Nutzung. Liefert **generische Web-Ergebnisse** (Titel/URL/Snippet), kein strukturiertes Job-JSON. | ➖ optional (eigener Key, mäßige Qualität), nicht umgesetzt |
| **Brave Search API** | Eigener Web-Index; ~$5 Free-Credits/Monat (≈ 2.000 Requests); keine Job-Vertikale; Ergebnis-Speicherung nur mit Paid-Plan. | ➖ optional (eigener Key), nicht umgesetzt |

**Fazit Recherche:** Kein neuer Code für „offene Daten öffentlicher Stellen“ –
die BA deckt den öffentlichen Sektor ab; Interamt/karriere.bund.de scheiden aus
(kein freier, legitimer, maschinenlesbarer Zugang). Für „Suchmaschinen-Anfragen“
bleibt SerpAPI (Google Jobs) der beste *strukturierte* Fallback. Generische
Websuche (Bing/Brave) wäre nur ein optionaler, Key-basierter Dienst mit **lose**
gemappten Ergebnissen (Firma = Host der Ziel-URL) – bewusst **nicht** umgesetzt;
stattdessen dokumentiert. DuckDuckGo wird abgelehnt (kein freier Web-Ergebnis-Zugang).

**Offen/Verifikation:** Careerjet – freies Publisher-Kontingent & `de_DE`-Abdeckung
und das `user_ip`-Verhalten mit einem selbst angelegten Publisher-Key live prüfen
(Konto auf careerjet.com/publisher), bevor die Quelle als „produktiv“ gilt.
