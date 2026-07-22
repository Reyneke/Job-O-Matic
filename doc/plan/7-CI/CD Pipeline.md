# CI/CD Pipeline

Bevor wir zur großen Zusammenfassung kommen, dokumentiert dieser Abschnitt die Continuous-Integration- und Continuous-Delivery-Strategie für das Job-O-Matic-Projekt. Ziel ist es, eine automatisierte Pipeline zu etablieren, die **Code-Qualität sicherstellt**, **Builds automatisiert** und **Auslieferungen vereinfacht** – im Rückblick auf die gesamte bisherige Dokumentation und alle noch offenen Fragen.

---

## 1. Zielsetzung

| Ziel | Beschreibung |
|------|-------------|
| **Automatisierte Qualitätssicherung** | Jeder Commit/PR wird automatisch auf Lint-Regeln, Typenkorrektheit und Tests geprüft |
| **Plattformübergreifende Builds** | Automatische Kompilierung für Android, iOS, Web, Windows, macOS und Linux |
| **Frühe Fehlererkennung** | Laufende Analyse (static analysis, dependency vulnerabilities) vor dem Merge |
| **Reproduzierbare Release-Prozesse** | Versionierte Builds mit konsistenten Umgebungen |
| **Automatisierte Auslieferung** | Deployment zu Stores (Google Play, Microsoft Store, Web-Hosting) oder Bereitstellung als Download-Artefakt |

---

## 2. Technologie-Stack

| Komponente | Technologie |
|------------|-------------|
| **CI-Plattform** | GitHub Actions (da Repository auf GitHub) |
| **Build-System** | Flutter SDK (per `flutter build`) + Dart SDK |
| **Code-Qualität** | `dart analyze` (static analysis), `dart format --dry-run` (Formatierung), `custom_lint` (optionale Regeln) |
| **Tests** | `flutter test` (Unit + Widget-Tests), `flutter test --coverage` (Code Coverage) |
| **Plattform-spezifische Builds** | `flutter build apk` / `appbundle` (Android), `flutter build ios` (iOS), `flutter build web` (Web), `flutter build windows` / `macos` / `linux` (Desktop) |
| **Code-Signing** | Android: Keystore in GitHub Secrets; iOS: Apple Developer Profile; Windows: SignTool |
| **Release-Management** | GitHub Releases + `git tag` für Semantic Versioning |
| **Benachrichtigungen** | GitHub Commit-Status, optional Slack/E-Mail via GitHub Actions |

---

## 3. Pipeline-Architektur

Die CI/CD-Pipeline ist in **drei Workflows** unterteilt, die bei unterschiedlichen Ereignissen ausgelöst werden:

```mermaid
flowchart LR
    subgraph "Events"
        A[Push auf feature/*]
        B[Push auf main]
        C[Pull Request]
        D[Tag (v*.*.*)]
    end

    subgraph "CI Workflows"
        E[CI – Quality Check\n(analyze + test)]
        F[CI – Build & Artifact\n(package per platform)]
        G[CD – Deploy & Release\n(sign, publish, release)]
    end

    A --> E
    B --> E
    B --> F
    C --> E
    D --> G
    F --> G
```

### Workflow-Trigger

| Workflow | Trigger | Dauer (ca.) |
|----------|---------|-------------|
| **quality_check.yaml** | Push auf `feature/*` oder `main`, PR gegen `main` | 2–5 Min |
| **build_all.yaml** | Push auf `main` (nach Quality-Check), manuell (`workflow_dispatch`) | 5–20 Min (plattformabhängig) |
| **release.yaml** | Tag `v*.*.*` (z. B. `v1.2.3`), manuell | 10–30 Min |

---

## 4. Workflow: `quality_check.yaml` (Code-Qualität)

Dieser Workflow läuft bei **jedem Push und jedem PR** und stellt sicher, dass der Code sauber ist.

