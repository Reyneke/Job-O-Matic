# Fazit

> **Zusammenfassung der Projektdokumentation**  
> Dieses Dokument fasst die wesentlichen Erkenntnisse aus allen Planungsdokumenten sowie dem aktuellen Projektstand zusammen und bietet eine konsolidierte Übersicht über offene Fragen und den Arbeitsplan.

---

## Übersicht der Planungsdokumente

| # | Dokument | Schwerpunkt | Status |
|---|----------|-------------|--------|
| 0 | [Grundidee](./0-Grundidee.md) | Projektvision und Zielsetzung | ✅ |
| 1 | [App-Basis](./1-AppBasis.md) | Grundlegende App-Struktur | ✅ |
| 2 | [Workflow](./2-Workflow.md) | Bewerbungs-Workflow | ✅ |
| 3 | [Automailer](./3-automailer.md) | Automatisierter E-Mail-Versand | ✅ |
| 4 | [PDF-Generierung](./4-PDF-Generierung.md) | PDF-Erstellung für Dokumente | ✅ |
| 5 | [API-Anbindung](./5-API-Anbindung.md) | Externe API-Integration | ✅ |
| 6 | [Datenbank-Persistenz](./6-Datenbank-Persistenz.md) | Datenspeicherung | ✅ |
| 7 | [CI/CD Pipeline](./7-CI:CD%20Pipleine.md) | Continuous Integration & Deployment | ✅ |

---

## Offene Fragen

_Alle noch zu klärenden Fragen aus den Einzeldokumenten, inklusive Priorität und Status:_

| # | Frage | Betroffenes Dokument | Priorität | Status |
|---|-------|---------------------|-----------|--------|
| 1 | **Architektur (State-Management):** Riverpod wurde in der Umsetzung gewählt – ist die finale Entscheidung dokumentiert und begründet? | `0-Grundidee.md` | 🟢 Niedrig | ✅ Geklärt (Riverpod) |
| 2 | **Portal-Unterstützung priorisieren:** Welche Portale außer Jobcenter sollen unterstützt werden? Qualität der Portal-APIs prüfen. | `3-automailer.md` | 🟡 Mittel | 🔄 Offen |
| 3 | **Rechtliche Prüfung der Portal-Automation:** Ist automatisierte Portal-Eingabe mit den AGB der Portale vereinbar? Anwalt für IT-Recht einschalten. | `3-automailer.md` | 🔴 Hoch | 🔄 Offen |
| 4 | **Mehrere E-Mail-Profile:** Sollen private Bewerbungen vs. Bewerbungen über Agentur getrennte Profile erhalten? (Auf spätere Iteration verschoben) | `3-automailer.md` | 🟢 Niedrig | ⏳ Verschoben |
| 5 | **Web-Kompatibilität der Datenbank:** `sqflite_common_ffi_web` ist noch experimentell. Alternativ `drift` mit WebSQL-Fallback? | `6-Datenbank-Persistenz.md` | 🟡 Mittel | 🔄 Offen |
| 6 | **Verschlüsselung der gesamten DB:** Soll `sqlcipher` für sensible Bewerbungsdaten verwendet werden? | `6-Datenbank-Persistenz.md` | 🟢 Niedrig | 🔄 Offen |
| 7 | **Backup/Export der DB:** Soll der Nutzer Daten (Applications, CV) als JSON exportieren können? | `6-Datenbank-Persistenz.md` | 🟢 Niedrig | 🔄 Offen |
| 8 | **Auto-Delete alter Einträge:** Alte Bewerbungen (> 6 Monate) automatisch bereinigen? (Speicherplatz-Optimierung) | `6-Datenbank-Persistenz.md` | 🟢 Niedrig | 🔄 Offen |
| 9 | **Sync mit Cloud:** Soll die DB später mit einem Cloud-Backend synchronisiert werden? (Beeinflusst Schema-Design) | `6-Datenbank-Persistenz.md` | 🟢 Niedrig | 🔄 Offen |
| 10 | **iOS-Builds:** Apple Developer-Account erforderlich ($99/Jahr). Wie gehen wir mit Code-Signing um? (Manuell vs. CI) | `7-CI/CD Pipeline.md` | 🟡 Mittel | 🔄 Offen |
| 11 | **Store-Deployment:** Soll die Pipeline automatisch in Google Play Store / Apple App Store / Microsoft Store veröffentlichen? | `7-CI/CD Pipeline.md` | 🟡 Mittel | 🔄 Offen |
| 12 | **Web-Hosting:** GitHub Pages vs. professionelleres Hosting (Netlify, Firebase Hosting, Vercel)? | `7-CI/CD Pipeline.md` | 🟡 Mittel | 🔄 Offen |
| 13 | **Code-Signing für Desktop:** Windows: SignTool-Zertifikat (~200 €/Jahr). macOS: Notarization. Linux: AppImage/Snap? | `7-CI/CD Pipeline.md` | 🟢 Niedrig | 🔄 Offen |
| 14 | **Test-Devices:** Werden echte Geräte/Emulatoren für Integrationstests benötigt? (Firebase Test Lab, BrowserStack) | `7-CI/CD Pipeline.md` | 🟢 Niedrig | 🔄 Offen |
| 15 | **CHANGELOG.md:** Release-Notes-Datei muss noch erstellt und gepflegt werden. | `7-CI/CD Pipeline.md` | 🟡 Mittel | 🔄 Offen |
| 16 | **Code-Coverage-Threshold:** Ab welchem Wert soll die Pipeline fehlschlagen? (Vorschlag: 60 % Phase 1, 80 % Produktion) | `7-CI/CD Pipeline.md` | 🟢 Niedrig | 🔄 Offen |

