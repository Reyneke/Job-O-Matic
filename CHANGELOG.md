# Changelog

All notable changes to the Job-O-Matic project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-07-28

### Added
- **Sprint 1: Projekt-Grundlage & Datenimport**
  - Flutter-Projekt-Setup mit Ordnerstruktur
  - State-Management mit Riverpod
  - Theme-System mit Dark/Light-Mode-Unterstützung
  - Datenmodelle: `PersonalData`, `WorkExperience`, `Education`, `Skill`, `Application`, `JobOffer`, `CvData`
  - CV-Daten-Parser aus YAML
  - Routing mit `go_router`
  - Zentrale-Logging mit Datei-Rotation

- **Sprint 2: Kernfunktionen**
  - UI-Screen 1: Stelleneingabe mit URL-Validierung
  - UI-Screen 2: Jobsuche mit Filter und Fuzzy-Ranking
  - UI-Screen 3: Ergebnisübersicht mit Batch-Export
  - UI-Screen 3a: Detailansicht mit PDF-Vorschau
  - Datenbank-Persistenz mit SQFlite (Schema, CRUD, Migrationen)
  - API-Anbindung: BA-JOBBÖRSE-API
  - PDF-Generierung: Deckblatt, Lebenslauf, Anschreiben
  - Vorlagen-System mit Platzhaltern `{{variable}}`

- **Sprint 3: Infrastruktur & Integration**
  - **Automailer:** Brevo-API-Integration, E-Mail-Templates (Mustache), Queue-System mit Rate-Limiter, Circuit-Breaker, Retry mit exponentiellem Backoff
  - **Adzuna-API:** Sekundäre Job-Suche-Quelle
  - **ApiCacheService:** 30-Minuten-Cache mit LRU-Eviction
  - **JobScraperService:** HTML-Parsing für Stellen-URLs (Fallback)
  - **Datenbank-Persistenz Phase D:** Autosave (5s-Debounce) für Stelleneingabe
  - **PDF-Bereinigung:** Entfernung verwaister PDF-Dateien beim App-Start
  - **API-Key-Verwaltung:** Konfigurationsscreen für alle API-Keys

- **Sprint 4: Qualitätssicherung & CI/CD**
  - **CI/CD Pipeline Phase 1:** `quality_check.yaml` – Lint, Analyse, Tests, Coverage
  - **CI/CD Pipeline Phase 2:** `build_all.yaml` – Android, Web, Windows, Linux, macOS + Dependabot + PR-Template
  - **CI/CD Pipeline Phase 3:** `release.yaml` – GitHub Releases, automatische Versionierung (SemVer), CHANGELOG-Generierung
  - **CI/CD Pipeline Phase 4:** `security_scan.yaml` – CodeQL, OSS-Scanner, `dart pub audit`
  - **Unit-Tests:** `JobOffer`-Modell, `CircuitBreaker`, `ApiCacheService`