```yaml
# .github/workflows/quality_check.yaml
name: Quality Check

on:
  push:
    branches: [main, 'feature/**', 'fix/**']
  pull_request:
    branches: [main]

jobs:
  analyze:
    name: Dart Analyze
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.x

      - name: Install dependencies
        run: |
          cd job_o_matic
          flutter pub get

      - name: Dart Format Check
        run: |
          cd job_o_matic
          dart format --dry-run --set-exit-if-changed lib/ test/

      - name: Static Analysis
        run: |
          cd job_o_matic
          flutter analyze
        env:
          FLUTTER_ANALYZE_STRICT: true

  test:
    name: Flutter Tests
    needs: analyze
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.x

      - name: Install dependencies
        run: |
          cd job_o_matic
          flutter pub get

      - name: Run Tests
        run: |
          cd job_o_matic
          flutter test --coverage --reporter=expanded

      - name: Upload Coverage Report
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: job_o_matic/coverage/

      - name: Check Coverage Threshold
        run: |
          cd job_o_matic
          # Optionale Coverage-Prüfung (z. B. mindestens 60%)
          # genhtml coverage/lcov.info -o coverage/html
          echo "Coverage report generated"
```

### Was wird geprüft?

| Prüfung | Befehl | Abbruch bei Fehler? |
|---------|--------|---------------------|
| **Dart-Formatierung** | `dart format --dry-run --set-exit-if-changed` | ✅ Ja |
| **Static Analysis** | `flutter analyze` | ✅ Ja (alle warnings + errors) |
| **Unit-/Widget-Tests** | `flutter test` | ✅ Ja |
| **Code Coverage** | `flutter test --coverage` | ⚠️ Nein (nur Report, kein harter Threshold) |

---

## 5. Workflow: `build_all.yaml` (Plattform-Builds)

Dieser Workflow erzeugt **installierbare Artefakte** für alle relevanten Plattformen. Er läuft nach einem erfolgreichen Quality-Check auf `main`.

```yaml
# .github/workflows/build_all.yaml
name: Build All Platforms

on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      platform:
        description: 'Platform to build (all/android/ios/web/windows/macos/linux)'
        required: false
        default: 'all'

jobs:
  build-android:
    name: Build Android
    runs-on: ubuntu-latest
    if: inputs.platform == 'all' || inputs.platform == 'android'
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.x

      - name: Install dependencies
        run: |
          cd job_o_matic
          flutter pub get

      - name: Build APK
        run: |
          cd job_o_matic
          flutter build apk --release
        env:
          # Keystore aus GitHub Secrets (optional)
          # ANDROID_KEYSTORE: ${{ secrets.ANDROID_KEYSTORE }}
          # ANDROID_KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          # ANDROID_KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
          # ANDROID_KEY_PASSWORD: ${{ secrets.ANDROID_KEY_PASSWORD }}

      - name: Build AppBundle
        run: |
          cd job_o_matic
          flutter build appbundle --release

      - name: Upload APK Artifact
        uses: actions/upload-artifact@v4
        with:
          name: android-apk
          path: job_o_matic/build/app/outputs/flutter-apk/*.apk

      - name: Upload AppBundle Artifact
        uses: actions/upload-artifact@v4
        with:
          name: android-aab
          path: job_o_matic/build/app/outputs/bundle/release/*.aab

  build-web:
    name: Build Web
    runs-on: ubuntu-latest
    if: inputs.platform == 'all' || inputs.platform == 'web'
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.x

      - name: Install dependencies
        run: |
          cd job_o_matic
          flutter pub get

      - name: Build Web (Release)
        run: |
          cd job_o_matic
          flutter build web --release --base-href=/Job-O-Matic/

      - name: Upload Web Artifact
        uses: actions/upload-artifact@v4
        with:
          name: web-build
          path: job_o_matic/build/web/

      - name: Deploy to GitHub Pages
        uses: peaceiris/actions-gh-pages@v3
        if: github.ref == 'refs/heads/main'
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: job_o_matic/build/web
          publish_branch: gh-pages

  build-windows:
    name: Build Windows
    runs-on: windows-latest
    if: inputs.platform == 'all' || inputs.platform == 'windows'
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.x

      - name: Install dependencies
        run: |
          cd job_o_matic
          flutter pub get

      - name: Build Windows (Release)
        run: |
          cd job_o_matic
          flutter build windows --release

      - name: Upload Windows Artifact
        uses: actions/upload-artifact@v4
        with:
          name: windows-build
          path: job_o_matic/build/windows/runner/Release/

  build-macos:
    name: Build macOS
    runs-on: macos-latest
    if: inputs.platform == 'all' || inputs.platform == 'macos'
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.x

      - name: Install dependencies
        run: |
          cd job_o_matic
          flutter pub get

      - name: Build macOS (Release)
        run: |
          cd job_o_matic
          flutter build macos --release

      - name: Upload macOS Artifact
        uses: actions/upload-artifact@v4
        with:
          name: macos-build
          path: job_o_matic/build/macos/Build/Products/Release/

  build-linux:
    name: Build Linux
    runs-on: ubuntu-latest
    if: inputs.platform == 'all' || inputs.platform == 'linux'
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.x

      - name: Install dependencies
        run: |
          cd job_o_matic
          flutter pub get

      - name: Build Linux (Release)
        run: |
          cd job_o_matic
          flutter build linux --release

      - name: Upload Linux Artifact
        uses: actions/upload-artifact@v4
        with:
          name: linux-build
          path: job_o_matic/build/linux/x64/release/bundle/
```

