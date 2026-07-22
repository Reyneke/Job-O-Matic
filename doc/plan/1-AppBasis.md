## Stelleneingabe

> **Zweck:** Ermöglicht dem Nutzer, Stellenangebote durch Angabe von URLs zu erfassen, um darauf basierend Bewerbungen automatisiert zu generieren.

### Funktionsweise

Die Eingabe der Stellenangebote erfolgt durch Angabe einer oder mehrerer URLs in einem dafür vorgesehenen Textfeld. Das Feld **muss** die gleichzeitige Eingabe mehrerer Stellenangebote unterstützen, damit der Nutzer mehrere Bewerbungen in einem Durchlauf verfassen kann.

#### Mögliche Eingabeformate

- **Einzelne URL:** Eine komplette URL pro Zeile (z. B. `https://example.com/job/123`)
- **Mehrere URLs:** Beliebig viele Zeilen mit je einer URL
- **URL-Liste:** Optional auch durch Komma oder Semikolon getrennt in einer Zeile (zu spezifizieren)

#### Validierung & Fehlerbehandlung

- Jede eingegebene URL wird auf syntaktische Korrektheit geprüft (z. B. gültiges `http://`/`https://`-Schema)
- Nicht-URL-Text (z. B. natürlichsprachlicher Text) wird erkannt und mit einer Fehlermeldung versehen
- Doppelte URLs werden ignoriert oder der Nutzer wird darauf hingewiesen
- Maximale Anzahl gleichzeitig verarbeitbarer URLs sollte definiert werden (z. B. 10–20)

### Aufbau (Bildschirme)

Derzeit ist folgender Bildschirm vorgesehen:

#### Bildschirm 1: Eingabemaske für Stellen-URLs

| Komponente | Beschreibung |
|---|---|
| **Textfeld (Textarea)** | Mehrzeiliges Eingabefeld für eine oder mehrere URLs |
| **Hinweistext/Placeholder** | Erklärt das Format (z. B. "Bitte geben Sie eine URL pro Zeile ein") |
| **Schaltfläche "Weiter"** | Startet die Validierung und leitet zur nächsten Stufe (Bewerbungserstellung) |
| **Fehleranzeige** | Zeigt ungültige oder fehlerhafte URLs farblich markiert an |

#### UI/UX-Überlegungen

- **Live-Validierung:** URLs werden bereits während der Eingabe auf Gültigkeit geprüft (z. B. durch farbige Umrandung)
- **Batch-Größenbeschränkung:** Klare Begrenzung der Anzahl gleichzeitig verarbeitbarer URLs mit Hinweis an den Nutzer
- **Zwischenspeicher:** Bei fehlerhaften URLs bleiben die korrekten erhalten, damit der Nutzer nicht alles neu eingeben muss
- **Barrierefreiheit:** Das Textfeld sollte über ein `<label>`-Element beschriftet und per Tastatur bedienbar sein
- **Persistenz der validierten URLs:** Nach erfolgreicher Validierung werden die URLs dauerhaft (z. B. in einer lokalen Datenbank oder `SharedPreferences`) gespeichert, damit der Nutzer die Sitzung unterbrechen und später fortsetzen kann. Ein Autosave-Mechanismus sichert die Eingabe zusätzlich in regelmäßigen Abständen (z. B. alle 5 Sekunden). Die persistierte Liste wird beim erneuten Öffnen des Bildschirms automatisch geladen und steht für die nächste Stufe (Bewerbungserstellung) bereit.

### Technische Randbedingungen

- **Parsing:** URLs werden zeilenweise getrennt, Leerzeilen ignoriert
- **Normalisierung:** Entfernen von trailing Slashes, Kleinschreibung des Hosts, Überführung in einen kanonischen URL-String (z. B. mit `Uri.normalize()` in Dart)
- **Extraktion:** Aus jeder gültigen URL werden später die Jobdetails (Titel, Unternehmen, Standort) per Web-Scraping oder strukturiertem Parsing extrahiert

---

## Jobsuche

> **Zweck:** Ermöglicht dem Nutzer, Stellenangebote über Suchmaschinen zu finden, indem Suchkriterien wie Jobbeschreibung, Ort und Umkreis eingegeben werden.

### Funktionsweise

Ein Bildschirm bietet ein Eingabefenster, in dem der Nutzer die Jobbeschreibung, einen Ort und über einen Slider den Umkreis für die Suche eingibt. Nach Klick auf eine Schaltfläche werden im Hintergrund passende Suchmaschinen angefragt, um offene Stellen zu suchen. Die Ergebnisse können anschließend in die unter "Stelleneingabe" erzeugte Liste übernommen werden.

