# API-Anbindung

Im Zuge der Entwicklung unserer App ist es an der Zeit, die API-Anbindung zu planen. Dieser Abschnitt analysiert die verfügbaren Optionen für Job-Such-APIs, Web-Scraping zur Stellenextraktion und E-Mail-Versand sowie deren Integration in die bestehende Architektur.

---

## 1. Übersicht: Anwendungsfälle für API-Integrationen

| Anwendungsfall | Beschreibung | Status |
|----------------|-------------|--------|
| **Job-Suche** | Stellenangebote über externe Suchmaschinen abrufen (Screen 2) | Mock vorhanden, API fehlt |
| **Job-Detail-Extraktion** | Aus einer Stellen-URL die relevanten Daten (Titel, Firma, Beschreibung) extrahieren (Screen 1) | Nicht implementiert |
| **E-Mail-Versand** | Fertige Bewerbungs-PDFs versenden (Automailer) | In Planung (Phase 5) |
| **Bewerberportal-Automation** | Automatisiertes Ausfüllen von Portal-Formularen | In Planung (Phase 6) |

---

## 2. Job-Such-APIs

### 2.1 Vergleich der Anbieter

| API | Kostenlos-Tier | Rate-Limit | REST | Standorte | DSGVO | Bewertung |
|-----|---------------|------------|------|-----------|-------|-----------|
| **Bundesagentur für Arbeit (JOBBÖRSE)** | ✅ Ja | 100 Anfragen/Stunde (verified) | ✅ Ja | 🇩🇪 DE | ✅ Ja | ⭐ Beste Wahl für dt. Markt |
| **Adzuna** | ✅ Ja (50 API-Calls/Tag) | 50/Tag kostenlos | ✅ Ja | 🇬🇧 UK | ⚠️ SCCs | ⭐ Gut, aber geringes Limit |
| **Indeed** | ❌ Nur über Partnerprogramm | – | ⚠️ Eingestellt 2024 | – | – | ❌ Nicht mehr verfügbar |
| **LinkedIn** |  Nur Enterprise | – | ✅ Ja | 🌍 Global | ⚠️ | ❌ Nur für große Unternehmen |
| **Google Jobs (via SerpAPI)** | ❌ Kostenpflichtig | Ab ~500/Monat | ✅ Ja | 🌍 Global | ✅ | ⭐ Beste Abdeckung, aber Kosten |
| **Jooble** | ✅ Ja (100 Requests/Monat) | 100/Monat | ✅ Ja | 🇺🇦 UA | ⚠️ | Mittel – geringes Limit |
| **Indeed unsichtbar (HTML-Scraping)** | ⚠️ Rechtlich fragwürdig | – | ❌ Nein (HTML) | – | – | ❌ Nicht empfohlen |

### 2.2 Empfehlung: Mehrere Quellen kombinieren

```
┌─────────────┐     REST API       ┌──────────────┐
│  Job-O-Matic │ ───────────────►  │  BA JOBBÖRSE │
│  (Flutter)   │                   │  (primär)     │
│              │ ───────────────►  │  Adzuna       │
│              │                   │  (sekundär)    │
│              │ ───────────────►  │  SerpAPI      │
│              │                   │  (Fallback)    │
└─────────────┘                   └──────────────┘
```

**Strategie:**
1. **Primär:** Bundesagentur für Arbeit JOBBÖRSE-API (kostenlos, DSGVO-konform, deutsche Stellen)
2. **Sekundär:** Adzuna API (50 Calls/Tag kostenlos, gute Abdeckung DE/AT/CH)
3. **Fallback:** SerpAPI/Google Jobs (kostenpflichtig, aber beste Ergebnisse)
4. **Manuelle Eingabe:** URL-Listing (benutzerdefiniert, Screen 1)

### 2.3 Bundesagentur für Arbeit – JOBBÖRSE-API

