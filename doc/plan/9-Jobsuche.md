# Jobsuche – Integration der BA-JOBBÖRSE-API

Dieses Dokument beschreibt den aktuellen Stand, die identifizierten Probleme und den Lösungsansatz für die Einbindung der Jobbörse der Bundesagentur für Arbeit (BA).

> **Status-Übersicht (Stand: 2026-07-26, verifiziert per curl):**
> - ✅ Endpunkt, Query-Parameter und API-Key sind korrigiert und **funktionsfähig** (HTTP 200)
> - ❌ **Response-Parsing ist fehlerhaft** – `_parseJobOffers` erwartet falsche Feldnamen und liefert daher immer 0 Ergebnisse
> - ⚠️ UI-Fehlermeldung in `JobSearchScreen` ist veraltet (verweist auf nicht mehr nötige Key-Registrierung)

---

## 1. Ausgangslage

| Aspekt | Beschreibung |
|---|---|
| **API (laut GitHub-Repo)** | Inoffizielle API der BA-JOBBÖRSE (Repository: https://github.com/bundesAPI/jobsuche-api) |
| **Implementierung (IST)** | `BaApiService` in `lib/data/services/api/ba_api_service.dart` |
| **HTTP-Client** | `ApiClient` in `lib/data/services/api/api_client.dart` (mit Retry-Logik, Timeout, API-Key-Management) |
| **Orchestrierung** | `JobSearchService` in `lib/data/services/api/job_search_service.dart` (koordiniert BA + zukünftige Quellen) |
| **API-Key-Verwaltung** | `ApiKeyService` in `lib/data/services/api/api_key_service.dart` (verschlüsselte Speicherung via `flutter_secure_storage`) – **für BA nicht mehr benötigt** |
| **Status** | ⚠️ Teilweise funktionsfähig – Verbindung steht, Parsing defekt (siehe Abschnitt 3) |

---

## 2. Technische Details – SOLL (verifiziert)

### 2.1 Endpunkte

| Zweck | Endpunkt | Status |
|---|---|---|
| **Jobsuche** | `/jobboerse/jobsuche-service/pc/v6/jobs` | ✅ Verifiziert (HTTP 200) |
| Jobdetails | `/jobboerse/jobsuche-service/pc/v4/jobdetails/{base64(refnr)}` | ⬜ Noch nicht getestet |
| Logo | `/vermittlung/ag-darstellung-service/ct/v1/arbeitgeberlogo/{hash}` | ⬜ Noch nicht getestet |

- **Basis-URL**: `rest.arbeitsagentur.de` (HTTPS)

### 2.2 Authentifizierung

Die API verwendet einen **festen, öffentlichen API-Key** – keine Registrierung nötig:

- **Header**: `X-API-Key: jobboerse-jobsuche` ✅ verifiziert
- **Fallback**: `X-API-KEY: jobboerse-jobsuche` (andere Schreibweise, laut GitHub-Repo)

Der Key ist bereits als Konstante `_apiKey` in `BaApiService` hinterlegt. `ApiKeyService` wird für die BA nicht mehr benötigt, bleibt aber für Adzuna/SerpAPI/Brevo relevant.

### 2.3 Query-Parameter (alle optional)

| Parameter | Bedeutung | Beispiel |
|---|---|---|
| `was` | Freitextsuche Jobtitel | `was=Flutter` |
| `wo` | Freitextsuche Beschäftigungsort | `wo=Berlin` |
| `umkreis` | Umkreis in km | `umkreis=200` |
| `arbeitszeit` | `vz` (Vollzeit), `tz` (Teilzeit), `snw` (Schicht), `ho` (Heim/Telearbeit), `mj` (Minijob); mehrere Werte mit `;` trennbar | `arbeitszeit=vz;tz` |
| `page` | Seite (beginnend mit 1) | `page=1` |
| `size` | Anzahl der Ergebnisse | `size=20` |
| `berufsfeld` | Freitext Berufsfeld | `berufsfeld=Informatik` |
| `arbeitgeber` | ID des Arbeitgebers | – |
| `angebotsart` | `1` (Arbeit), `2` (Selbstständigkeit), `4` (Ausbildung), `34` (Praktikum) | `angebotsart=1` |
| `befristung` | `1` (befristet), `2` (unbefristet); mit `;` trennbar | `befristung=1` |
| `zeitarbeit` | `true`/`false` (default: `true`) | `zeitarbeit=false` |
| `pav` | `true`/`false` (private Arbeitsvermittlung) | – |
| `veroeffentlichtseit` | 0–100 Tage | `veroeffentlichtseit=30` |
| `corona` | `true`/`false` | – |
| `behinderung` | `true`/`false` | – |

### 2.4 Retry-Logik (ApiClient)

- Max. 3 Versuche, exponentielles Backoff, Timeout 15s
- 429 (Rate-Limit) wird mit steigender Wartezeit (5s × Versuch) behandelt

---

## 3. Problemanalyse

### 3.1 Mögliche Fehlerquellen

| # | Problem | Priorität | Status |
|---|---|---|---|
| 1 | **Falscher Endpunkt (Such-Pfad)** – war `/jobsearch/v1/jobsearch`, korrigiert auf `/jobboerse/jobsuche-service/pc/v6/jobs` | Hoch | ✅ Behoben & verifiziert |
| 2 | **Falsche Query-Parameter** – waren `fulltext`/`ort`, korrigiert auf `was`/`wo`; `arbeitszeit`-Werte auf `vz`/`tz` | Hoch | ✅ Behoben & verifiziert |
| 3 | **Falscher/fehlender API-Key** – war registrierungspflichtig, korrigiert auf festen Wert `jobboerse-jobsuche` | Hoch | ✅ Behoben & verifiziert |
| 4 | **Response-Format weicht ab** – `_parseJobOffers` erwartet `stellenangebote[].refnr/.titel/.arbeitgeber`, die API liefert aber `ergebnisliste[].referenznummer/.stellenangebotsTitel/.firma` | **Hoch** | ❌ **Offen – Hauptproblem** |
| 5 | **CORS / Netzwerk-Restriktionen** – bei Web-Builds möglich (lokaler Dev-Server vs. API) | Mittel | ⬜ Offen |
| 6 | **Rate-Limiting** – API könnte 429 werfen (wird von ApiClient mit Retry behandelt) | Niedrig | ⬜ Offen |
| 7 | **Veraltete UI-Fehlermeldung** – `JobSearchScreen` verweist auf Key-Registrierung unter `jobsuche.api.bund.dev`, die nicht mehr nötig ist | Mittel | ⬜ Offen |

### 3.2 Verifizierte API-Response (Stand: 2026-07-26)

Testaufruf:
```bash
curl -H "X-API-Key: jobboerse-jobsuche" \
  "https://rest.arbeitsagentur.de/jobboerse/jobsuche-service/pc/v6/jobs?was=Flutter&page=1&size=1"
```
→ **HTTP 200**

**Top-Level-Struktur:**
```json
{
  "ergebnisliste": [ ... ],
  "maxErgebnisse": 1234,
  "page": 1,
  "size": 1,
  "woOutput": "...",
  "facetten": { ... }
}
```

**Einzelnes Stellenangebot (gekürzt):**
```json
{
  "stellenangebotsart": "ARBEIT",
  "stellenangebotsTitel": "Ingenieur (m/w/d) Testautomatisierung Flutter und Dart",
  "arbeitszeitVollzeit": true,
  "gehaltsspanneVon": 45000.0,
  "gehaltsspanneBis": 78000.0,
  "stellenlokationen": [
    { "adresse": { "plz": "68163", "ort": "Mannheim", "region": "BADEN_WUERTTEMBERG", "land": "DEUTSCHLAND" } }
  ],
  "datumErsteVeroeffentlichung": "2026-07-24",
  "hauptberuf": "Ingenieur/in - Automatisierungstechnik",
  "firma": "FERCHAU GmbH Niederlassung Mannheim",
  "referenznummer": "12265-487930_JB5205113-S",
  "alleBerufe": [ "Ingenieur/in - Automatisierungstechnik" ]
}
```

**Feld-Mapping (IST-Code → tatsächliche API):**

| Zweck | `_parseJobOffers` erwartet (IST) | Tatsächliche API (SOLL) | Status |
|---|---|---|---|
| Ergebnisliste | `data['stellenangebote']` | `data['ergebnisliste']` | ❌ Falsch |
| Job-ID | `map['refnr']` | `map['referenznummer']` | ❌ Falsch |
| Titel | `map['titel']` | `map['stellenangebotsTitel']` | ❌ Falsch |
| Arbeitgeber | `map['arbeitgeber']` | `map['firma']` | ❌ Falsch |
| Ort | `map['ort']` | `map['stellenlokationen'][0]['adresse']['ort']` | ❌ Falsch |
| Beschreibung | `map['kurzbeschreibung']` | In Listen-Response **nicht enthalten** (nur in Jobdetails) | ❌ Falsch |
| Veröffentlichungsdatum | `map['aktuelleVeroeffentlichungsdatum']` | `map['datumErsteVeroeffentlichung']` | ❌ Falsch |

> **Konsequenz:** Da `data['stellenangebote']` nicht existiert, liefert `_parseJobOffers` aktuell immer eine leere Liste – die Suche „funktioniert" (HTTP 200), zeigt aber keine Ergebnisse.

---

## 4. Bisherige Lösungsversuche

| Datum | Versuch | Ergebnis | Erkenntnis |
|---|---|---|---|
| 2026-07-26 | Analyse der BA-JOBBÖRSE-API anhand des GitHub-Repos (bundesAPI/jobsuche-api) und Vergleich mit Ist-Implementierung | Abweichungen in Endpunkt, Query-Parametern und API-Key identifiziert | Siehe Abschnitt 2 und 3 |
| 2026-07-26 | Korrektur von `BaApiService`: Endpunkt auf `/pc/v6/jobs`, Parameter auf `was`/`wo`/`vz`/`tz`, API-Key auf festen Wert `jobboerse-jobsuche` geändert | Code-Änderungen durchgeführt | Verbindung steht |
| 2026-07-26 | Manueller Test per curl mit korrigiertem Endpunkt und Key | ✅ **HTTP 200**, gültige JSON-Response | Endpunkt, Parameter und Key sind korrekt; Response-Struktur dokumentiert (Abschnitt 3.2) |
| 2026-07-26 | Vergleich der tatsächlichen Response mit `_parseJobOffers` | ❌ **Parsing-Fehler identifiziert** – Feldnamen weichen vollständig ab | `_parseJobOffers` muss angepasst werden (Abschnitt 5) |

---

## 5. Lösungsansatz

### Schritt 1: `_parseJobOffers` an die tatsächliche Response anpassen (Hauptaufgabe)

Die Methode in `BaApiService` muss auf die verifizierte Response-Struktur umgestellt werden:

**1.1 Ergebnisliste lesen**
```dart
// aktuell (falsch):
final items = data['stellenangebote'] as List<dynamic>? ?? [];
// korrekt:
final items = data['ergebnisliste'] as List<dynamic>? ?? [];
```

**1.2 Feld-Mapping korrigieren**

| `JobOffer`-Feld | Quelle in der API-Response |
|---|---|
| `id` | `referenznummer` |
| `title` | `stellenangebotsTitel` |
| `company` | `firma` |
| `location` | `stellenlokationen[0].adresse.ort` (ggf. mehrere Orte zu einem String verbinden) |
| `description` | In Listen-Response nicht enthalten → `null` lassen oder Jobdetails-Endpunkt nachladen |
| `url` | `https://www.arbeitsagentur.de/jobsuche/job/{referenznummer}` |
| `publishedAt` | `datumErsteVeroeffentlichung` (Format `YYYY-MM-DD`) |
| `source` | `'ba'` |

**1.3 Optional: Zusatzfelder nutzen**

Die Response enthält weitere nützliche Felder, die in `JobOffer` abgebildet werden könnten:
- `gehaltsspanneVon` / `gehaltsspanneBis` → `salaryRange` (z. B. `"45.000 € – 78.000 €"`)
- `arbeitszeitVollzeit` → `employmentType`
- `hauptberuf` / `alleBerufe` → ggf. für Filterung

### Schritt 2: Verbindung erneut testen

```bash
curl -H "X-API-Key: jobboerse-jobsuche" \
  "https://rest.arbeitsagentur.de/jobboerse/jobsuche-service/pc/v6/jobs?was=Flutter&wo=Berlin&umkreis=200&page=1&size=10"
```
- Erwartet: HTTP 200 mit `ergebnisliste` (nicht leer)
- Response-Struktur mit Abschnitt 3.2 abgleichen

### Schritt 3: UI-Fehlermeldung in `JobSearchScreen` korrigieren

Die Fehlermeldung (Zeilen ~230–235) verweist noch auf eine nicht mehr nötige Key-Registrierung:
> „Die BA-Jobsuche benötigt einen kostenlosen API-Key. Registrieren Sie sich unter https://jobsuche.api.bund.dev/ ..."

Dies ist **veraltet** – die BA-API nutzt einen festen, öffentlichen Key. Die Meldung sollte z. B. lauten:
> „Die Jobsuche ist derzeit nicht erreichbar. Bitte versuchen Sie es später erneut."

### Schritt 4: App-Log prüfen

- Logger-Ausgaben von `BaApiService`, `ApiClient` und `JobSearchService` überprüfen
- Fehlermeldung aus `JobSearchResult.errorMessage` im UI auswerten

### Schritt 5: Fallback-Mechanismus prüfen

- `JobSearchService` gibt bei BA-Fehler einen `errorMessage` zurück, schlägt aber nicht fehl
- Adzuna wird als Fallback genutzt, wenn BA wenig/keine Ergebnisse liefert
- UI (`JobSearchScreen`) zeigt den Fehler an und bietet Handlungsoptionen

---

## 6. Nächste Schritte

- [x] `BaApiService` korrigieren: Endpunkt auf `/jobboerse/jobsuche-service/pc/v6/jobs` ändern
- [x] `BaApiService` korrigieren: Query-Parameter `fulltext` → `was`, `ort` → `wo`, `arbeitszeit`-Werte anpassen
- [x] `BaApiService` korrigieren: API-Key auf festen Wert `jobboerse-jobsuche` setzen (statt über `ApiKeyService`)
- [x] API-Verbindung manuell testen (curl mit korrektem Endpunkt und Key) → **HTTP 200**
- [x] Tatsächliche Response-Struktur analysieren → dokumentiert in Abschnitt 3.2
- [ ] `_parseJobOffers` anpassen: `ergebnisliste` + korrekte Feldnamen (`referenznummer`, `stellenangebotsTitel`, `firma`, `stellenlokationen[].adresse.ort`, `datumErsteVeroeffentlichung`)
- [ ] Optional: `salaryRange` und `employmentType` aus `gehaltsspanneVon/Bis` und `arbeitszeitVollzeit` befüllen
- [ ] Veraltete UI-Fehlermeldung in `JobSearchScreen` korrigieren (Key-Registrierung entfernen)
- [ ] Integration weiterer Job-Quellen (Adzuna, SerpAPI) vorbereiten (siehe `ApiKeyService`-Konstanten)

---

## 7. Offene Fragen / Risiken

| Frage / Risiko | Notiz |
|---|---|
| Gibt es ein tägliches Request-Limit? | Unbekannt – sollte getestet werden |
| Funktioniert die API auch ohne `User-Agent`-Header? | `ApiClient` setzt `User-Agent: Job-O-Matic/1.0` |
| Ist die API über HTTPS erreichbar? | Ja, `Uri.https()` wird verwendet – verifiziert |
| Welche HTTP-Methoden werden unterstützt? | Derzeit nur GET implementiert |
| Funktioniert der Fallback `X-API-KEY` (andere Schreibweise) noch? | Laut GitHub-Repo als Fallback dokumentiert |
| Sind die Response-Felder zwischen `/pc/v6/jobs` und `/pc/v4/jobs` identisch? | Unterschiedliche Versionen – `/v6` bevorzugen |
| Enthält die Listen-Response jemals eine Beschreibung? | Nein – `kurzbeschreibung` fehlt; ggf. Jobdetails-Endpunkt nachladen |
| Wie viele Orte können in `stellenlokationen` vorkommen? | Mehrere möglich – Parsing sollte alle Orte berücksichtigen |

---

## 8. Entscheidungslog

| Datum | Entscheidung | Begründung |
|---|---|---|
| 2026-07-26 | API-Dokumentation von https://jobsuche.api.bund.dev/ auf https://github.com/bundesAPI/jobsuche-api umgestellt | Die jobsuche.api.bund.dev-Seite war nicht zielführend; das GitHub-Repo enthält die tatsächliche API-Doku mit korrekten Endpunkten |
| 2026-07-26 | Endpunkt von `/jobsearch/v1/jobsearch` auf `/jobboerse/jobsuche-service/pc/v6/jobs` geändert | Gemäß GitHub-Repo ist dies der korrekte Such-Endpunkt; der alte Endpunkt existiert so nicht |
| 2026-07-26 | Query-Parameter `fulltext` → `was`, `ort` → `wo` geändert | Die API erwartet diese Parameternamen; die alten wurden ignoriert |
| 2026-07-26 | API-Key von registrierungspflichtigem Key auf festen Wert `jobboerse-jobsuche` umgestellt | Die API verwendet einen öffentlichen, statischen Key – keine Registrierung nötig. Der Key kann direkt als Konstante in `BaApiService` hinterlegt werden, `ApiKeyService` wird nicht mehr für BA benötigt |
| 2026-07-26 | `arbeitszeit`-Werte von `vollzeit`/`teilzeit` auf `vz`/`tz` geändert | Entspricht den von der API erwarteten Codes (vz=VOLLZEIT, tz=TEILZEIT) |
| 2026-07-26 | `apiKeyName`-Parameter aus `_client.get()`-Aufruf entfernt, stattdessen `X-API-Key`-Header direkt gesetzt | Da der Key fest und öffentlich ist, entfällt die Notwendigkeit, ihn über `ApiKeyService` zu laden |
| 2026-07-26 | Response-Parsing als Hauptproblem identifiziert (Feldnamen weichen ab) | Verifiziert per curl: `ergebnisliste` statt `stellenangebote`, `referenznummer` statt `refnr`, etc. |