### Sortierung & Aufbau der Ergebnisliste

Die Sortierung und der Aufbau der Ergebnisliste basieren auf einem Fertigkeitenset, das aus dem Datensatz des Nutzers besteht und durch eine Fuzzy-Logik repräsentiert wird. Hierfür ist die unter `assets/fuzzy-logic` hinterlegte Bibliothek in das Flutter-Projekt zu integrieren und zu nutzen.

#### Bildschirm 2: Suchmaske für Stellenangebote

| Komponente | Beschreibung |
|---|---|
| **Textfeld (Jobbeschreibung)** | Eingabe der gewünschten Tätigkeit / Stellenbeschreibung |
| **Textfeld (Ort)** | Eingabe des Standorts (Stadt, PLZ, Region) |
| **Slider (Umkreis)** | Auswahl des Suchradius in km (z. B. 0–100 km) |
| **Schaltfläche "Suchen"** | Startet die Hintergrundsuche auf angeschlossenen Suchmaschinen |
| **Ergebnisliste** | Anzeige der gefundenen Stellen, sortiert nach Relevanz (Fuzzy-Logik) |
| **Schaltfläche "Übernehmen"** | Fügt ausgewählte Ergebnisse in die Stelleneingabe-Liste ein |

#### UI/UX-Überlegungen

- **Asynchrone Suche:** Die Suche läuft im Hintergrund, der Nutzer sieht einen Ladeindikator
- **Suchmaschinen-Auswahl:** Optional Auswahl der zu durchsuchenden Quellen (z. B. StepStone, Indeed, LinkedIn)
- **Filter & Sortierung:** Ergebnisse können nach Datum, Unternehmen oder Relevanz gefiltert werden
- **Zwischenspeicher:** Letzte Sucheingaben werden gespeichert, um erneute Eingaben zu vermeiden
- **Vermeidung von Dubletten:** Bewerbungen, die in den letzten 90 Tagen erstellt wurden, führen dazu, dass der zugehörige Job aus den Suchergebnissen ausgefiltert wird. Die Filterlogik prüft anhand der Job-ID, ob bereits eine Bewerbung existiert, deren Erstellungsdatum weniger als drei Monate zurückliegt. Der Schwellwert (90 Tage) sollte als konfigurierbare Konstante hinterlegt werden.
- **Einbindung der Jobbörse des Jobcenters:** Sofern eine API-Schnittstelle der Bundesagentur für Arbeit (z. B. JOBBÖRSE-API) verfügbar ist, soll diese als zusätzliche Suchquelle angebunden werden. Die Konfiguration der Jobcenter-Zuständigkeit (z. B. über PLZ oder Region) erfolgt über die Nutzereinstellungen und wird bei der API-Anfrage als Filterkriterium übergeben.
- **Visualisierung der Übereinstimmung:** Darstellung der prozentualen Übereinstimmung (0–100 %) zwischen jedem Skill im Nutzer-Fertigkeitenset und den extrahierten Anforderungen einer Stellenanzeige als horizontales Balkendiagramm (z. B. mit `fl_chart` in Flutter).
  - **Farbskala (semantisch):** Rot (0–40 %) → Gelb/Orange (41–70 %) → Grün (71–100 %) — definiert als konfigurierbare Konstanten in einem Theme-File (`assets/theme/colors.dart`).
  - **Allgemeine Übereinstimmungsanzeige:** Zusätzlich ein einzelner zusammengefasster Score-Wert (z. B. "73 % Übereinstimmung") oberhalb des Diagramms, ebenfalls farblich codiert gemäß obiger Skala.
  - **Barrierefreiheit:** Farbkodierung *nicht* als alleiniges Unterscheidungsmerkmal verwenden; zusätzlich Balken mit Muster/Hatching oder Textlabels (z. B. "niedrig", "mittel", "hoch") ergänzen. Kontrastverhältnisse nach WCAG 2.1 AA einhalten.
  - **Interaktivität:** Jeder Balken ist klickbar und zeigt in einem Tooltip oder Expander an, welche konkreten Anforderungen der Stellenanzeige zu diesem Skill-Wert geführt haben (z. B. "Geforderte Erfahrung: 5 Jahre Java → Vorhanden: 3 Jahre → Teilübereinstimmung").
  - **Datenquelle:** Die Übereinstimmungsberechnung erfolgt über die Fuzzy-Logik-Bibliothek aus `assets/fuzzy-logic`; die Visualisierung greift auf das Ergebnis dieser Berechnung zu.
  - **Ladezustand:** Während der Berechnung/API-Antwort wird ein animiertes Skeleton/Shimmer-Element anstelle des Diagramms angezeigt.
  - **Responsiveness:** Das Balkendiagramm skaliert auf schmalen Bildschirmen (Smartphone < 360 dp) automatisch auf vertikale Anordnung mit kürzeren Balken; horizontales Scrollen ist zu vermeiden.