**Legende:**  
- 🔴 Hoch – muss vor nächstem Release geklärt werden  
- 🟡 Mittel – sollte zeitnah geklärt werden  
- 🟢 Niedrig – kann später behandelt werden  
- ✅ Geklärt / ❌ Abgelehnt / 🔄 Offen / ⏳ Verschoben

---

## Arbeitsplan (mit Prioritäten & Deadlines)

_Die Aufgaben aus allen Dokumenten wurden konsolidiert, nach Priorität geordnet und mit geschätztem Aufwand/Deadline versehen._

**Prioritäts-Legende:**  
🔴 **Kritisch (Sprint 1)** – Muss sofort umgesetzt werden, Blockiert andere Aufgaben  
🟡 **Wichtig (Sprint 2)** – Sollte zeitnah umgesetzt werden  
🟢 **Nice-to-have (Sprint 3+)** – Kann später folgen

---

### 🔴 Sprint 1: Projekt-Grundlage & Datenimport (KW 31–32 · 29.07.–09.08.2026)

| Deadline | Priority | Aufgabe | Dokumentation | Abhängigkeiten |
|----------|----------|---------|---------------|----------------|
| KW 31 | 🔴 | Flutter-Projekt-Setup (`flutter create`, Ordnerstruktur, `pubspec.yaml`-Abhängigkeiten) | `0-Grundidee.md` Phase 0 | — |
| KW 31 | 🔴 | State-Management-Festlegung (Riverpod) + Provider-Grundstruktur | `0-Grundidee.md` Phase 0 | — |
| KW 31 | 🔴 | Theme übernehmen (`assets/theme` → `ThemeData`, Design-Tokens, Dark-Mode) | `0-Grundidee.md` Phase 1 | — |
| KW 31 | 🔴 | Dépendances installieren (`flutter pub get`) | `2-Workflow.md` Schritt 1 | — |
| KW 31–32 | 🔴 | Datenmodelle definieren (`PersonalData`, `WorkExperience`, `Education`, `Skill`, `Application`, `JobOffer`, `CvData`) | `0-Grundidee.md` Phase 2, `5-API-Anbindung.md` §2.4 | — |
| KW 32 | 🔴 | CV-Daten aus `assets/mydata/cv` einlesen + Parser + Validierung | `0-Grundidee.md` Phase 2, `2-Workflow.md` §1 | Datenmodelle |
| KW 32 | 🔴 | Routing mit `go_router` aufsetzen (Routen-Tabelle, Redirect-Guards, Navigationsdiagramm) | `1-AppBasis.md` Navigation, `2-Workflow.md` Schritt 2 | — |
| KW 32 | 🔴 | Logsystem implementieren (zentraler Logger, Log-Level, Output-Handler, Datei-Rotation) | `2-Workflow.md` §6 | — |

### 🟡 Sprint 2: Kernfunktionen (KW 32–34 · 09.08.–22.08.2026)

