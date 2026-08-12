# Gefundene Bugs

## Bug: Generierte PDFs sind korrupt (leer)

**Symptom:**
Generierte PDFs lassen sich nicht öffnen. Betroffen z. B.:
- Job: https://talents.studysmarter.de/companies/neon-software-solutions/flutter-entwickler-21113602/
- Datei: `/assets/mydata/25_Flutter_Entwickler.pdf`

**Root Cause (gefunden):**

Die Datei ist nur **427 Bytes** groß und enthält `Kids[]/Count 0` – das ist eine **valide, aber leere PDF mit 0 Seiten**.

Ursache: Im `JobRepository`-Konstruktor wurde `PdfGenerator` nur mit `templateLoader` und `templateRenderer` initialisiert. Die drei Generatoren `coverPageGenerator`, `coverLetterGenerator` und `cvGenerator` waren **null**. Dadurch wurden in `generateApplicationPdf()` **keine einzigen Seiten hinzugefügt** – das leere Dokument wurde trotzdem gespeichert.

**Fix (implementiert):**

1. **`job_o_matic/lib/data/repositories/job_repository.dart`**
   - Alle drei Generatoren (`CoverPageGenerator`, `CoverLetterGenerator`, `CvGenerator`) werden jetzt beim Erstellen des `PdfGenerator` übergeben.

2. **`job_o_matic/lib/data/services/pdf/pdf_generator.dart`**
   - Sicherheitscheck hinzugefügt: Wenn `pageCount == 0`, wird ein `StateError` geworfen statt einer leeren (korrupten) PDF.
   - Logging erweitert um Seitenanzahl: `PDF gespeichert: $filePath ($pageCount Seiten)`.

**Verifikation:**
- Die alte korrupte Datei `assets/mydata/25_Flutter_Entwickler.pdf` sollte gelöscht werden (leere PDF mit 0 Seiten).
- Nach dem Fix sollten PDFs erneut generiert werden – die neue Datei enthält Deckblatt, Anschreiben und Lebenslauf.

## Bug: Erstelltes PDF enthält falsche Daten

**Symptom:**
Das erzeugte PDF unter `/assets/mydata/26_Flutter_Entwickler.pdf` enthält falsche oder Musterdaten statt der echten CV-Daten.

**Root Cause (gefunden):**

Die Datei `job_o_matic/assets/mydata/cv/cv_data.yaml` enthielt **Muster-/Platzhalterdaten**:
- `matthias.struck@example.com` statt `MatthiasStruck@gmx.net`
- `Musterstraße 1, 12345 Berlin` statt `Glacisweg 9, 13583 Berlin`
- `Tech GmbH`, `Web Solutions AG`, `StartUp GmbH` statt der echten Arbeitgeber
- Generische Skills statt der echten Kenntnisse

Zusätzlich wurde die CV-Daten aus der **Datenbank gecacht** (`JobRepository.initialize()` lädt `_cvData` aus der DB), sodass selbst nach einer Korrektur der YAML-Datei die alten Daten weiterverwendet wurden.

**Fix (implementiert):**

1. **`job_o_matic/assets/mydata/cv/cv_data.yaml`**
   - Mit echten Daten aus dem Lebenslauf (`Matthias_Struck_14072026.pdf`) aktualisiert:
     - Kontaktdaten: Glacisweg 9, 13583 Berlin, 030 3337311, MatthiasStruck@gmx.net
     - Berufserfahrung: Pegasus Spiele, Dryad, Doorbird, X2E, Automatentechnik Baumann, Ferchau, netfabb, Sintermask, Handy-games, Kithara
     - Ausbildung: TFH Berlin (Diplom-Ingenieur), appAkademie, Skilldrops Akademie
     - Skills: Dart, Flutter, C/C++, Python, Java, C#, JavaScript, Assembler, SQL, Scrum, Git

2. **`job_o_matic/lib/data/repositories/job_repository.dart`**
   - `_ensureCvDataLoaded()` lädt die YAML-Datei jetzt **immer** neu (nicht nur wenn `_cvData == null`).
   - `initialize()` lädt CV-Daten **nicht mehr** aus der Datenbank – die YAML-Datei ist die autoritative Quelle.
   - Die Datenbank wird nach dem Laden aus der YAML-Datei aktualisiert.

**Verifikation:**
- Die alte PDF `assets/mydata/26_Flutter_Entwickler.pdf` sollte gelöscht und neu generiert werden.
- Nach dem Fix enthält die neue PDF die echten CV-Daten.