- **Erweiterte Filterkriterien:** Über die reine Stellensuche hinaus werden zusätzliche Such-/Filterkriterien definiert, um Ergebnisse gezielt einzugrenzen. Die Kriterien gliedern sich in folgende Kategorien:

  - **Arbeitszeitmodell (Vollzeit / Teilzeit):**
    - Auswahl als Radio-Button-Gruppe oder Dropdown (z. B. "Vollzeit", "Teilzeit", "Beides")
    - Mehrfachauswahl optional (z. B. "Vollzeit + Teilzeit")
    - Default-Wert: "Beides" (keine Einschränkung)
    - Mapping auf API-Parameter (z. B. `employment_type=full_time,part_time`)
    - Datenmodell: Enum `EmploymentType { fullTime, partTime, both }`

  - **Arbeitsmodell (Homeoffice / Remote / Präsenz):**
    - Auswahl als Chip/Button-Gruppe (z. B. "Vor Ort", "Hybrid", "Remote", "Egal")
    - Falls die Such-API keine Remote-Filterung unterstützt, erfolgt eine Post-Filterung über Schlüsselwörter in der Stellenbeschreibung (z. B. "Remote", "Homeoffice", "mobile work")
    - Datenmodell: Enum `WorkModel { onSite, hybrid, remote, any }` mit konfigurierbarer Keyword-Liste für Post-Filterung in `assets/config/work_model_keywords.json`

  - **Bestimmte Firma / Unternehmen:**
    - Textfeld mit Autocomplete-Vorschlägen basierend auf bereits gefundenen Unternehmen aus der aktuellen Suche
    - Optional: Gespeicherte Favorite-Companies-Liste aus dem Nutzerprofil
    - Exakte Übereinstimmung vs. Teilübereinstimmung (Fuzzy-Match) als Option
    - Mehrere Unternehmen durch Komma getrennt eingebbar
    - Datenmodell: `List<String> targetCompanies`

  - **Beschäftigungsart (Festanstellung / Befristung / Freelance):**
    - Dropdown-Auswahl mit Default "Egal"
    - Datenmodell: Enum `EmploymentTypeCategory { permanent, fixedTerm, freelance, any }`

  - **Gehaltsspanne (optional):**
    - Minimalgehalt als Zahlenfeld (z. B. "Mindestens 45.000 €")
    - Währung als Dropdown (EUR, USD, etc.), Default EUR
    - UI: Number-Input mit Tausendertrennzeichen und €-Suffix
    - Datenmodell: `SalaryRange { double? min, String currency }`

  - **UI/UX-Integration:**
    - Die erweiterten Kriterien werden als **einklappbare Sektion ("Erweiterte Filter")** unterhalb der Suchmaske dargestellt, um den Standard-Workflow nicht zu überladen
    - Zustand der Sektion (offen/geschlossen) wird über eine `ExpandableFilter`-Komponente in Flutter realisiert
    - Gespeicherte Filtereinstellungen pro Nutzer (z. B. in `SharedPreferences` oder einer lokalen DB), damit der Nutzer nicht jedes Mal neu auswählen muss
    - **Live-Vorschau der aktiven Filter:** Oberhalb der Ergebnisliste werden aktiv gesetzte Filter als Chips/Tags angezeigt (z. B. "Vollzeit ✕", "Remote ✕", "Firma: Acme ✕"), die sich einzeln entfernen lassen

  - **Technische Randbedingungen:**
    - Filter werden als `Map<String, dynamic> filters` an die Such-API übergeben; APIs ohne nativen Filter-Support erhalten eine Post-Filterung auf Client-Seite
    - Reihenfolge der Filterauswertung: API-Filter (serverseitig) → Post-Filter (clientseitig)
    - Die Filterlogik wird in einer eigenen Service-Klasse `FilterService` gekapselt (`lib/services/filter_service.dart`)
    - Filter werden auf das einheitliche Datenmodell (`JobOffer`) angewendet, bevor es an die Ergebnisliste übergeben wird
    - Fehlerbehandlung: Falls eine Such-API einen Filterparameter nicht unterstützt, wird stillschweigend auf Post-Filter umgeschaltet (Log-Eintrag auf `debug`-Level)

### Technische Randbedingungen