### Plattform-Matrix

| Plattform | Runner | Voraussetzungen | Build-Dauer (ca.) |
|-----------|--------|----------------|-------------------|
| **Android (APK + AAB)** | `ubuntu-latest` | JDK (im Runner enthalten) | 5–8 Min |
| **Web** | `ubuntu-latest` | Keine | 3–5 Min |
| **Windows** | `windows-latest` | Visual Studio Build Tools | 8–15 Min |
| **macOS** | `macos-latest` | Xcode (im Runner enthalten) | 10–20 Min |
| **Linux** | `ubuntu-latest` | `clang`, `cmake`, `ninja-build`, `libgtk-3-dev` | 5–10 Min |

### System-Abhängigkeiten für Linux-Builds

```yaml
# Vor dem Linux-Build (in build-linux-Schritt ergänzen)
- name: Install Linux Dependencies
  run: |
    sudo apt-get update
    sudo apt-get install -y clang cmake ninja-build libgtk-3-dev liblzma-dev libstdc++-12-dev
```

---

## 6. Workflow: `release.yaml` (Veröffentlichung & Deployment)

Wird durch **Git-Tags** ausgelöst (Semantic Versioning: `v1.2.3`) oder manuell gestartet. Erstellt ein **GitHub Release** mit allen Build-Artefakten.

```yaml
# .github/workflows/release.yaml
name: Create Release

on:
  push:
    tags:
      - 'v*.*.*'
  workflow_dispatch:
    inputs:
      version:
        description: 'Release version (e.g., 1.2.3)'
        required: true
        type: string

jobs:
  extract-version:
    name: Extract Version
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.version.outputs.version }}
      tag: ${{ steps.version.outputs.tag }}
    steps:
      - id: version
        run: |
          if [[ "${{ github.event_name }}" == "workflow_dispatch" ]]; then
            echo "version=${{ inputs.version }}" >> $GITHUB_OUTPUT
            echo "tag=v${{ inputs.version }}" >> $GITHUB_OUTPUT
          else
            echo "version=${GITHUB_REF_NAME#v}" >> $GITHUB_OUTPUT
            echo "tag=$GITHUB_REF_NAME" >> $GITHUB_OUTPUT
          fi

  quality-gate:
    name: Quality Gate
    needs: extract-version
    uses: ./.github/workflows/quality_check.yaml
    secrets: inherit

  build-all:
    name: Build All Platforms
    needs: quality-gate
    uses: ./.github/workflows/build_all.yaml
    secrets: inherit
    with:
      platform: all

  create-release:
    name: Create GitHub Release
    needs: [extract-version, build-all]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Download all artifacts
        uses: actions/download-artifact@v4
        with:
          path: artifacts/

      - name: Generate Release Notes
        id: release_notes
        run: |
          # Extrahiert Einträge aus CHANGELOG.md für diese Version (CHANGELOG.md muss noch erstellt werden)
          # Fallback: git log
          echo "## Changelog" > release_notes.md
          git log --pretty=format:"* %s (%h)" $(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)..HEAD >> release_notes.md
          echo "release_notes_content=$(cat release_notes.md)" >> $GITHUB_OUTPUT

      - name: Create Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ needs.extract-version.outputs.tag }}
          name: "Job-O-Matic v${{ needs.extract-version.outputs.version }}"
          body_path: release_notes.md
          draft: true
          prerelease: false
          files: |
            artifacts/android-apk/*.apk
            artifacts/android-aab/*.aab
            artifacts/web-build/**
            artifacts/windows-build/**
            artifacts/macos-build/**
            artifacts/linux-build/**
```