- **Dokumentation:** [https://jobsuche.api.bund.dev/](https://jobsuche.api.bund.dev/)
- **Authentifizierung:** API-Key (kostenlos beantragbar)
- **Endpunkte:**
  - `GET /api/v1/jobsearch` – Stellensuche mit Parametern
  - `GET /api/v1/job/{id}` – Detailinformationen zu einer Stelle
- **Parameter:** `fulltext`, `ort`, `umkreis`, `page`, `size`, `arbeitszeit`, `beruf`

#### Beispiel-Request (Dart)

```dart
import 'package:http/http.dart' as http;
import 'dart:convert';

Future<List<JobOffer>> searchJobsBA({
  required String query,
  String? location,
  int radius = 25,
  int page = 1,
  int size = 20,
}) async {
  final params = <String, String>{
    'fulltext': query,
    'page': page.toString(),
    'size': size.toString(),
  };
  if (location != null && location.isNotEmpty) {
    params['ort'] = location;
    params['umkreis'] = radius.toString();
  }

  final uri = Uri.https('rest.arbeitsagentur.de', '/jobsearch/v1/jobsearch', params);
  final response = await http.get(
    uri,
    headers: {'X-API-Key': _apiKey},
  );

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseJobOffers(data);
  }
  throw JobApiException('BA API error: ${response.statusCode}');
}
```

#### HTML-Extraktion (Scraping)

Für Stellen-URLs, die kein strukturiertes API-Format bieten, kommt **clientseitiges Scraping** infrage:

```dart
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;   // hinzufügen: html: ^0.15.4

Future<JobDetails> extractJobFromUrl(String url) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) {
    throw JobApiException('HTTP ${response.statusCode}');
  }

  final document = parser.parse(response.body);
  return JobDetails(
    title: _tryExtract(document, [
      'meta[property="og:title"]',
      'h1.job-title',
      'h1[class*=title]',
    ]),
    company: _tryExtract(document, [
      'meta[property="og:site_name"]',
      '[class*=company]',
      '[class*=employer]',
    ]),
    description: _tryExtract(document, [
      'meta[property="og:description"]',
      '[class*=description]',
      '[class*=job-text]',
    ]),
  );
}

String? _tryExtract(Document doc, List<String> selectors) {
  for (final selector in selectors) {
    final element = doc.querySelector(selector);
    if (element != null) {
      return element.text.trim();
    }
  }
  return null;
}
```

**Wichtig:** Scraping unterliegt rechtlichen Einschränkungen (AGB, Urheberrecht, E-Commerce-Gesetz). Es sollte nur als **Fallback** eingesetzt werden, wenn keine API verfügbar ist.

### 2.4 Datenmodell: `JobOffer`

```dart
class JobOffer {
  final String id;
  final String title;
  final String company;
  final String? location;
  final String? description;
  final String url;
  final String? salaryRange;
  final EmploymentType? employmentType;
  final WorkModel? workModel;
  final DateTime? publishedAt;
  final String source; // 'ba', 'adzuna', 'serpapi', 'manual'

  const JobOffer({
    required this.id,
    required this.title,
    required this.company,
    this.location,
    this.description,
    required this.url,
    this.salaryRange,
    this.employmentType,
    this.workModel,
    this.publishedAt,
    required this.source,
  });
}

enum EmploymentType { fullTime, partTime, both }
enum WorkModel { onSite, hybrid, remote, any }
```

---

## 3. Architektur: Service-Schicht für API-Integration

### 3.1 Package-Struktur (neu)

```
lib/
└── data/
    ├── repositories/
    │   └── job_repository.dart          # Bestehend
    ├── services/
    │   ├── api/
    │   │   ├── api_client.dart          # HTTP-Client mit Auth, Retry, Logging
    │   │   ├── job_search_service.dart   # Orchestriert alle API-Quellen
    │   │   ├── ba_api_service.dart       # Bundesagentur für Arbeit
    │   │   ├── adzuna_api_service.dart   # Adzuna
    │   │   ├── serpapi_service.dart      # SerpAPI/Google Jobs
    │   │   └── job_scraper_service.dart  # HTML-Scraping (Fallback)
    │   └── email/
    │       └── email_service.dart       # Automailer (später)
    └── models/
        ├── job_offer.dart               # JobOffer + Enums (NEU)
        └── ...                          # Bestehende Modelle
```

### 3.2 `ApiClient` – Zentrale HTTP-Client-Klasse

```dart
/// Zentrale HTTP-Client-Klasse für alle API-Anfragen.
/// 
/// Features:
/// - Singleton HTTP-Client (Connection-Pooling)
/// - Automatisches Retry mit exponentiellem Backoff
/// - Einheitliches Logging
/// - API-Key-Management
/// - Timeout-Konfiguration
class ApiClient {
  static const Duration defaultTimeout = Duration(seconds: 15);
  static const int maxRetries = 3;

  final Logger _log;
  final http.Client _client;
  final Map<String, String> _apiKeys;

  ApiClient({
    required Logger logger,
    Map<String, String>? apiKeys,
    http.Client? client,
    Duration? timeout,
  })  : _log = logger,
        _client = client ?? http.Client(),
        _apiKeys = apiKeys ?? {},
        _timeout = timeout ?? defaultTimeout;

  final Duration _timeout;

  Future<http.Response> get(
    Uri uri, {
    String? apiKeyName,
    Map<String, String>? extraHeaders,
  }) async {
    final headers = <String, String>{
      'User-Agent': 'Job-O-Matic/1.0',
      if (apiKeyName != null && _apiKeys.containsKey(apiKeyName))
        'X-API-Key': _apiKeys[apiKeyName]!,
      ...?extraHeaders,
    };

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        _log.fine('GET ${uri.toString()} (Versuch $attempt/$maxRetries)');
        final response = await _client.get(uri, headers: headers)
            .timeout(_timeout);

        if (response.statusCode == 429) {
          // Rate-Limited – warten und wiederholen
          final retryAfter = Duration(seconds: 5 * attempt);
          _log.warning('Rate-Limited. Warte ${retryAfter.inSeconds}s...');
          await Future.delayed(retryAfter);
          continue;
        }

        _log.fine('Antwort ${response.statusCode} von $uri');
        return response;
      } on TimeoutException {
        _log.warning('Timeout für $uri (Versuch $attempt/$maxRetries)');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: 2 * attempt));
        }
      } catch (e, stack) {
        _log.severe('Fehler bei API-Anfrage: $e', e, stack);
        rethrow;
      }
    }

    throw JobApiException('Maximale Anzahl Versuche ($maxRetries) überschritten');
  }

  /// API-Key sicher speichern (nicht im Code, sondern via Konfiguration)
  void setApiKey(String name, String key) {
    _apiKeys[name] = key;
  }
}
```

### 3.3 `JobSearchService` – Orchestrierung

```dart
/// Orchestriert die Jobsuche über mehrere Quellen.
///
/// Reihenfolge: BA → Adzuna → SerpAPI (kaskadierend)
/// Ergebnisse werden dedupliziert und fusioniert.
class JobSearchService {
  final ApiClient _client;
  final BaApiService _baService;
  final AdzunaApiService _adzunaService;
  final Logger _log;

  JobSearchService({
    required ApiClient client,
    required BaApiService baService,
    required AdzunaApiService adzunaService,
    required Logger logger,
  })  : _client = client,
        _baService = baService,
        _adzunaService = adzunaService,
        _log = logger;

  Future<List<JobOffer>> searchJobs({
    required String query,
    String? location,
    int radius = 25,
    EmploymentType? employmentType,
    WorkModel? workModel,
    Map<String, dynamic>? extraFilters,
    CancelToken? cancelToken,
  }) async {
    final allResults = <JobOffer>[];
    final seenUrls = <String>{};

    // 1. Bundesagentur für Arbeit
    try {
      final baResults = await _baService.search(
        query: query,
        location: location,
        radius: radius,
        employmentType: employmentType,
        cancelToken: cancelToken,
      );
      for (final job in baResults) {
        if (seenUrls.add(job.url)) {
          allResults.add(job);
        }
      }
      _log.info('BA: ${baResults.length} Ergebnisse');
    } on JobApiException catch (e) {
      _log.warning('BA-API fehlgeschlagen: ${e.message} – fahre mit Adzuna fort');
    }

    // 2. Adzuna (falls BA keine/wenige Ergebnisse liefert)
    if (allResults.length < 10) {
      try {
        final adzunaResults = await _adzunaService.search(
          query: query,
          location: location,
          radius: radius,
          cancelToken: cancelToken,
        );
        for (final job in adzunaResults) {
          if (seenUrls.add(job.url)) {
            allResults.add(job);
          }
        }
        _log.info('Adzuna: ${adzunaResults.length} Ergebnisse');
      } on JobApiException catch (e) {
        _log.warning('Adzuna-API fehlgeschlagen: ${e.message}');
      }
    }

    // 3. Post-Filterung (clientseitig)
    var filtered = _applyFilters(allResults, employmentType, workModel, extraFilters);

    // 4. Fuzzy-Ranking (Skill-Abgleich)
    if (_cvData != null) {
      filtered = _rankBySkillMatch(filtered);
    }

    _log.info('Jobsuche abgeschlossen: ${filtered.length} Ergebnisse (nach Filter/Ranking)');
    return filtered;
  }

  List<JobOffer> _applyFilters(
    List<JobOffer> jobs,
    EmploymentType? employmentType,
    WorkModel? workModel,
    Map<String, dynamic>? extraFilters,
  ) {
    // Implementierung siehe FilterService (1-AppBasis.md)
  }

  List<JobOffer> _rankBySkillMatch(List<JobOffer> jobs) {
    // Fuzzy-Logik aus assets/fuzzy-logic einbinden
  }
}
```

### 3.4 API-Key-Management

API-Keys dürfen **nicht** im Quellcode oder in der Versionskontrolle gespeichert werden:

| Speicherort | Sicherheit | Empfehlung |
|-------------|-----------|------------|
| **Umgebungsvariablen** | Hoch | ✅ Für Entwicklungs-/Desktop-Umgebungen |
| **`.env`-Datei** (via `envied`-Package) | Mittel | ✅ Für Entwicklung (in `.gitignore`) |
| **Flutter Secure Storage** | Hoch | ✅ Für Mobile (verschlüsselt) |
| **App-Konfiguration** (`assets/config/`) | Niedrig | ❌ Nur für Public-Keys |
| **Hardcoded im Code** | Keine | ❌ Niemals |

```dart
// Beispiel: API-Keys aus Umgebungsvariablen (für Server/Desktop)
class ApiKeyProvider {
  String? get baApiKey => Platform.environment['JOBOMATIC_BA_API_KEY'];
  String? get adzunaAppId => Platform.environment['JOBOMATIC_ADZUNA_APP_ID'];
  String? get adzunaApiKey => Platform.environment['JOBOMATIC_ADZUNA_API_KEY'];

  bool get hasRequiredKeys => baApiKey != null;
}
```

---

## 4. Integration in bestehende Architektur

### 4.1 Datenfluss: Screen 2 (Jobsuche) mit API

```
User-Eingabe (Jobbeschreibung, Ort, Umkreis, Filter)
        │
        ▼
JobSearchScreen._performSearch()
        │
        ▼
JobSearchService.searchJobs(query, location, radius, ...)
        │
        ├──► BaApiService.search()          (REST: Bundesagentur)
        ├──► AdzunaApiService.search()      (REST: Adzuna)
        └──► Post-Filter + Fuzzy-Ranking
        │
        ▼
List<JobOffer> (zurück an Screen)
        │
        ▼
JobRepository.addJobsFromSearch(selectedIds)
        │
        ▼
Navigation zu /applications
```

### 4.2 Datenfluss: Screen 1 (URL-Eingabe) mit Scraping

```
User-Eingabe (mehrere URLs)
        │
        ▼
JobInputScreen (Validierung auf URL-Format)
        │
        ▼
JobScraperService.extractJobs(urls)
        │
        ├──► http.get(url) für jede URL
        ├──► html::parser.parse(response.body)
        └──► Extraktion: title, company, description, location
        │
        ▼
List<JobOffer> → Application-Liste
        │
        ▼
Navigation zu /applications
```

### 4.3 Riverpod-Integration

```dart
// lib/data/services/api/api_client_provider.dart
final apiClientProvider = Provider<ApiClient>((ref) {
  final logger = ref.read(appLoggerProvider);
  return ApiClient(logger: logger);
});

// lib/data/services/api/job_search_service_provider.dart
final jobSearchServiceProvider = Provider<JobSearchService>((ref) {
  final client = ref.read(apiClientProvider);
  final logger = ref.read(appLoggerProvider);
  return JobSearchService(
    client: client,
    baService: BaApiService(client, logger),
    adzunaService: AdzunaApiService(client, logger),
    logger: logger,
  );
});

// lib/data/repositories/job_repository.dart (Erweiterung)
class JobRepository {
  // Bestehende Felder + neu:
  List<JobOffer> _searchResults = [];
  List<JobOffer> get searchResults => List.unmodifiable(_searchResults);

  void setSearchResults(List<JobOffer> results) {
    _searchResults = results;
    _logger.info('Suchergebnisse aktualisiert: ${results.length} Jobs');
  }
}
```

---

## 5. Fehlerbehandlung & Edge Cases

| Szenario | Behandlung |
|----------|-----------|
| **API nicht erreichbar (Timeout)** | Automatischer Retry (3x, exponentieller Backoff) → Fehlermeldung mit "Erneut versuchen"-Button |
| **Rate-Limit erreicht (HTTP 429)** | Wartezeit einhalten, dann erneut versuchen → Bei erneutem Fehlschlag: Benachrichtigung + Fallback zur nächsten API |
| **Ungültiger API-Key** | Deutlicher Hinweis in der UI + Logeintrag auf `severe`-Level + Verweis auf Konfiguration |
| **Keine Ergebnisse** | Leerer Zustand (Empty State) mit Vorschlägen zur Erweiterung der Suchkriterien |
| **Scraping fehlgeschlagen (z. B. HTTP 403)** | Fallback: URL manuell in Zwischenablage öffnen lassen – "Diese Seite konnte nicht automatisch gelesen werden. Bitte öffnen Sie die URL manuell." |
| **CAPTCHA beim Scraping** | Abbruch der Automatisierung + manuelle Eingabeaufforderung |
| **Stellen-URL nicht mehr gültig (HTTP 404)** | Fehlerstatus für diese Bewerbung (status = `failed`) + Fehlermeldung im Detail |
| **Kein Internet** | Prüfung via `connectivity_plus` vor API-Aufruf; bei Offline: gecachte Ergebnisse anzeigen + Hinweis |
| **API-Änderungen (Breaking Changes)** | Versionierte API-Endpunkte verwenden (z. B. `/v1/`, `/v2/`); regelmäßige Integrationstests |

---

## 6. Abhängigkeiten (pubspec.yaml – Erweiterung)

```yaml
dependencies:
  # Bestehend (bereits enthalten):
  http: ^1.2.0

  # Neu hinzuzufügen:
  html: ^0.15.4                          # HTML-Parsing für Scraping
  connectivity_plus: ^6.0.0              # Internetverbindungsprüfung
  flutter_secure_storage: ^9.0.0        # Sichere API-Key-Speicherung (Mobile)
  envied: ^0.5.0                         # .env-Unterstützung (optional)
```

---

## 7. Nächste Schritte & Priorisierung

### Phase 1: Grundlagen (sofort)
- [ ] **`ApiClient` implementieren** – Zentrale HTTP-Client-Klasse mit Retry, Timeout, Logging
- [ ] **`JobOffer`-Datenmodell erstellen** – Einheitliches Modell für alle API-Quellen
- [ ] **Bestehende Mock-Suche durch ApiClient ersetzen** – `JobSearchScreen` entkoppeln

### Phase 2: Primäre API (2–3 Wochen)
- [ ] **BA-JOBBÖRSE-API anbinden** – `BaApiService` implementieren
- [ ] **API-Key-Management** – Sichere Speicherung einrichten
- [ ] **Integration in `JobSearchService`** – Orchestrierung mit Post-Filter
- [ ] **Integrationstests** – Gegen reale API-Endpunkte testen (mit Dummy-Schlüssel)

### Phase 3: Sekundäre Quellen (optional, 1–2 Wochen)
- [ ] **Adzuna-API anbinden** – `AdzunaApiService`
- [ ] **Caching-Strategie** – Ergebnisse für 30 Minuten cachen (Rate-Limit-Schonung)

### Phase 4: Scraping (bei Bedarf, 1–2 Wochen)
- [ ] **`JobScraperService` implementieren** – HTML-Parsing mit Selektoren
- [ ] **Portal-spezifische Selector-Konfiguration** (StepStone, Indeed, LinkedIn)
- [ ] **CAPTCHA-Erkennung** – Automatischer Abbruch bei CAPTCHA

### Phase 5: E-Mail-Integration (später)
- [ ] Siehe `doc/plan/3-automailer.md` für detaillierte Planung

---

## 8. Entscheidungsmatrix: API-Stack

| Kriterium | Gewicht | BA JOBBÖRSE | Adzuna | SerpAPI | Scraping |
|-----------|---------|-------------|--------|---------|----------|
| Kosten | Hoch | ✅ 10/10 | ✅ 8/10 | ⚠️ 3/10 | ✅ 10/10 |
| Abdeckung DE | Hoch | ✅ 10/10 | ✅ 7/10 | ✅ 9/10 | ✅ 6/10 |
| DSGVO-Konform | Hoch | ✅ 10/10 | ⚠️ 5/10 | ✅ 8/10 | ⚠️ 4/10 |
| Stabilität | Mittel | ✅ 9/10 | ✅ 8/10 | ✅ 8/10 | ❌ 3/10 |
| Einfachheit | Mittel | ✅ 8/10 | ✅ 9/10 | ✅ 7/10 | ❌ 4/10 |
| **Gesamt** | | **47/50** | **37/50** | **35/50** | **27/50** |

**Ergebnis:** BA JOBBÖRSE-API als primäre Quelle, Adzuna als sekundäre, SerpAPI als kostenpflichtige Premium-Option, Scraping nur als letzter Fallback.