- **Such-API:** Anbindung an Job-Suchmaschinen über REST-APIs (z. B. Indeed API, Adzuna API) oder Web-Scraping
- **Fuzzy-Logik:** Integration der Bibliothek aus `assets/fuzzy-logic` zur Bewertung der Übereinstimmung zwischen Suchkriterien und Stellenanzeigen basierend auf dem Nutzer-Fertigkeitenset
- **Ergebnis-Parsing:** Ergebnisse werden in ein einheitliches Datenmodell überführt (Titel, Unternehmen, Ort, Beschreibung, Link)
- **Ratenbegrenzung:** Berücksichtigung von API-Rate-Limits durch verzögerte Anfragen oder Warteschlangen

---

## Ergebnisübersicht

> **Zweck:** Ermöglicht dem Nutzer, die automatisch generierten Bewerbungen zu begutachten, herunterzuladen, zu korrigieren oder erneut zu generieren, bevor sie versendet oder lokal gespeichert werden.

### Funktionsweise

Nachdem alle konfigurierten Stellenangebote verarbeitet (gescrapt, analysiert, mit Nutzerdaten befüllt) wurden, wechselt die App in diesen Bildschirm. Der Nutzer sieht eine Übersicht aller generierten Bewerbungen mit ihrem jeweiligen Status. Jede Bewerbung kann einzeln geöffnet werden, um die vollständigen Inhalte (Anschreiben, Lebenslauf, ggf. Zeugnisse) einzusehen. Aus der Detailansicht heraus kann die Bewerbung als PDF-Dokument heruntergeladen, in einer Vorschau betrachtet, zur erneuten Generierung markiert oder endgültig gelöscht werden. Zusätzlich steht ein **Batch-Export** zur Verfügung, um alle fertigen Bewerbungen gesammelt herunterzuladen (z. B. als ZIP-Archiv).

#### Aufbau des Statusmodells

Jede Bewerbung durchläuft während der Generierung folgende Phasen; der Nutzer sieht den jeweils aktuellen Status in der Liste:

- **Wartend (queued):** Die Bewerbung wurde zur Generierung vorgemerkt, der Prozess läuft noch nicht.
- **In Bearbeitung (processing):** Die Generierung läuft (Scraping, Anschreiben-Erstellung, Zusammenführung).
- **Generierung fehlgeschlagen (failed):** Bei einem Fehler (z. B. URL nicht erreichbar, Parsing-Fehler) wird die Bewerbung mit einer Fehlermeldung markiert.
- **Generierung abgeschlossen (completed):** Die Bewerbung liegt vollständig vor und kann begutachtet werden.
- **Exportiert (exported):** Die Bewerbung wurde heruntergeladen; dies ist ein reiner Informationsstatus, der die Liste nicht blockiert.

Fehlgeschlagene Bewerbungen können manuell erneut gestartet werden, ohne dass die gesamte Stapelverarbeitung wiederholt werden muss.

#### Bildschirm 3: Ergebnisübersicht

| Komponente | Beschreibung |
|---|---|
| **Statusleiste (Fortschrittsanzeige)** | Zeigt den Gesamtfortschritt der Stapelverarbeitung an (z. B. "4 / 7 Bewerbungen fertig") mit Prozentbalken |
| **Ergebnisliste** | Listet alle verarbeiteten Stellenangebote mit Status-Icon (✔ ⏳ ❌), Jobtitel und Unternehmen |
| **Schaltfläche "Alle exportieren"** | Startet den Batch-Download aller fertigen Bewerbungen als ZIP-Archiv |
| **Schaltfläche "Neu starten" (pro Eintrag)** | Setzt eine fehlgeschlagene Bewerbung zurück in die Warteschlange |
| **Schaltfläche "Löschen" (pro Eintrag)** | Entfernt eine Bewerbung aus der Liste (mit Bestätigungsdialog) |
| **Schaltfläche "Zurück"** | Führt zur vorherigen Stufe zurück (Stelleneingabe oder Jobsuche) |

#### Bildschirm 3a: Detailansicht einer Bewerbung (durch Tippen auf einen Listeneintrag erreichbar)

| Komponente | Beschreibung |
|---|---|
| **PDF-Vorschau** | Eingebettete Vorschau des generierten Bewerbungsdokuments (Seitenweise blätterbar) |
| **Schaltfläche "Als PDF speichern"** | Lädt die Bewerbung als einzelne PDF-Datei herunter |
| **Schaltfläche "Erneut generieren"** | Startet die Neugenerierung für diese einzelne Bewerbung (z. B. nach manueller Korrektur der Eingabedaten) |
| **Schaltfläche "Löschen"** | Entfernt die Bewerbung (mit Bestätigungsdialog) |
| **Metadaten-Anzeige** | Zeigt Zusatzinformationen: Stellen-URL, Erstellungsdatum, Dateigröße der PDF, letzte Änderung |