---

## 7. Zusätzliche Qualitätsmaßnahmen

### 7.1 Dependency-Scanning (Sicherheit)

Ein separater Workflow zur Erkennung von Sicherheitslücken in Abhängigkeiten:

```yaml
# .github/workflows/security_scan.yaml
name: Security Scan

on:
  schedule:
    - cron: '0 6 * * 1' # Jeden Montag um 6:00 UTC
  push:
    branches: [main]
    paths:
      - 'job_o_matic/pubspec.yaml'
      - 'job_o_matic/pubspec.lock'

jobs:
  dependency-check:
    name: Dependency Vulnerability Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.x

      - name: List outdated dependencies
        run: |
          cd job_o_matic
          flutter pub outdated

      - name: Run dart pub audit
        run: |
          cd job_o_matic
          dart pub audit

      - name: Check for known vulnerabilities (osv-scanner)
        uses: google/osv-scanner/actions/scanner@v1
        with:
          scan-args: "--recursive job_o_matic/"
```

### 7.2 Code-Qualitäts-Metriken (SonarCloud / Codacy)

Optional kann eine externe Qualitätsplattform angebunden werden:

```yaml
# (optional) SonarCloud-Integration
- name: SonarCloud Scan
  uses: SonarSource/sonarcloud-github-action@v2
  if: github.ref == 'refs/heads/main'
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
```

### 7.3 Automatisierte PR-Beschreibung

Ein PR-Template in `.github/pull_request_template.md` sorgt für konsistente Pull-Requests:

```markdown
## Beschreibung
<!-- Kurze Zusammenfassung der Änderungen -->

## Typ der Änderung
- [ ] Bugfix
- [ ] Neue Funktion
- [ ] Refactoring / Code-Qualität
- [ ] Dokumentation
- [ ] CI/CD / DevOps

## Checkliste
- [ ] Code wurde getestet (mindestens manuell)
- [ ] Tests wurden geschrieben/aktualisiert
- [ ] Dokumentation wurde aktualisiert (falls nötig)
- [ ] Keine neuen `flutter analyze`-Warnings

## Verknüpfte Issues
<!-- Closes #ISSUE_NUMBER -->
```

---

## 8. Versionierungsstrategie

### Semantic Versioning (SemVer)

| Komponente | Beschreibung | Beispiel |
|------------|-------------|----------|
| **MAJOR** | Inkompatible API-Änderungen | `2.0.0` |
| **MINOR** | Neue Funktionen (abwärtskompatibel) | `1.3.0` |
| **PATCH** | Bugfixes (abwärtskompatibel) | `1.0.1` |

### Version in `pubspec.yaml` aktualisieren

```bash
# Manuell oder via CI-Automation
# Version in pubspec.yaml auf neue Version setzen (z. B. 1.2.0)
# Commit + Tag
git add job_o_matic/pubspec.yaml
git commit -m "chore: bump version to 1.2.0"
git tag v1.2.0
git push origin main --tags
```

### Automatische Versionierung via CI (optional)

```yaml
# Workflow-Schritt: Version aus Tag extrahieren und in pubspec.yaml setzen
- name: Update pubspec version
  run: |
    VERSION="${{ needs.extract-version.outputs.version }}"
    sed -i "s/version: .*/version: $VERSION+1/" job_o_matic/pubspec.yaml
    git config user.name "GitHub Actions"
    git config user.email "actions@github.com"
    git add job_o_matic/pubspec.yaml
    git commit -m "chore: update version to $VERSION [skip ci]"
    git push
```

---

## 9. Notwendige Secrets & Konfiguration

