# Aktueller Stand

> **Status-Übersicht (Stand: 2026-08-10)**
> - ✅ **BA-JOBBÖRSE-API** – Verbindung steht (HTTP 200), **Response-Parsing korrigiert** → Suche liefert Ergebnisse
> - ✅ **Adzuna-API** – Implementiert, benötigt App-ID + API-Key (Free-Tier: 50 Calls/Tag)
> - ✅ **JobScraperService** – HTML-Scraping **in `JobInputScreen` eingebunden** – extrahiert Job-Details aus URLs
> - ❌ **SerpAPI/Google Jobs** – Key-Konstante vorhanden, Service **nicht implementiert**
> - ✅ **UI-Fehlermeldung** in `JobSearchScreen` **korrigiert** (Key-Registrierungs-Hinweis entfernt)
> - ✅ **Unit-Tests** für `BaApiService._parseJobOffers` hinzugefügt (6 Tests bestanden)

---

## 1. Integrierte Jobbörsen

| # | Quelle | Service | Status | Authentifizierung | Anmerkung |
|---|--------|---------|--------|-------------------|-----------|
| 1 | **BA-JOBBÖRSE** (Bundesagentur für Arbeit) | `BaApiService` | ✅ Funktionsfähig | Fester, öffentlicher Key (`X-API-Key: jobboerse-jobsuche`) | Parsing korrigiert, inkl. Gehalt & Beschäftigungsart |
| 2 | **Adzuna** | `AdzunaApiService` | ✅ Implementiert | App-ID + API-Key (via `ApiKeyService`) | Free-Tier: 50 Calls/Tag |
| 3 | **HTML-Scraping** (Fallback) | `JobScraperService` | ✅ Eingebunden | Keine | In `JobInputScreen` integriert – extrahiert Titel/Firma/Ort aus URLs |

### 1.1 BA-JOBBÖRSE (primär)

- **Endpunkt:** `/jobboerse/jobsuche-service/pc/v6/jobs` (Basis: `rest.arbeitsagentur.de`)
- **API-Key:** Fester, öffentlicher Wert `jobboerse-jobsuche` – keine Registrierung nötig
- **Query-Parameter:** `was`, `wo`, `umkreis`, `arbeitszeit` (`vz`/`tz`), `page`, `size`, u. v. m.
- **Retry-Logik:** Max. 3 Versuche, exponentielles Backoff, Timeout 15s (via `ApiClient`)
- **Parsing:** `ergebnisliste`, `referenznummer`, `stellenangebotsTitel`, `firma`, `stellenlokationen[].adresse.ort`, `datumErsteVeroeffentlichung` – inkl. `salaryRange` und `employmentType`
- **Dokumentation:** https://github.com/bundesAPI/jobsuche-api

### 1.2 Adzuna (sekundär)

- **Endpunkt:** `https://api.adzuna.com/v1/api/jobs/de/search/{page}`
- **Authentifizierung:** App-ID + API-Key, gespeichert via `flutter_secure_storage`
- **Rate-Limit:** 50 API-Calls/Tag im Free-Tier
- **Dokumentation:** https://developer.adzuna.com/

### 1.3 HTML-Scraping (Fallback)

- **Zweck:** Extraktion von Titel, Firma, Beschreibung und Ort aus Stellen-URLs
- **Status:** In `JobInputScreen` eingebunden – extrahiert Job-Details beim Hinzufügen von URLs
- **Risiken:** Rechtliche Einschränkungen (AGB, Urheberrecht), CAPTCHA, fragile CSS-Selektoren

---

## 2. Noch fehlende Jobbörsen

| # | Quelle | Status | Aufwand | Anmerkung |
|---|--------|--------|---------|-----------|
| 1 | **SerpAPI / Google Jobs** | ❌ Nicht implementiert | Mittel | Key-Konstante `serpapi` existiert in `ApiKeyService`; Service-Klasse fehlt |
| 2 | **Indeed** | ❌ Nicht verfügbar | – | API wurde 2024 eingestellt; nur noch über Partnerprogramm |
| 3 | **LinkedIn** | ❌ Nicht verfügbar | – | Nur Enterprise-Lizenz |
| 4 | **Jooble** | ❌ Nicht implementiert | Gering | Free-Tier: 100 Requests/Monat |
| 5 | **StepStone** | ❌ Nicht implementiert | – | Keine öffentliche API; nur Scraping möglich |
| 6 | **Monster** | ❌ Nicht implementiert | – | Keine öffentliche API; nur Scraping möglich |