#### UI/UX-Überlegungen

- **Live-Fortschritt:** Während der laufenden Generierung wird die Ergebnisliste dynamisch aktualisiert (z. B. per Stream/WebSocket), sodass der Nutzer den Fortschritt in Echtzeit verfolgen kann
- **Fehlerbehandlung:** Fehlgeschlagene Einträge werden farblich hervorgehoben (rot) und enthalten eine einblendbare Fehlerdetail-Meldung (z. B. "HTTP 404 – Seite nicht gefunden"). Der Nutzer kann direkt aus der Fehleransicht heraus die URL korrigieren und erneut starten.
- **Zwischenspeicherung:** Die generierten Bewerbungen (inkl. Status) werden persistent gespeichert (z. B. in einer lokalen SQLite-Datenbank oder als Dateien im App-Verzeichnis), sodass die Ergebnisliste auch nach App-Neustart erhalten bleibt
- **Batch-Export als ZIP:** Alle fertigen PDFs werden in ein ZIP-Archiv verpackt. Das Archiv erhält einen aussagekräftigen Dateinamen (z. B. `Bewerbungen_2026-07-22.zip`). Leere oder fehlgeschlagene Einträge werden automatisch ausgeschlossen, der Nutzer wird über die Anzahl der tatsächlich exportierten Dateien informiert.
- **Dateibenennung der Einzel-PDFs:** Jede PDF-Datei folgt einem einheitlichen Schema, z. B. `Bewerbung_{Unternehmen}_{Datum}.pdf`. Sonderzeichen werden ersetzt oder entfernt.
- **Bestätigungsdialoge:** Vor dem Löschen einer Bewerbung erscheint ein Dialog ("Möchten Sie diese Bewerbung wirklich löschen?"), um versehentliches Entfernen zu verhindern. Auch das erneute Generieren löst eine Bestätigungsabfrage aus, da dabei ggf. manuelle Änderungen verloren gehen.
- **Barrierefreiheit:** Status-Icons werden durch Textlabels ergänzt (z. B. "Abgeschlossen", "Fehlgeschlagen"). Die PDF-Vorschau sollte per Screenreader erfassbar sein (alternativ eine textuelle Zusammenfassung anbieten). Alle Schaltflächen sind per Tastatur erreichbar.
- **Leerer Zustand (Empty State):** Falls keine Bewerbungen vorhanden sind (z. B. nach Löschen aller Einträge), wird ein Hinweistext mit Vorschlag zur Rückkehr zur Stelleneingabe angezeigt.
- **Sortierung der Liste:** Standardmäßig sortiert nach Status (fehlgeschlagen zuerst, dann in Bearbeitung, dann fertig) und innerhalb gleicher Status alphabetisch nach Unternehmen. Der Nutzer kann die Sortierung umkehren oder nach Datum ordnen.
- **Dark-Mode-Unterstützung:** Die Statusfarben (grün/rot/gelb) müssen auch im Dark-Mode gut unterscheidbar sein. Die kontrastreichen Farbdefinitionen aus dem Theme-File (`assets/theme/colors.dart`) werden hier wiederverwendet.

### Technische Randbedingungen

- **PDF-Generierung:** Die Erstellung der PDF-Dokumente erfolgt serverseitig (z. B. über einen REST-Endpunkt) oder clientseitig in Flutter (z. B. mit dem Paket `pdf` oder `printing`). Die finale PDF wird als `Uint8List` im Speicher gehalten und erst beim Export auf das Dateisystem geschrieben.
- **Speicherort:** Generierte PDFs werden im App-eigenen Dokumentenverzeichnis abgelegt (z. B. `getApplicationDocumentsDirectory()` in Flutter). Der Pfad zur Datei wird in der lokalen Datenbank gespeichert; die Datei selbst wird nicht in die App-Datenbank eingebettet.
- **ZIP-Erstellung:** Der Batch-Export nutzt ein ZIP-Utility (z. B. `archive`-Paket in Dart). Das ZIP-Archiv wird temporär im Cache-Ordner erstellt und über den Share/Datei-Export-Dialog des Betriebssystems angeboten (z. B. über `share_plus` oder die plattformspezifische "In Dateien speichern"-Funktion).
- **Datenmodell:** `Application`-Klasse in `lib/models/application.dart` mit Feldern:
  - `int id` (Primärschlüssel)
  - `String jobTitle`, `String company`, `String jobUrl`
  - `ApplicationStatus status` (Enum: `queued`, `processing`, `completed`, `failed`, `exported`)
  - `String? pdfPath` (lokaler Dateipfad, nullable bis zur Fertigstellung)
  - `String? errorMessage` (nullable, nur bei `failed`)
  - `DateTime createdAt`, `DateTime? completedAt`