Für den Produktivbetrieb der Pipeline müssen folgende Secrets in den **GitHub Repository Secrets** hinterlegt werden:

| Secret-Name | Verwendung | Erforderlich für |
|-------------|-----------|------------------|
| `ANDROID_KEYSTORE` | Base64-codierter Keystore für App-Signing | Android-Release |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore-Passwort | Android-Release |
| `ANDROID_KEY_ALIAS` | Key-Alias | Android-Release |
| `ANDROID_KEY_PASSWORD` | Key-Passwort | Android-Release |
| `APPLE_DEVELOPER_CERT` | Apple Developer-Zertifikat (Base64) | iOS-Release |
| `APPLE_PROFILE` | Provisioning Profile (Base64) | iOS-Release |
| `SONAR_TOKEN` | SonarCloud-Auth-Token | SonarCloud-Scan (optional) |
| `SLACK_WEBHOOK_URL` | Slack-Webhook für Benachrichtigungen | Slack-Integration (optional) |

---

## 10. Notwendige Dateien (Repository-Struktur)

Folgende Dateien müssen im Repository-Stammverzeichnis angelegt werden:

```
.github/
├── workflows/
│   ├── quality_check.yaml        # Code-Qualitäts-Prüfungen
│   ├── build_all.yaml            # Plattform-Builds
│   ├── release.yaml              # Release-Erstellung
│   └── security_scan.yaml        # Sicherheits-Scans (optional)
├── pull_request_template.md      # PR-Template
└── dependabot.yml                # Automatische Dependency-Updates (optional)
```

### Dependabot-Konfiguration (optional)

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "pub"
    directory: "/job_o_matic"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "08:00"
      timezone: "Europe/Berlin"
    open-pull-requests-limit: 10
    labels:
      - "dependencies"
      - "automerge"
```

---

## 11. Lokale CI-Simulation

Entwickler können die CI-Prüfungen auch **lokal** ausführen, bevor sie pushen:

```bash
# 1. Formatierung prüfen
dart format --dry-run --set-exit-if-changed job_o_matic/lib/ job_o_matic/test/

# 2. Static Analysis
cd job_o_matic && flutter analyze

# 3. Tests + Coverage
cd job_o_matic && flutter test --coverage

