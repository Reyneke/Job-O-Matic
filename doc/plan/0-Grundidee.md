# Kernidee

Das Ziel dieses Projektes ist es, eine produktionsfähige App zu entwickeln, welche aus vorhandenen Daten eine vollständige, auf eine Stelle zugeschnittene Bewerbung erstellt – inklusive:

- **Deckblatt**
- **Anschreiben**
- **Lebenslauf**

Die App soll modular aufgebaut und für spätere Erweiterungen bequem erweiterbar sein. Ebenfalls wird das Projekt dokumentiert.

---

## Stelleneingabe

Die Eingabe der Stellenangebote erfolgt durch Angabe einer URL in einem Textfeld. Jenes Feld soll die Eingabe **mehrerer** Stellenangebote gleichzeitig ermöglichen, um mehrere Bewerbungen auf einmal verfassen zu können.

---

## Daten

Die Bewerbungsdaten (z. B. persönliche Informationen, beruflicher Werdegang, Qualifikationen) liegen unter `assets/mydata/cv` und müssen eingelesen und in ein sauberes, strukturiertes Format gebracht werden.

---

## Vorlagen

Eine Formatvorlage für das Layout der Bewerbung liegt im Ordner `assets/mydata/vorlagen`. Diese Vorlage bestimmt das optische Erscheinungsbild der generierten Dokumente.

---

## Technologie

| Bereich        | Technologie / Vorgabe                       |
|----------------|---------------------------------------------|
| Sprache        | **Flutter / Dart**                          |
| AppTheme       | nach Projekterstellung aus `assets/theme` ins Projekt kopieren und einbinden |
| Architektur    | (noch festzulegen, z. B. BLoC / Riverpod / Provider) |
| Ausgabeformat  | PDF                                         |

---

## Nächste Schritte

### Phase 0: Projekt-Grundlage
- [ ] **Flutter-Projekt anlegen** (`flutter create --org de.matth.jobomatic job_o_matic`)
- [ ] **State-Management festlegen** – Architektur-Entscheidung treffen (Empfehlung: **Riverpod** wegen Testbarkeit und Skalierbarkeit)
- [ ] **Ordnerstruktur etablieren** (z. B. `lib/` mit `core/`, `features/`, `data/`, `presentation/`)
- [ ] **Abhängigkeiten definieren** – `pubspec.yaml` mit relevanten Paketen vorbereiten (pdf_generator, http, riverpod, freezed, etc.)

### Phase 1: Theme & Design-System
- [ ] **AppTheme aus `assets/theme` übernehmen** – Farben, Typografie, Abstände als `ThemeData` konfigurieren
- [ ] **Design-Tokens definieren** – Konstanten für Abstände, Rundungen, Schattierungen in einem zentralen `AppConstants`-Objekt bündeln
- [ ] **Dark-Mode-Unterstützung** – Theme-Datei bereits auf Hell/Dunkel auslegen

### Phase 2: Daten-Import & Validierung
- [ ] **Datenmodell entwerfen** – Klassen für `PersonalData`, `WorkExperience`, `Education`, `Skill` mit `freezed` + `json_serializable`
- [ ] **CV-Daten aus `assets/mydata/cv` einlesen** – Parser-Klasse, die JSON/YAML-Dateien lädt und in die Modelle deserialisiert
- [ ] **Validierung implementieren** – Pflichtfelder prüfen, Datumslogik validieren (keine Enddaten vor Startdaten), ggf. fehlende Felder melden
- [ ] **Fehlerbehandlung** – Defensive Programmierung: fehlende/fehlerhafte Dateien führen nicht zum Absturz, sondern zu aussagekräftigen Fehlermeldungen
- [ ] **Unit-Tests für Parser & Validierung** – Grenzfälle wie leere Daten, Sonderzeichen, fehlende Felder abdecken

### Phase 3: Vorlagen-System
- [ ] **Vorlagen aus `assets/mydata/vorlagen` laden** – Template-Engine (z. B. `mustache_template` oder Eigenbau) einbinden
- [ ] **Platzhalter-Variablen definieren** – Einheitliches Schema wie `{{name}}`, `{{position}}`, `{{skills}}` dokumentieren
- [ ] **Default-Vorlage bereitstellen** – Fallback für den Fall, dass keine benutzerdefinierte Vorlage existiert

### Phase 4: Dokumenten-Generierung
- [ ] **Deckblatt-Generator** – Position, Firmenlogo-Platzhalter, Datum aus dem Anschreiben-Kontext
- [ ] **Anschreiben-Generator** – Personalisierung pro Stelle (Anrede, Qualifikationen, Motivation)
- [ ] **Lebenslauf-Generator** – Chronologische/ tabellarische Darstellung der CV-Daten
- [ ] **PDF-Export** – `pdf`-Paket oder `printing` + natives Drucken
- [ ] **Integration: URL-Parsing → Datenabgleich → Generierung** – Zusammenspiel der Module in einem `GenerateUseCase` orchestrieren

### Phase 5: Qualitätssicherung
- [ ] **Widget-Tests** für UI-Komponenten (z. B. Texteingabefeld für Stellen-URL)
- [ ] **Integrationstests** für den gesamten Generierungs-Workflow
- [ ] **Dokumentation** in `/doc` vervollständigen (Architektur-Entscheidungen, Datenformat-Spezifikation, Benutzerhandbuch)
- [ ] **CI/CD-Pipeline** (GitHub Actions: `analyze`, `test`, `build apk`)

### Hinweise zur Reihenfolge
- **Phase 0** und **Phase 1** können parallel starten.
- **Phase 2** und **Phase 3** sind unabhängig voneinander und können parallel bearbeitet werden.
- **Phase 4** baut auf den Ergebnissen der Phasen 2 und 3 auf.
- **Phase 5** sollte begleitend ab Phase 2 beginnen, nicht erst am Ende.