---

## 3. Begrenzungen

| Bereich | Begrenzung | Details |
|---------|-----------|---------|
| **BA-JOBBÖRSE** | Request-Limit | 100 Anfragen/Stunde (laut Planungsdokument, nicht verifiziert) |
| **Adzuna** | Rate-Limit | 50 API-Calls/Tag im Free-Tier |
| **SerpAPI** | Kosten | Kostenpflichtig (ab ~500 Requests/Monat) |
| **Scraping** | Rechtlich | AGB-Konformität, Urheberrecht, E-Commerce-Gesetz |
| **Scraping** | Technisch | CAPTCHA, Bot-Erkennung, HTTP 403, fragile Selektoren |
| **Web-Builds** | CORS | Mögliche Netzwerk-Restriktionen bei Web-Deployment |
| **Beschreibung** | BA-API | Listen-Response enthält **keine** Stellenbeschreibung – nur über Jobdetails-Endpunkt |
| **Cache** | TTL | 30 Minuten, max. 100 Einträge (LRU-Eviction) |

---

## 4. Probleme

### 4.1 ✅ Behoben: BA-Response-Parsing

`_parseJobOffers` in `BaApiService` erwartete früher falsche Feldnamen und lieferte daher **immer 0 Ergebnisse**. Das Parsing wurde auf die verifizierte Response-Struktur umgestellt und durch 6 Unit-Tests abgesichert:

| Zweck | Code erwartet (IST – behoben) | Tatsächliche API (SOLL) | Status |
|-------|-------------------------------|-------------------------|--------|
| Ergebnisliste | `data['ergebnisliste']` | `data['ergebnisliste']` | ✅ Behoben |
| Job-ID | `map['referenznummer']` | `map['referenznummer']` | ✅ Behoben |
| Titel | `map['stellenangebotsTitel']` | `map['stellenangebotsTitel']` | ✅ Behoben |
| Arbeitgeber | `map['firma']` | `map['firma']` | ✅ Behoben |
| Ort | `map['stellenlokationen'][0]['adresse']['ort']` | `map['stellenlokationen'][0]['adresse']['ort']` | ✅ Behoben |
| Beschreibung | `null` (nicht in Listen-Response) | In Listen-Response **nicht enthalten** | ✅ Behoben |
| Veröffentlichungsdatum | `map['datumErsteVeroeffentlichung']` | `map['datumErsteVeroeffentlichung']` | ✅ Behoben |
| Gehalt | `gehaltsspanneVon`/`gehaltsspanneBis` | ✅ Neu hinzugefügt |
| Beschäftigungsart | `arbeitszeitVollzeit`/`arbeitszeitTeilzeit` | ✅ Neu hinzugefügt |

### 4.2 ✅ Behoben: Veraltete UI-Fehlermeldung

`JobSearchScreen` zeigte eine veraltete Meldung zur Key-Registrierung. Die Meldung wurde ersetzt durch:
> „Die Jobsuche ist derzeit nicht erreichbar. Bitte versuchen Sie es später erneut."

### 4.3 ✅ Behoben: JobScraperService eingebunden

`JobScraperService` war implementiert, wurde aber nirgends aufgerufen. Er ist jetzt in `JobInputScreen._onContinue()` integriert:
- Extrahiert Titel, Firma, Ort beim Hinzufügen von URLs
- Ergebnisse werden im `JobRepository` gespeichert (`saveScrapeResults`)
- `createApplicationsFromUrls()` nutzt die gescrapten Details für bessere Applikationsdaten
- Bei Scraping-Fehlern wird ohne Job-Details fortgefahren (kein Blocker)

### 4.4 Adzuna-Key-Konfiguration