- **Persistenz:** Verwendung einer lokalen Datenbank (z. B. `sqflite` in Flutter) zur Speicherung der `Application`-Einträge. Der PDF-Pfad referenziert eine Datei außerhalb der DB.
- **Dateigrößen-Limit:** Einzelne PDFs sollten 10 MB nicht überschreiten, das gesamte ZIP-Archiv maximal 50 MB. Bei Überschreitung wird eine Warnung angezeigt.
- **Fehlerbehandlung und Retry-Mechanismus:**
  - Schlägt die Generierung fehl, wird der Fehler in `errorMessage` gespeichert und der Status auf `failed` gesetzt.
  - Ein exponentieller Backoff-Retry (max. 3 Versuche) wird für flüchtige Fehler (z. B. Timeout) automatisch durchgeführt, bevor der Status auf `failed` gesetzt wird.
  - Der Nutzer kann fehlgeschlagene Einträge manuell erneut anstoßen; der Retry-Zähler wird dabei zurückgesetzt.
- **Speicherbereinigung:** Bei erneuter Generierung wird die alte PDF-Datei gelöscht, bevor die neue erstellt wird. Verwaiste PDFs (z. B. nach Löschen eines Eintrags) werden regelmäßig (z. B. beim App-Start) durch einen Cleanup-Job entfernt.
- **Logging:** Jeder Generierungsschritt und jeder Export wird auf `info`-Level geloggt (Dauer, Dateigröße, Zielpfad). Fehler werden auf `error`-Level geloggt inklusive Stacktrace. Die Logs werden in einer zentralen Log-Datei im App-Cache-Ordner gespeichert (maximal 5 MB, Rotation).
- **Threading:** Die PDF-Generierung läuft in einem separaten Isolate (in Flutter), um die UI nicht zu blockieren. Die Status-Updates werden über `SendPort`/`ReceivePort` an den Hauptisolate kommuniziert.

## Navigation zwischen den Bildschirmen

> **Zweck:** Definiert ein einfaches, wartbares Navigationskonzept für die App, das dem Nutzer eine klare Bildschirmhierarchie bietet und einen reibungslosen Datenfluss zwischen den Stufen sicherstellt.

### Architektur-Entscheidung: Declarative Routing mit `go_router`