# 4. (Optional) Dependency-Check
cd job_o_matic && dart pub outdated
cd job_o_matic && dart pub audit
```

### Als NPM-Skript (für Konsistenz mit anderen Projekten)

```json
{
  "scripts": {
    "ci:format": "dart format --dry-run --set-exit-if-changed job_o_matic/lib/ job_o_matic/test/",
    "ci:analyze": "cd job_o_matic && flutter analyze",
    "ci:test": "cd job_o_matic && flutter test --coverage",
    "ci:audit": "cd job_o_matic && dart pub audit",
    "ci:all": "npm run ci:format && npm run ci:analyze && npm run ci:test && npm run ci:audit"
  }
}
```

---

## 12. Offene Fragen & Nächste Schritte

### Noch zu klären

- [ ] **iOS-Builds:** Apple Developer-Account erforderlich ($99/Jahr). Wie gehen wir mit Code-Signing um? (Manuell vs. CI)
- [ ] **Store-Deployment:** Soll die Pipeline automatisch in Google Play Store / Apple App Store / Microsoft Store veröffentlichen?
- [ ] **Web-Hosting:** GitHub Pages ist als einfache Lösung vorgesehen. Soll stattdessen ein professionelleres Hosting (Netlify, Firebase Hosting, Vercel) verwendet werden?
- [ ] **Code-Signing für Desktop:** Windows: SignTool-Zertifikat erforderlich (~200 €/Jahr). macOS: Notarization durch Apple. Linux: AppImage/Snap-Crafting?
- [ ] **Test-Devices:** Werden echte Geräte/Emulatoren für Integrationstests benötigt? (Firebase Test Lab für Android, BrowserStack für Web)
- [ ] **CHANGELOG.md:** Release-Notes aus CHANGELOG.md extrahieren → muss noch erstellt und gepflegt werden
- [ ] **Code-Coverage-Threshold:** Ab welchem Wert soll die Pipeline fehlschlagen? (Vorschlag: 60 % für Phase 1, 80 % für Produktion)

### Vorgeschlagene Umsetzung (Phasen)

| Phase | Inhalt | Aufwand |
|-------|--------|---------|
| **Phase 1 (Muss)** | `quality_check.yaml` + `build_all.yaml` (nur Android/Web) + lokale CI-Simulation | 1–2 Tage |
| **Phase 2 (Soll)** | `build_all.yaml` für alle Plattformen + `dependabot.yml` + PR-Template | 2–3 Tage |
| **Phase 3 (Kann)** | `release.yaml` + GitHub Releases + automatische Versionsverwaltung | 1–2 Tage |
| **Phase 4 (Optional)** | Store-Deployment + Security-Scans + SonarCloud + Benachrichtigungen | 3–5 Tage |

---

## 13. Integration mit der bestehenden Architektur

Die CI/CD-Pipeline ist eng mit den bisherigen Plan-Dokumenten verzahnt:

| Dokument | Integration in CI/CD |
|----------|---------------------|
| **`0-Grundidee.md`** (Phase 5) | CI/CD-Pipeline ist dort bereits als letzter Punkt der Qualitätssicherung aufgeführt |
| **`2-Workflow.md`** (Logging) | Das Logsystem (`debugPrint` in Entwicklung, Datei-Logging in Produktion) wird in der CI verwendet, um Build-Fehler zu diagnostizieren |
| **`4-PDF-Generierung.md`** | PDF-Tests (z. B. "generierte PDF beginnt mit `%PDF`") werden in `flutter test` integriert |
| **`5-API-Anbindung.md`** | Integrationstests gegen reale API-Endpunkte werden in der CI ausgeführt (mit Dummy-Keys aus GitHub Secrets) |
| **`6-Datenbank-Persistenz.md`** | Datenbank-Tests (`sqflite` in-memory) laufen im `flutter test`-Schritt; Schema-Migrationen werden in der CI validiert |
| **`doc/doc/0-Architecture.md`** | Die Architektur-Dokumentation beschreibt die Layer, die durch die CI-Qualitätsprüfungen geschützt werden |

### Pipeline-Integration in `doc/doc/README.md`

Die CI/CD-Dokumentation wird im README verlinkt:

```markdown
## CI/CD Status

[![Quality Check](https://github.com/Reyneke/Job-O-Matic/actions/workflows/quality_check.yaml/badge.svg)](https://github.com/Reyneke/Job-O-Matic/actions/workflows/quality_check.yaml)
[![Build All Platforms](https://github.com/Reyneke/Job-O-Matic/actions/workflows/build_all.yaml/badge.svg)](https://github.com/Reyneke/Job-O-Matic/actions/workflows/build_all.yaml)

Siehe [CI/CD Pipeline](../doc/plan/7-CI/CD%20Pipeline.md) für Details.
```

---

## 14. Zusammenfassung

Die CI/CD-Pipeline für Job-O-Matic setzt auf **GitHub Actions** als zentrale Automatisierungsplattform und deckt den gesamten Entwicklungs-Workflow ab:

1. **Lokale CI-Simulation** – Entwickler führen `dart format`, `flutter analyze`, `flutter test` und `dart pub audit` vor dem Push aus
2. **Automatisierte Qualitätssicherung** – Bei jedem Push/PR: Format-Check, Static Analysis, Tests, Coverage-Report
3. **Plattform-Builds** – Automatische Kompilierung für Android (APK + AAB), Web, Windows, macOS und Linux
4. **Release-Management** – Getaggte Versionen erzeugen GitHub Releases mit allen Build-Artefakten
5. **Sicherheits-Scans** – Wöchentliche Abhängigkeitsprüfung auf bekannte Schwachstellen
6. **Dependency-Updates** – Dependabot hält die Abhängigkeiten aktuell

Die Pipeline ist **modular aufgebaut** (separate Workflows für Qualität, Builds und Releases) und wird **phasenweise** eingeführt, beginnend mit den Qualitätsprüfungen und Android-/Web-Builds, bevor sie auf die restlichen Plattformen und Store-Deployments ausgeweitet wird.