Adzuna erfordert manuelle Key-Eingabe durch den Nutzer. Ohne konfigurierte Keys schlägt die sekundäre Suche fehl (wird aber korrekt als Fallback behandelt).

### 4.5 Kein SerpAPI-Service

`ApiKeyService` definiert die Konstante `serpapi`, aber es existiert **keine** `SerpApiService`-Klasse – die geplante Fallback-Quelle fehlt vollständig.

---

## 5. Offene Topics

| # | Topic | Priorität | Status |
|---|-------|-----------|--------|
| 1 | **SerpAPI-Service implementieren** – Als kostenpflichtige Premium-Option | 🟡 Mittel | ❌ Offen |
| 2 | **Portal-spezifische Scraper-Selektoren** – StepStone, Indeed, LinkedIn | 🟢 Niedrig | ❌ Offen |
| 3 | **CAPTCHA-Erkennung** – Automatischer Abbruch bei CAPTCHA | 🟢 Niedrig | ❌ Offen |
| 4 | **Connectivity-Check** – `connectivity_plus` vor API-Aufruf (Offline-Hinweis) | 🟢 Niedrig | ❌ Offen |
| 5 | **Fuzzy-Ranking** – Skill-Abgleich mit CV-Daten (in Planungsdokument erwähnt, nicht implementiert) | 🟢 Niedrig | ❌ Offen |
| 6 | **Jobdetails-Endpunkt** – Beschreibung nachladen (`/pc/v4/jobdetails/{base64(refnr)}`) | 🟢 Niedrig | ❌ Offen |

---

## 6. Offene Fragen

| # | Frage | Notiz | Status |
|---|-------|-------|--------|
| 1 | Gibt es ein tägliches Request-Limit bei der BA-API? | 🔄 **Testen und anpassen** | 🔄 Offen |
| 2 | Funktioniert die BA-API auch ohne `User-Agent`-Header? | 🔄 **Testen** – `ApiClient` setzt `User-Agent: Job-O-Matic/1.0` | 🔄 Offen |
| 3 | Funktioniert der Fallback `X-API-KEY` (andere Schreibweise) noch? | ✅ **Ja** – laut GitHub-Repo als Fallback dokumentiert | ✅ Geklärt |
| 4 | Sind die Response-Felder zwischen `/pc/v6/jobs` und `/pc/v4/jobs` identisch? | 🔄 **Testen** – unterschiedliche Versionen, `/v6` bevorzugen | 🔄 Offen |
| 5 | Enthält die Listen-Response jemals eine Beschreibung? | 🟡 **Durch Scraping ergänzen** – `kurzbeschreibung` fehlt in Listen-Response | 🟡 Entscheidung |
| 6 | Wie viele Orte können in `stellenlokationen` vorkommen? | ✅ **Mehrere möglich** – Parsing berücksichtigt alle Orte | ✅ Geklärt |
| 7 | Soll SerpAPI als kostenpflichtige Option angeboten werden? | ✅ **Ja** – als Premium-Option anbieten | ✅ Geklärt |
| 8 | Ist Scraping für StepStone/Monster rechtlich zulässig? | 🔄 **Prüfung läuft** – Einbinden wäre praktisch | 🔄 Offen |

---

## 7. Nächste Schritte (Priorisiert)

- [x] **`_parseJobOffers` in `BaApiService` korrigieren** – `ergebnisliste`, `referenznummer`, `stellenangebotsTitel`, `firma`, `stellenlokationen[].adresse.ort`, `datumErsteVeroeffentlichung`
- [x] **UI-Fehlermeldung in `JobSearchScreen` aktualisieren** – Key-Registrierungs-Hinweis entfernen
- [x] **`JobScraperService` in `JobInputScreen` einbinden** – Extrahiert Job-Details aus URLs
- [x] **Unit-Tests für `BaApiService._parseJobOffers`** – 6 Tests mit verifizierter Response-Struktur bestanden
- [ ] **SerpAPI-Service implementieren** – `SerpApiService` mit Key aus `ApiKeyService`
- [ ] **Optional:** Jobdetails-Endpunkt für Beschreibungen nachladen

---

_Stand: 2026-08-10_
_Dieses Dokument wird bei Projektfortschritt aktualisiert._