| Deadline | Priority | Aufgabe | Dokumentation | Abhängigkeiten |
|----------|----------|---------|---------------|----------------|
| KW 32 | 🟡 | UI-Screen 1: Stelleneingabe (Textarea, Live-Validierung, Autosave) | `1-AppBasis.md` Stelleneingabe | Routing, Logsystem |
| KW 32 | 🟡 | UI-Screen 2: Jobsuche (Suchmaske, Filter, Ergebnisliste, Fuzzy-Ranking) | `1-AppBasis.md` Jobsuche | Routing, Datenmodelle |
| KW 32–33 | 🟡 | UI-Screen 3: Ergebnisübersicht (Statusliste, Fortschritt, Batch-Export) | `1-AppBasis.md` Ergebnisübersicht | Routing |
| KW 33 | 🟡 | UI-Screen 3a: Detailansicht (PDF-Vorschau, Download, Metadaten) | `1-AppBasis.md` Detailansicht | Routing |
| KW 33 | 🟡 | **Datenbank-Persistenz Phase A:** `sqflite` einrichten, `DatabaseHelper` (Singleton, Schema, Migrationen) | `6-Datenbank-Persistenz.md` Phase A | Modelle |
| KW 33 | 🟡 | **Datenbank-Persistenz Phase B:** `DatabaseRepository` CRUD (applications, validated_urls, search_filters, cv_data) inkl. Dublettenprüfung | `6-Datenbank-Persistenz.md` Phase B | DB-Grundlage |
| KW 33–34 | 🟡 | **Datenbank-Persistenz Phase C:** `JobRepository` von In-Memory auf DB migrieren (initialize, async-Methoden, Provider-Umstellung) | `6-Datenbank-Persistenz.md` Phase C | DatabaseRepository |
| KW 33 | 🟡 | **API-Anbindung Phase 1:** `ApiClient` (HTTP-Client mit Retry, Timeout, Logging) + `JobOffer`-Modell | `5-API-Anbindung.md` Phase 1 | Logsystem |
| KW 33–34 | 🟡 | **API-Anbindung Phase 2:** BA-JOBBÖRSE-API (`BaApiService`), API-Key-Management (`flutter_secure_storage`) | `5-API-Anbindung.md` Phase 2 | ApiClient |
| KW 34 | 🟡 | **PDF-Generierung Phase A (1–6):** PdfUtils, TemplateLoader, TemplateRenderer, CoverPageGenerator, CvGenerator, CoverLetterGenerator | `4-PDF-Generierung.md` Phase A (1–6) | Modelle, Vorlagen |
| KW 34 | 🟡 | **PDF-Generierung Phase A (7–11):** PdfGenerator-Orchestrierung, Riverpod-Provider, `JobRepository.generatePdf()`, UI-Integration, Tests | `4-PDF-Generierung.md` Phase A (7–11) | PDF-Generierung (1–6) |
| KW 34 | 🟡 | Vorlagen-System (Template-Engine, Platzhalter `{{variable}}`, Default-Vorlage) | `0-Grundidee.md` Phase 3, `4-PDF-Generierung.md` §3.5 | Datenmodelle |

### 🟢 Sprint 3: Infrastruktur & Integration (KW 34–36 · 22.08.–05.09.2026)

| Deadline | Priority | Aufgabe | Dokumentation | Abhängigkeiten |
|----------|----------|---------|---------------|----------------|
| KW 34 | 🟢 | **Automailer Phase 1:** Brevo-Account + API-Key + Secrets-Manager | `3-automailer.md` §1 | ApiClient |
| KW 34–35 | 🟢 | **Automailer Phase 2:** E-Mail-Vorlagen (Handlebars/Mustache), Queue-System, Rate-Limiter | `3-automailer.md` §1, §4 | Automailer Phase 1 |
| KW 35 | 🟢 | **Automailer Phase 3:** Versand-Logik (pending→sending→sent/failed), Retry (Backoff), Circuit Breaker, Deliverability (DKIM/SPF) | `3-automailer.md` §1, §4, §5 | Automailer Phase 2 |
| KW 35 | 🟢 | **API-Anbindung Phase 3:** Adzuna-API + Caching-Strategie (30 Min) | `5-API-Anbindung.md` Phase 3 | ApiClient |
| KW 35 | 🟢 | **API-Anbindung Phase 4:** `JobScraperService` (HTML-Parsing, Portal-Selector-Konfiguration, CAPTCHA-Erkennung) | `5-API-Anbindung.md` Phase 4 | ApiClient |
| KW 35 | 🟢 | **Datenbank-Persistenz Phase D:** `ApiKeyService` (flutter_secure_storage), `AutosaveService` (5s-Debounce) in `JobInputScreen` integrieren | `6-Datenbank-Persistenz.md` Phase D | DatabaseRepository |
| KW 35 | 🟢 | Datenbereinigung (PDF-Cleanup beim App-Start, verwaiste Dateien entfernen) | `2-Workflow.md` §5 | PDF-Generierung |

### 🟢 Sprint 4: Qualitätssicherung & CI/CD (KW 36–38 · 05.09.–19.09.2026)

