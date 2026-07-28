# Jobsuche – Integration der BA-JOBBÖRSE-API

Da die Einbindung der Jobbörse vom Arbeitsamt (Bundesagentur für Arbeit) derzeit nicht funktioniert, dokumentiert dieses Dokument den aktuellen Stand, die identifizierten Probleme und den Lösungsansatz.

---

## 1. Ausgangslage

| Aspekt | Beschreibung |
|---|---|
| **API (laut GitHub-Repo)** | Inoffizielle API der BA-JOBBÖRSE (Repository: https://github.com/bundesAPI/jobsuche-api) |
| **Implementierung (IST)** | `BaApiService` in `lib/data/services/api/ba_api_service.dart` |
| **HTTP-Client** | `ApiClient` in `lib/data/services/api/api_client.dart` (mit Retry-Logik, Timeout, API-Key-Management) |
| **Orchestrierung** | `JobSearchService` in `lib/data/services/api/job_search_service.dart` (koordiniert BA + zukünftige Quellen) |
| **API-Key-Verwaltung** | `ApiKeyService` in `lib/data/services/api/api_key_service.dart` (verschlüsselte Speicherung via `flutter_secure_storage`) |
| **Status** | ❌ Nicht funktionsfähig – siehe Probleme |

### Technische Details – SOLL (laut GitHub-Repo)

- **Basis-URL**: `rest.arbeitsagentur.de`
- **Such-Endpunkt (IST)**: `/jobsearch/v1/jobsearch` ❌ **falsch**
- **Such-Endpunkt (SOLL)**: `/jobboerse/jobsuche-service/pc/v6/jobs` ✅ (alternativ `/pc/v4/jobs` oder `/pc/v4/app/jobs`)
- **Jobdetail-Endpunkt**: `/jobboerse/jobsuche-service/pc/v4/jobdetails/{base64(refnr)}`
- **Logo-Endpunkt**: `/vermittlung/ag-darstellung-service/ct/v1/arbeitgeberlogo/{hash}`
- **Authentifizierung**: `X-API-Key`-Header mit **festem Wert**: `jobboerse-jobsuche` (keine Registrierung nötig!)
  - Fallback: `X-API-KEY: jobboerse-jobsuche` (andere Schreibweise)
- **Query-Parameter (IST)**: `fulltext`, `ort`, `umkreis`, `arbeitszeit` ❌ **teilweise falsch**
- **Query-Parameter (SOLL)**: `was` (Jobtitel), `wo` (Ort), `umkreis` (km), `arbeitszeit` (vz/tz/snw/ho/mj), `page`, `size`, `berufsfeld`, `arbeitgeber`, `angebotsart`, `befristung`, `zeitarbeit`, `pav`, `veroeffentlichtseit`, `corona`, `behinderung`
- **Response-Felder**: siehe GitHub-Repo – abweichend von aktueller Implementierung
- **Retry-Logik**: max. 3 Versuche, exponentielles Backoff, Timeout 15s
- **Keine Registrierung erforderlich** – der API-Key ist ein öffentlicher, statischer Wert

---

## 2. Problemanalyse

Folgende Probleme wurden identifiziert (laufend zu ergänzen):

### 2.1 Mögliche Fehlerquellen

| # | Problem | Priorität | Status |
|---|---|---|---|
| 1 | **Falscher Endpunkt (Such-Pfad)** – Aktuell `/jobsearch/v1/jobsearch`, korrekt ist `/jobboerse/jobsuche-service/pc/v6/jobs` | Hoch | ⬜ Offen |
| 2 | **Falsche Query-Parameter** – Aktuell `fulltext`/`ort`, korrekt ist `was`/`wo` – auch `arbeitszeit`-Werte weichen ab (`vollzeit` → `vz`, `teilzeit` → `tz`) | Hoch | ⬜ Offen |
| 3 | **Falscher/fehlender API-Key** – Es wird ein registrierter Key vermutet, aber die API verwendet einen **festen, öffentlichen Wert**: `jobboerse-jobsuche` | Hoch | ⬜ Offen |
| 4 | **Response-Format weicht ab** – Die erwarteten Felder (`stellenangebote[].refnr`, `.titel`, `.arbeitgeber`) stimmen ggf. nicht mit der tatsächlichen API-Response überein | Mittel | ⬜ Offen |
| 5 | **CORS / Netzwerk-Restriktionen** – Bei Web-Builds könnten CORS-Probleme auftreten (lokaler Dev-Server vs. API) | Mittel | ⬜ Offen |
| 6 | **Rate-Limiting** – Die API könnte bei zu vielen Anfragen 429-Fehler werfen (wird von ApiClient mit Retry behandelt) | Niedrig | ⬜ Offen |

### 2.2 Bekannte Fehler/Besonderheiten

> *Hier können spezifische Fehlermeldungen oder Beobachtungen dokumentiert werden, sobald sie aufgetreten sind.*

---

## 3. Bisherige Lösungsversuche

| Datum | Versuch | Ergebnis | Erkenntnis |
|---|---|---|---|
| 2026-07-26 | Analyse der BA-JOBBÖRSE-API anhand des GitHub-Repos (bundesAPI/jobsuche-api) und Vergleich mit Ist-Implementierung | Abweichungen in Endpunkt, Query-Parametern und API-Key identifiziert | Siehe Abschnitt 1 und 2 |
| 2026-07-26 | Korrektur von `BaApiService`: Endpunkt auf `/pc/v6/jobs`, Parameter auf `was`/`wo`/`vz`/`tz`, API-Key auf festen Wert `jobboerse-jobsuche` geändert | Code-Änderungen durchgeführt; noch nicht getestet | Nächster Schritt: Verbindung per curl testen |

---

## 4. Lösungsansatz

### Schritt 1: `BaApiService` korrigieren (Endpunkt + Query-Parameter + API-Key)

Die Implementierung in `BaApiService` muss an die tatsächliche API angepasst werden. Die wichtigsten Änderungen:

**1.1 Such-Endpunkt korrigieren**
```
aktuell:  /jobsearch/v1/jobsearch
korrekt:  /jobboerse/jobsuche-service/pc/v6/jobs
```

**1.2 Query-Parameter anpassen**
| aktuell (IST) | korrekt (SOLL) |
|---|---|
| `fulltext=Begriff` | `was=Begriff` |
| `ort=Stadt` | `wo=Stadt` |
| `arbeitszeit=vollzeit` | `arbeitszeit=vz` |
| `arbeitszeit=teilzeit` | `arbeitszeit=tz` |

Vollständige Liste der verfügbaren Parameter (alle optional):
- `was` – Freitextsuche Jobtitel
- `wo` – Freitextsuche Beschäftigungsort
- `umkreis` – Umkreis in km (z. B. 25, 200)
- `arbeitszeit` – `vz` (Vollzeit), `tz` (Teilzeit), `snw` (Schicht), `ho` (Heim/Telearbeit), `mj` (Minijob); mehrere Werte mit `;` trennbar
- `page` – Seite (beginnend mit 1)
- `size` – Anzahl der Ergebnisse
- `berufsfeld` – Freitext Berufsfeld
- `arbeitgeber` – ID des Arbeitgebers
- `angebotsart` – `1` (Arbeit), `2` (Selbstständigkeit), `4` (Ausbildung), `34` (Praktikum)
- `befristung` – `1` (befristet), `2` (unbefristet); mit `;` trennbar
- `zeitarbeit` – `true`/`false` (default: `true`)
- `pav` – `true`/`false` (private Arbeitsvermittlung)
- `veroeffentlichtseit` – 0–100 Tage
- `corona` – `true`/`false`
- `behinderung` – `true`/`false`

**1.3 API-Key auf festen Wert setzen (keine Registrierung nötig!)**

Die API authentifiziert nicht über individuell registrierte Keys, sondern über einen festen, öffentlichen Wert:

- **Header**: `X-API-Key: jobboerse-jobsuche`
- **Fallback**: `X-API-KEY: jobboerse-jobsuche` (alternative Schreibweise)

Der Key muss **nicht** registriert werden. Er kann direkt im Code als Konstante hinterlegt werden (z. B. in `BaApiService`), statt über `ApiKeyService` mit `flutter_secure_storage` zu laden. Die bestehende `ApiKeyService`-Integration kann für andere APIs (Adzuna, SerpAPI) weiterhin genutzt werden.

**1.4 Response-Felder prüfen und `_parseJobOffers` anpassen**

Die tatsächliche API-Response muss mit einem Testaufruf (siehe Schritt 2) analysiert werden. Erwartete Felder laut GitHub-Repo:
- `refnr` / `referenznummer` – Referenznummer der Stelle
- `titel` / `stellenangebotsTitel` – Titel der Stelle
- `arbeitgeber` – Arbeitgebername
- `ort` – Beschäftigungsort
- `kurzbeschreibung` / `stellenangebotsBeschreibung` – Beschreibung
- `aktuelleVeroeffentlichungsdatum` – Veröffentlichungsdatum
- `externeUrl` – ggf. externe URL (bei externen Stellenanzeigen)

### Schritt 2: Verbindung testen

- Manuellen Test des korrigierten Endpunkts durchführen:
  ```bash
  curl -H "X-API-Key: jobboerse-jobsuche" \
    "https://rest.arbeitsagentur.de/jobboerse/jobsuche-service/pc/v6/jobs?was=Flutter&wo=Berlin&umkreis=200&page=1&size=10"
  ```
- Erwartet: JSON mit HTTP 200
- Response-Struktur notieren, um das Parsing in `_parseJobOffers` anzupassen

### Schritt 3: App-log prüfen

- Logger-Ausgaben von `BaApiService`, `ApiClient` und `JobSearchService` überprüfen
- Fehlermeldung aus `JobSearchResult.errorMessage` im UI auswerten

### Schritt 4: Response-Parsing validieren

- Bei erfolgreichem API-Call: Die tatsächlichen JSON-Feldnamen mit den erwarteten (`refnr`, `titel`, `arbeitgeber`, etc.) abgleichen
- Ggf. `_parseJobOffers` in `BaApiService` anpassen

### Schritt 5: Fallback-Mechanismus prüfen

- `JobSearchService` gibt bei BA-Fehler einen `errorMessage` zurück, aber schlägt nicht fehl
- UI (vermutlich `JobSearchScreen`) sollte den Fehler anzeigen und dem Nutzer Handlungsoptionen bieten

---

## 5. Nächste Schritte

- [ ] `BaApiService` korrigieren: Endpunkt auf `/jobboerse/jobsuche-service/pc/v6/jobs` ändern
- [ ] `BaApiService` korrigieren: Query-Parameter `fulltext` → `was`, `ort` → `wo`, `arbeitszeit`-Werte anpassen
- [ ] `BaApiService` korrigieren: API-Key auf festen Wert `jobboerse-jobsuche` setzen (statt über `ApiKeyService`)
- [ ] API-Verbindung manuell testen (curl mit korrektem Endpunkt und Key)
- [ ] Tatsächliche Response-Struktur analysieren und `_parseJobOffers` anpassen
- [ ] Fehlerbehandlung im UI verbessern (Anzeige konkreter Handlungsanweisungen)
- [ ] Integration weiterer Job-Quellen (Adzuna, SerpAPI) vorbereiten (siehe `ApiKeyService`-Konstanten)

---

## 6. Offene Fragen / Risiken

| Frage / Risiko | Notiz |
|---|---|
| Gibt es ein tägliches Request-Limit? | Unbekannt – sollte getestet werden |
| Funktioniert die API auch ohne `User-Agent`-Header? | `ApiClient` setzt `User-Agent: Job-O-Matic/1.0` |
| Ist die API über HTTPS erreichbar? | Ja, `Uri.https()` wird verwendet |
| Welche HTTP-Methoden werden unterstützt? | Derzeit nur GET implementiert |
| Funktioniert der Fallback `X-API-KEY` (andere Schreibweise) noch? | Laut GitHub-Repo als Fallback dokumentiert |
| Sind die Response-Felder zwischen `/pc/v6/jobs` und `/pc/v4/jobs` identisch? | Unterschiedliche Versionen – `/v6` bevorzugen |

---

## 7. Entscheidungslog

| Datum | Entscheidung | Begründung |
|---|---|---|
| 2026-07-26 | API-Dokumentation von https://jobsuche.api.bund.dev/ auf https://github.com/bundesAPI/jobsuche-api umgestellt | Die jobsuche.api.bund.dev-Seite war nicht zielführend; das GitHub-Repo enthält die tatsächliche API-Doku mit korrekten Endpunkten |
| 2026-07-26 | Endpunkt von `/jobsearch/v1/jobsearch` auf `/jobboerse/jobsuche-service/pc/v6/jobs` geändert | Gemäß GitHub-Repo ist dies der korrekte Such-Endpunkt; der alte Endpunkt existiert so nicht |
| 2026-07-26 | Query-Parameter `fulltext` → `was`, `ort` → `wo` geändert | Die API erwartet diese Parameternamen; die alten wurden ignoriert |
| 2026-07-26 | API-Key von registrierungspflichtigem Key auf festen Wert `jobboerse-jobsuche` umgestellt | Die API verwendet einen öffentlichen, statischen Key – keine Registrierung nötig. Der Key kann direkt als Konstante in `BaApiService` hinterlegt werden, `ApiKeyService` wird nicht mehr für BA benötigt |
| 2026-07-26 | `arbeitszeit`-Werte von `vollzeit`/`teilzeit` auf `vz`/`tz` geändert | Entspricht den von der API erwarteten Codes (vz=VOLLZEIT, tz=TEILZEIT) |
| 2026-07-26 | `apiKeyName`-Parameter aus `_client.get()`-Aufruf entfernt, stattdessen `X-API-Key`-Header direkt gesetzt | Da der Key fest und öffentlich ist, entfällt die Notwendigkeit, ihn über `ApiKeyService` zu laden |