Für die Navigation wird **`go_router`** (Flutter's empfohlenes declaratives Routing-Framework) verwendet. Dies bietet:

- **Zentralisierte Routendefinition** in einer `GoRouter`-Instanz
- **Deep Linking**-Unterstützung (optional für spätere Erweiterungen)
- **Type-sichere Pfadparameter** für Datenweitergabe
- **Redirect-Guards** für erzwungene Navigationsreihenfolgen
- **ShellRoute** für gemeinsame Layouts (z. B. AppBar)

### Routen-Tabelle

| Pfad | Bildschirm | Zweck | Erreichbar von |
|---|---|---|---|
| `/` | **Start/Stelleneingabe** (Screen 1) | Eingabe von Stellen-URLs | — |
| `/search` | **Jobsuche** (Screen 2) | Suche nach Stellen via Suchmaschinen | `/` (via "Jobsuche"-Button) |
| `/applications` | **Ergebnisübersicht** (Screen 3) | Liste aller generierten Bewerbungen | `/`, `/search` (via "Weiter"/"Übernehmen") |
| `/applications/:id` | **Detailansicht** (Screen 3a) | Einzelansicht einer Bewerbung | `/applications` (via Tippen) |

**Optionale Zusatzrouten (zukünftig):**

| Pfad | Bildschirm | Zweck |
|---|---|---|
| `/settings` | **Einstellungen** | Nutzerprofil, API-Keys, Jobcenter-Konfiguration |
| `/help` | **Hilfe/Anleitung** | Erklärung der App-Funktionen |

### Navigationsdiagramm (Ablauf)

```
                    ┌──────────────────┐
                    │                  │
       ┌───────────►│  Stelleneingabe  │◄───────────┐
       │            │    (Screen 1)    │            │
       │            │        │         │            │
       │            │        ▼         │            │
       │            │   [Weiter]       │            │
       │            │        │         │            │
       │            │        ▼         │            │
       │            └────────┼─────────┘            │
       │                     │                      │
       │                     ▼                      │
       │            ┌──────────────────┐            │
       │            │                  │            │
       │            │ Ergebnisübersicht│            │
       └────────────┤   (Screen 3)     ├────────────┘
       (Zurück)     │   │          ▲   │  (Zurück)
                    │   ▼          │   │
                    │ [Tippen]─────┘   │
                    │   │              │
                    │   ▼              │
                    │ Detailansicht    │
                    │  (Screen 3a)     │
                    └──────────────────┘

       ┌──────────────────┐
       │                  │
       │    Jobsuche      ├───────(Übernehmen)──► Ergebnisübersicht
       │   (Screen 2)     │
       └────────┬─────────┘
                │
         (Zurück nach /)
```

### Datenweitergabe zwischen Screens

Um die Bildschirme weitgehend entkoppelt zu halten, wird die Datenweitergabe über einen **zentralen Zustandsmanager (z. B. Riverpod/Cubit)** realisiert – nicht über `Navigator.push`-Argumente.

| Übergang | Daten | Mechanismus |
|---|---|---|
| Screen 1 → Screen 3 | Validierte URL-Liste (`List<String>`) | Nach Validierung in `JobRepository` speichern → Screen 3 liest aus selber Quelle |
| Screen 2 → Screen 3 | Ausgewählte Job-IDs (`List<String>`) | Übernommene Jobs in `JobRepository` hinzufügen → Screen 3 aktualisiert |
| Screen 3 → Screen 3a | `int applicationId` | Pfadparameter `:id` im Route-Pfad |
| Screen 3 → Screen 1 (via "Zurück") | (keine) | Einfache Navigation zurück; der Zustand von Screen 1 bleibt erhalten (Autosave) |
| Screen 3 → Screen 2 (via "Zurück") | (keine) | Einfache Navigation zurück; Suchfilter bleiben erhalten |

### Navigationslogik im Detail

#### 1. Startbildschirm (Screen 1 → Screen 3)

```dart
// Nach erfolgreicher Validierung:
context.go('/applications');
// Der JobRepository-Provider wird automatisch die validierten URLs
// aus dem persistenten Speicher laden und an Screen 3 übergeben.
```

- **Validierungsprüfung:** Vor der Navigation wird `context.go()` in einem `GoRouter`-Redirect-Guard abgesichert: Falls keine validierten URLs im Repository vorhanden sind, wird zurück nach `/` geroutet.
- **Fehlerfall:** Falls die Persistenz fehlschlägt, wird ein Snackbar/Dialog angezeigt, die Navigation unterbleibt.

#### 2. Jobsuche (Screen 2 → Screen 3)

```dart
// Nach Klick auf "Übernehmen":
final selectedIds = await showDialog<List<String>>( /* Mehrfachauswahl */ );
if (selectedIds != null && selectedIds.isNotEmpty) {
  jobRepository.addJobsFromSearch(selectedIds);
  context.go('/applications');
}
```

- **Leere Auswahl:** Falls der Nutzer keine Jobs übernimmt, bleibt er auf Screen 2. Ein Hinweistext erklärt, dass er Jobs auswählen muss.
- **Parallelität:** Jobs können sowohl über Screen 1 (URLs) als auch über Screen 2 (Suche) hinzugefügt werden. Das Repository führt eine **Deduplizierung** anhand der Job-URL durch.

#### 3. Ergebnisübersicht → Detailansicht (Screen 3 → Screen 3a)

```dart
// Tippen auf einen Listeneintrag:
context.go('/applications/${application.id}');
```

- **ID-Prüfung:** Existiert die Application-ID nicht (z. B. gelöscht während der Navigation), zeigt die Detailansicht einen "Nicht gefunden"-Zustand und navigiert automatisch zurück zur Liste.
- **Deep Link:** Die Route `/applications/:id` kann später auch von außerhalb (z. B. via Notification) geöffnet werden.

#### 4. Rückwärts-Navigation

- **Zurück-Button (AppBar):** `Navigator.pop(context)` bzw. `context.pop()` – standardmäßiger Back-Stack.
- **Hardware-Zurück (Android):** Wird automatisch durch `PopScope` (ab Flutter 3.16+) abgefangen. Auf Screen 3 (Ergebnisübersicht) mit Bestätigungsdialog, falls noch Bewerbungen in Bearbeitung sind.
- **Browser-Zurück (Web):** Wird durch `go_router` automatisch behandelt.

### Zustandserhaltung bei Navigation

| Szenario | Verhalten |
|---|---|
| **Screen 1 → Screen 3 → Zurück → Screen 1** | Eingetippte URLs bleiben durch Autosave erhalten. Der Cursor und Scrollposition können optional via `PageStorage` wiederhergestellt werden. |
| **Screen 2 → Screen 3 → Zurück → Screen 2** | Letzte Sucheingaben (Jobbeschreibung, Ort, Umkreis, Filter) bleiben durch gespeicherte `SearchPreference` erhalten. |
| **App schließen und neu öffnen** | Alle persistierten Daten (URLs, Suchfilter, Bewerbungsstatus) werden aus der lokalen DB geladen. Der zuletzt besuchte Screen wird als Startroute verwendet (optional: immer Screen 1 als Start). |
| **Screen 3a → App schließen → neu öffnen** | Kein automatischer Return zur Detailansicht; App startet auf Screen 1. Eine "Zuletzt angesehen"-Funktion ist optional. |

### Fehlerbehandlung & Edge Cases

| Fall | Reaktion |
|---|---|
| **Keine validierten URLs vorhanden** – Nutzer versucht, `/applications` direkt aufzurufen | `GoRouter`-Redirect fängt ab → Navigation zu `/` |
| **Application-ID in `/applications/:id` existiert nicht** (z. B. gelöscht) | Detailansicht zeigt "Bewerbung nicht gefunden" + Button "Zurück zur Übersicht" |
| **Navigation während laufender Generierung** (Screen 3 aktiv) | `PopScope` blockiert Zurück-Navigation mit Dialog: "Generierung läuft noch. Wirklich abbrechen?" |
| **Batch-Export läuft** – Nutzer navigiert weg | Export läuft im Hintergrund-Isolate weiter; Benachrichtigung bei Abschluss (Snackbar/Toast) |
| **Screen 2 (Jobsuche) ohne Internet** | Ladeindikator wird durch Fehlermeldung ersetzt; Button "Erneut versuchen" erscheint. Navigation zurück zu Screen 1 bleibt möglich. |
| **Doppelte Navigation (schnelles Klicken)** | `context.go()` ist idempotent – wiederholtes Klicken auf "Weiter" führt nicht zu doppelten Einträgen. Zusätzlich wird der Button während der Navigation deaktiviert. |

### Umsetzung in Flutter

```dart
// lib/app/router.dart
import 'package:go_router/go_router.dart';

final goRouter = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    // Guard: Applications-Route nur mit validierten Daten erreichbar
    final isApplicationsRoute = state.matchedLocation == '/applications'
        || state.matchedLocation.startsWith('/applications/');
    if (isApplicationsRoute) {
      final hasApplications = context.read<JobRepository>().hasValidApplications;
      if (!hasApplications) return '/';
    }
    return null; // kein Redirect
  },
  routes: [
    GoRoute(
      path: '/',
      name: 'jobInput',
      builder: (context, state) => const JobInputScreen(),
    ),
    GoRoute(
      path: '/search',
      name: 'jobSearch',
      builder: (context, state) => const JobSearchScreen(),
    ),
    GoRoute(
      path: '/applications',
      name: 'applicationList',
      builder: (context, state) => const ApplicationListScreen(),
      routes: [
        GoRoute(
          path: ':id',
          name: 'applicationDetail',
          builder: (context, state) {
            final id = int.parse(state.pathParameters['id']!);
            return ApplicationDetailScreen(applicationId: id);
          },
        ),
      ],
    ),
  ],
);
```

### Entscheidungsmatrix: Alternativen zu `go_router`

| Ansatz | Vorteil | Nachteil | Entscheidung |
|---|---|---|---|
| **Navigator 1.0** (`Navigator.push`/`pop`) | Einfach, keine zusätzliche Dependency | Kein Deep Linking, manuelle Redirects, schlecht testbar | ❌ Verworfen |
| **Navigator 2.0** (roh) | Maximale Flexibilität | Hohe Komplexität, viel Boilerplate | ❌ Verworfen |
| **go_router** | Declarativ, type-sichere Pfade, Redirect-Guards, De facto Standard | Zusätzliche Dependency (~100 KB) | ✅ **Gewählt** |
| **auto_route** | Code-Generierung, type-safe | Build-Runner nötig, weniger flexibel bei Redirects | ❌ Verworfen |
| **Beamer** | Sehr flexibel | Steile Lernkurve, zu mächtig für diese App-Größe | ❌ Verworfen |

### Zusammenfassung

- **Navigations-Framework:** `go_router` (declarativ, wartbar, testbar)
- **Datenfluss:** Zentraler Zustandsmanager (Riverpod/Cubit) statt Route-Argumente
- **Guards:** Redirect auf `/` bei fehlenden Daten; `PopScope` zum Schutz laufender Prozesse
- **Persistenz:** Alle relevanten Eingaben (URLs, Suchfilter, Bewerbungen) werden automatisch gespeichert und beim Zurücknavigieren oder Neustart wiederhergestellt
- **Ziel:** Der Nutzer kann jederzeit zwischen den Bildschirmen wechseln, ohne Daten zu verlieren, und wird durch klare Rückmeldungen (Fehlerdialoge, Bestätigungen, Ladezustände) geführt.