| Deadline | Priority | Aufgabe | Dokumentation | Abhängigkeiten |
|----------|----------|---------|---------------|----------------|
| KW 36 | 🟢 | Unit-Tests für Datenmodelle, Parser, Template-Renderer, PDF-Generatoren | Alle Dokumente (Testpläne) | Phase 1–2 |
| KW 36 | 🟢 | Widget-Tests für alle UI-Screens (Stelleneingabe, Jobsuche, Ergebnisübersicht, Detailansicht) | `0-Grundidee.md` Phase 5 | UI-Screens |
| KW 36 | 🟢 | Integrationstests: Vollständiger Generierungs-Workflow (URL → PDF), API-Mocking | `4-PDF-Generierung.md` §8.2, `6-Datenbank-Persistenz.md` §10.2 | PDF, DB, API |
| KW 36–37 | 🟢 | **CI/CD Phase 1:** `quality_check.yaml` (analyze + test) + `build_all.yaml` (Android + Web) | `7-CI/CD Pipeline.md` Phase 1 | Tests |
| KW 37 | 🟢 | **CI/CD Phase 2:** `build_all.yaml` für alle Plattformen + Dependabot + PR-Template | `7-CI/CD Pipeline.md` Phase 2 | CI/CD Phase 1 |
| KW 37–38 | 🟢 | **CI/CD Phase 3:** `release.yaml` + GitHub Releases + autom. Versionierung (SemVer) | `7-CI/CD Pipeline.md` Phase 3 | CI/CD Phase 2 |
| KW 38 | 🟢 | **CI/CD Phase 4:** Security-Scans (`dart pub audit`, osv-scanner), optional SonarCloud, Slack-Benachrichtigungen | `7-CI/CD Pipeline.md` Phase 4 | CI/CD Phase 3 |
| KW 38 | 🟢 | Dokumentation finalisieren (README, Architektur-Doku, Benutzerhandbuch, CHANGELOG) | `0-Grundidee.md` Phase 5, Alle | Alle |

### 📋 Backlog (Nach Phase 4 · ab KW 39)

| Deadline | Priority | Aufgabe | Dokumentation | Abhängigkeiten |
|----------|----------|---------|---------------|----------------|
| Offen | 🟢 | **Portal-Automation:** Browser-Extension (Phase 2) + Playwright-Skripte (Phase 3) – *nach rechtlicher Prüfung* | `3-automailer.md` §2 | Automailer, Rechtl. Prüfung |
| Offen | 🟢 | PDF-Verschlüsselung (Passwortschutz) | `4-PDF-Generierung.md` Phase B Schritt 18 | PDF-Generierung |
| Offen | 🟢 | PDF teilen (`share_plus`) | `4-PDF-Generierung.md` Phase B Schritt 12 | PDF-Generierung |
| Offen | 🟢 | Drucken (native Druck-API via `printing`) | `4-PDF-Generierung.md` Phase B Schritt 13 | PDF-Generierung |
| Offen | 🟢 | Layout-Konfiguration (YAML/JSON für Seiten-Layout aus Vorlagen) | `4-PDF-Generierung.md` Phase B Schritt 15 | PDF-Generierung |
| Offen | 🟢 | Profilfoto im Lebenslauf | `4-PDF-Generierung.md` Phase B Schritt 16 | PDF-Generierung, CV-Daten |
| Offen | 🟢 | Batch-Generierung (mehrere PDFs parallel) | `4-PDF-Generierung.md` Phase B Schritt 17 | PDF-Generierung |
| Offen | 🟢 | Store-Deployment (Google Play, App Store, Microsoft Store automatisieren) | `7-CI/CD Pipeline.md` §12 | CI/CD Phase 3 |
| Offen | 🟢 | Cloud-Sync der Datenbank | `6-Datenbank-Persistenz.md` Offene Fragen | DB-Persistenz |
| Offen | 🟢 | Backup/Export der DB als JSON | `6-Datenbank-Persistenz.md` Offene Fragen | DB-Persistenz |

---

## Nächste Schritte

1. ✅ Offene Fragen aus den Einzeldokumenten gesammelt und in die Tabelle oben eingetragen
2. ✅ Arbeitsplan-Items nach Priorität sortiert und mit Deadlines (KW) versehen
3. ❌ Status der einzelnen Phasen regelmäßig aktualisieren – *bei jedem Meilenstein*  
4. ❌ Dieses Fazit-Dokument bei jedem Meilenstein aktualisieren  
5. ❌ Offene Fragen klären (insbesondere 🔴 Rechtliche Prüfung Portal-Automation) – *vor Sprint 3*
6. ❌ Abhängigkeiten zwischen Sprints prüfen – *vor jedem Sprint-Start*

---

_Stand: 22.07.2026_  
_Dieses Dokument wird bei Projektfortschritt aktualisiert._
