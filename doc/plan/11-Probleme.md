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

## Bug: Deckblatt

1. Anstelle des Platzhalters "Logo" sollte das Bild eingefügt werden, welches unter "assets/mydata/cv" liegt

2. Wenn man das Beispiel "/assets/mydata/28_Unbekannt.pdf" betrachtet, fällt auf, dass di Jobbeschreibung nicht geclippt wird.
Dort steht "Senior Flutter Developer / Client Engineer, AI-Native and Rust-Friendly (m/f/d) | Jobs at Bliq", wobei "Jobs at Bliq" von der Webseite stammt. Können wir einen Algoyrthmus entwerfen, welcher die Stellenbeschreibung sauber rausclippt und alles, was nicht dazugehört, wie eben das "Jobs at Bliq" rausfiltert?

3. Was bedeutet das "Unbekannt" eine Zeile tiefer? Woher kommt es und wie kann es vermieden oder sinnvoll angepasst werden?

4. In der Fußzeile steht neub voller Name, sowie meine Telefonnummer. Das schaut irgendwie falsch aus. Wie können wir das verbessern?

5. Wäre es klüger, wenn die Zeile "Senior Flutter Developer / Client Engineer,
AI-Native and Rust-Friendly (m/f/d)" im PDF "/assets/mydata/30_Bliq.pdf" zentriert ist? Generell wirkt das Deckblatt, als wenn die Textzeilen besser über das Blatt verteilt sein können. Wird das dynamisch generiert oder ist das eine fixe Einstellung?

## Bug: Anschreiben

1. Starke Stilistische Utnershciede zwischen Anschreiben und Deckblatt. Bitte anpassen. => Erledigt
2. Das Anschreiben ist bei jeder Bewerbung gleich. Haben wir eine Möglichkeit es auf jede Stelle anzupassen, es zu individualisieren? => Erledigt
3. Der Lebenslauf entspricht, nach den Änderungen aus 1., keinerlei Standards für gutes Design von Anschreiben mehr. Siehe "/assets/mydata/31_Bliq.pdf". Die große rote Überschrift ist zu viel. Bitte nochmal genau überarbeiten. => Erledigt
4. Das Anschreiben wurde, nach 1. insbesondere, augenscheinlich verschlimmbessert und entspricht nicht dem gängigen Design f+r Anschreiben. Siehe "/assets/mydata/31_Bliq.pdf". Zum Beispiel die große rote Überschrift ist out of place, ebenso die Linie darunter. Auch ein Beispiel ist die Nennung meiner Adresse unter der großen Überschrift und das Fehler der Firmenaresse von Bliq. Kurz: Es gibt mehrere Formfehler von denen nur ein paar genannt wurden. Welche müssen noch verbessert werden?

## Bug Anschreiben, die 2.
Siehe "/assets/mydata/31_Bliq.pdf".

- Die Kopfzeile schaut nicht aus, wie auf dem Deckblatt => Anpassen
- Datum oben rechts in der ersten Zeile ist in Ordnung.
- In der Zeile "Bewerbung als Senior Flutter Developer / Client Engineer, AI-Native and Rust-Friendly (m/f/d)" fehlt das Wort "Betreff"
- Zwischen Datum und dem Betreff fehlt die Adresse von der Firma => Einbauen, ggf. Scraper nutzen, falls die Firmenadresse nicht offensichbtlich ist.
- Unter dem Betreff folgende redundante Daten, wie nochmals meine Adresse, ein erneutes Datum und noch ein Betreff => entfernen.
- Am Ende des Anschreibens steht nochmal "Mit freundlichen Grüßen\nMatthias Struck" => Entfernen
- Das Anschreiben hat seltsame Leerzielen => Korrgieren
- Anschreiben nicht änder, als eine Seite.
- Anschreiben soll dynamisch, ggf. sogar ki-unterstützt anhand der Bewerbung aufgebaut werden => wie?

## Bug Lebenslauf
Siehe "/assets/mydata/31_Bliq.pdf".

- die Datumsangaben, z.B. "07/2025 heute" bei "Freier Mitarbeiter (Honorarbasis), Redaktion Shadowrun" unter dem Punkt "Berufserfahrung" haben Zeichenfehler. => Korrgieren
- Das Gesamtdesign des Lebenslaufes, etwa bei den Fußzeilen, hebt sich von dem des Deckblatts und des Anschreibens ab. => Überprüfen und ggf. anpassen.
- Sind die "Persönlichen Daten" vollständig? Genügt es, wenn die so kurz sind?
- Die Prozentzahlen der Balkengrafiken unter "Kenntnisse" stimmen nicht mit den Balken überein. Etwa steht bei Dart "95%", aber der Balken ist nur halb voll. Können wir da eine andere Darstellung finden?
- Die Liste der Kenntnisse im Vergleich zur Vorlage ist ein wenig kurz. Soll das so? 
- Können wir die Liste der Kenntnisse so umstrukturieren, dass sie dynmaisch anhand der in der Stellenbeschreibung geforderten sortiert sind? Was für Optionen haben wir da?

## Bug Lebenslauf YAML
Quelle: "assets/myassets/cv"

- Die Lebenslauf YAML scheint im bereich "Berfuliche Kenntnisse und Fertigkeiten" deutlich zu kurz zu sein. Vergleiche ich was darin steht, mit der Vorlage. Bitte den Inhalt der YAML überprüfen und ggf. updaten.

## Bug Lebenslauf Zertifikate
Quelle: "assets/myassets/cv"

- Es scheinen beim Lebenslauf die beruflichen Zertikate zu fehlen, welche im original PDF Ordner liegen. Wurden diese bereits angefügt und, passend, eingepflegt?

## Bug Anschreiben: Textbreiten
Siehe "/assets/mydata/31_Bliq.pdf"

- Die Anschreiben im Lebenslauf scheinen stark zu variieren. Woran liegt das und wie könnte man das lösen und weiterhin DIN 5008 konform zu sein?

**Root Cause (gefunden):**

Alle drei Generatoren (`cover_letter_generator.dart`, `cv_generator.dart`, `cover_page_generator.dart`) verwendeten eine explizite `margin: const pw.EdgeInsets.all(48)`-Eigenschaft. Diese **überschrieb** die DIN-5008-Ränder aus `PdfUtils.pageFormat` (links 71pt/25mm, rechts 57pt/20mm, oben/unten 57pt/20mm). Dadurch:
- Einheitliche Textbreite von 499pt statt der DIN-5008-konformen 467pt
- Die Textbreiten variierten, weil die explizite `margin`-Eigenschaft die `pageFormat`-Ränder überstimmte

**Fix (implementiert):**

1. **`cover_letter_generator.dart`** – `margin: const pw.EdgeInsets.all(48)` entfernt
2. **`cv_generator.dart`** – `margin: const pw.EdgeInsets.all(48)` entfernt
3. **`cover_page_generator.dart`** – `margin: const pw.EdgeInsets.all(48)` entfernt

Alle drei Generatoren verwenden jetzt ausschließlich die DIN-5008-Ränder aus `PdfUtils.pageFormat`. Die Textbreiten sind damit konsistent und DIN-5008-konform.

**Verifikation:**
- Alle 43 Tests bestanden (inkl. 6 DIN-5008-Tests)
- Keine weiteren `EdgeInsets.all(48)`-Vorkommen im PDF-Code

- Bitte in Siehe "/assets/mydata/31_Bliq.pdf" reinsehen. Im Anschreiben sind immer noch augenscheinlich drei unterschiedliche Textbreiten versehen? Und stimmt die Textausrichtung? Ausserdem: gehört das "mit freundlichen Grüßen" und mein Name darunter nicht nach links?

**Analyse:**

1. **Drei unterschiedliche Textbreiten**: Das ist teilweise normales DIN-5008-Verhalten – Absender und Empfängerblock sind üblicherweise schmaler als der Fließtext. Die wahrgenommene Inkonsistenz entsteht durch die unterschiedlichen Breiten der Blöcke. (Empfängerblock-Anpassung wurde auf Wunsch des Nutzers zurückgestellt.)

2. **Textausrichtung**: Der Fließtext war linksbündig (Flattersatz). DIN 5008 empfiehlt Blocksatz.

3. **Grußformel**: War rechtsbündig (`centerRight`). DIN 5008 schreibt vor, dass die Grußformel **linksbündig** ist.

**Fix (implementiert):**

**`cover_letter_generator.dart`:**
- **Fließtext**: `textAlign: pw.TextAlign.justify` hinzugefügt (Blocksatz, DIN-5008-konform)
- **Grußformel**: `pw.Alignment.centerRight` → `pw.Alignment.centerLeft` (linksbündig, DIN-5008-konform)

**Verifikation:**
- Alle 43 Tests bestanden

# Bug Vorlage für den Cover Letter

- Die Vorlage "cover_letter_default.txt" ist darauf zu überprüfen, ob sie unseren Anforderungen an ein Anschreiben genügt, inwieweit das aus ihr generierte Eregbnis DIN 5008 konform ist und was wir ver#ndern könnten. Besonders die festen Zeilenabsätze im Textfile sehen aus, als könnten sie alles zerhacken.

**Root Cause (gefunden):**

Die Vorlage `cover_letter_default.txt` enthielt **feste Zeilenumbrüche nach ~72 Zeichen** (z.B. "mit großem Interesse habe ich Ihre Stellenausschreibung für die Position" / "als {{jobTitle}} bei der {{company}} gelesen."). Der `TemplateRenderer` ersetzte nur die Platzhalter, aber die Zeilenumbrüche blieben erhalten. Dadurch:
- Der Fließtext wurde mit den fixen Zeilenumbrüchen gerendert
- Das rechte Textende wurde unregelmäßig (Blocksatz wirkungslos)
- Die Umbrüche basierten auf der Template-Zeilenlänge, nicht auf der tatsächlichen PDF-Spaltenbreite

**Fix (implementiert):**

1. **`template_loader.dart` – `TemplateRenderer` erweitert:**
   - Neue Methode `_normalizeLineBreaks()`:
     - Einfache `\n` → Leerzeichen (Fließtext fließt dynamisch)
     - Leere Zeilen (`\n\n`) → Absatztrenner (bleiben erhalten)
     - Mehrfache Leerzeichen → einzelnes Leerzeichen
   - `render()` ruft `_normalizeLineBreaks()` nach der Platzhalter-Ersetzung auf

2. **`cover_letter_default.txt` überarbeitet:**
   - Feste Zeilenumbrüche entfernt – jeder Absatz ist jetzt eine einzige lange Zeile
   - 5 saubere Absätze statt 6 Zeilenblöcke
   - Der PDF-Renderer setzt die Zeilenumbrüche jetzt dynamisch (Blocksatz)

3. **`template_loader.dart` – Fallback-Template bereinigt:**
   - `_defaultCoverLetterTemplate` auf dieselbe neue Struktur umgestellt
   - Veraltete Absender/Empfänger-Daten entfernt (werden vom Generator gerendert)

## Bug Texte unvollständig oder falsch

Nach Einbettung von AI generierten Anschreiben, sind die Ergebnisse, welche wir zurückbekommen, un vollständigo der schlichtweg falsch. Als Beispiel:

"(...)
5: Formal closing (optional or combined with 4 to respect the 5-paragraph limit).* Keep it to 4 or 5
paragraphs.
**Refining Text to meet (...)"

oder 

"(...)

Sehr geehrte Damen und Herren,
mit großem Interesse bewerbe ich mich bei Bliq für die Position als Senior Flutter Developer und Client
Engineer. Als Diplom-Ingenieur fü

(...)"

Woran liegt das?

**Root Cause (gefunden):**

Die beiden Beispiele haben **zwei unterschiedliche Ursachen**, beide hängen mit dem KI-Anbieter Gemini (`gemini-3.5-flash`) zusammen:

**Beispiel 1 ("5: Formal closing ... **Refining Text to meet"):**
`gemini-3.5-flash` ist ein **Reasoning-Modell** – es denkt intern nach ("Gedankenkette"), bevor es antwortet. Die Gemini-API (`generateContent`) liefert diese internen Gedanken als zusätzliche **`thought`-Parts** in der Antwort (`parts[]` mit dem Flag `thought: true`). Der Parser in `gemini_cover_letter_ai_service.dart` sammelte bislang **alle** `text`-Felder ein – **auch die der Gedankenkette**. Dadurch landete die Modell-Planung ("Schritt 5: formeller Abschluss …") im Anschreiben.

**Beispiel 2 (Abbruch mitten im Wort "...Als Diplom-Ingenieur fü"):**
Die Antwort wurde **abgeschnitten**. Der `maxOutputTokens`-Wert lag bei nur **1024** – Reporting-Modelle brauchen für die Gedankenkette + die eigentliche Antwort mehr Token, sodass die sichtbare Antwort vorzeitig endete.

**Fix (implementiert):**

1. **`job_o_matic/lib/data/services/ai/gemini_cover_letter_ai_service.dart`**
   - `thinkingConfig: {'includeThoughts': false}` im `generationConfig` ergänzt → die Gedankenkette wird gar nicht erst angefordert.
   - `_extractText()` filtert zusätzlich Parts mit `thought: true` heraus → Defense-in-Depth, falls der Anbieter doch Thoughts liefert:
   ```dart
   return parts
       .where((p) => p is Map<String, dynamic> && p['thought'] != true)
       .map((p) => (p as Map<String, dynamic>)['text'] as String? ?? '')
       .join();
   ```

2. **`job_o_matic/lib/data/services/ai/cover_letter_prompt_builder.dart`**
   - `maxOutputTokens` von **1024 → 8192** erhöht, damit Reasoning-Modelle genug Spielraum für eine ungekürzte Antwort haben (die Länge wird weiterhin per Prompt auf ~350 Wörter begrenzt).

Problem bestand zunächst weiterhin – **zweiter, entscheidender Root Cause:**

Der schlechte KI-Text wurde **einmal pro Bewerbung in der Datenbank persistiert** (Spalte `cover_letter_text` in `applications`). `_ensureCoverLetterText()` in `job_repository.dart` brach bislang ab, **sobald Text vorhanden war** (`app.coverLetterText?.trim().isNotEmpty == true → return`). Dadurch wurden die **alten, korrupten Texte** bei jedem Neu-Generieren einfach wiederverwendet – die API-Fixes oben griffen nie, weil `generateCoverLetter()` gar nicht mehr aufgerufen wurde.

**Fix (ergänzt):**

1. **`job_o_matic/lib/data/services/ai/cover_letter_sanitizer.dart`**
   - Neue statische, testbare Heuristik **`isGarbage(String)`**: erkennt die beiden Fehlermuster
     - Reasoning-Gedankenkette (englische Meta-Planung wie „Formal closing", „5-paragraph limit", „Refining", nummerierte Planung `1: Opening`)
     - abgeschnittener Text (keine Grußformel „Mit freundlichen Grüßen", zu kurz, < 80 Zeichen)

2. **`job_o_matic/lib/data/repositories/job_repository.dart`**
   - `_ensureCoverLetterText()` ruft jetzt `CoverLetterSanitizer.isGarbage()` auf. Ist der persistierte Text korrupt, wird er **verworfen und neu generiert** (statt zu den alten, kaputten Texten zu bleiben):
   ```dart
   if (app == null) return;
   if (_hasValidCoverLetterText(app.coverLetterText)) {
     return; // sauber/manuell bearbeitet → beibehalten
   }
   // sonst: regulärer KI-Aufruf + saveCoverLetterText(…) (überschreibt)
   ```
   - Gültige (und manuell bearbeitete) Texte bleiben unangetastet.

Nach einer weiteren Testrunde neues Symptom: **Text bricht weiterhin mitten im Satz ab** („…Neben meinen technischen…" → Ende), aber jetzt als sauberes deutsches Anschreiben. Falsche Spur „Empfangsbuffer": Der Dart-`http`-Client liest den HTTP-Body **immer vollständig** in den Speicher – es gibt keinen begrenzten Empfangsbuffer, der erweitert werden müsste.

**Dritter Root Cause (erneutes Abschneiden):**

`gemini-3.5-flash` ist ein **Thinking-Modell**: Es verbraucht Token für die interne Gedankenkette UND den sichtbaren Text. `maxOutputTokens` begrenzt bei Gemini 2.5+/3.x die **SUMME aus Thinking- + Output-Tokens** (siehe ai.google.dev Thinking-Guide: „Control thinking budget … to save tokens"). Bei `maxOutputTokens: 8192` konnte die Gedankenkette den größten Teil aufbrauchen → der sichtbare Text endete vorzeitig, `finishReason: MAX_TOKENS`. Der Code speicherte den abgeschnittenen Text, weil `finishReason` nicht ausgewertet wurde.

**Fix (ergänzt, 3. und 4.):**

3. **`job_o_matic/lib/data/services/ai/cover_letter_prompt_builder.dart`**
   - `maxOutputTokens`: 8192 → **16384** (genug Gesamtbudget; die eigentliche Antwort braucht ~800 Token)
   - Neu: `thinkingBudget = 1024` – begrenzt die Gedankenkette (einfache Aufgabe → minimales Denken laut Google-Guide), sodass das Budget für den sichtbaren Text bleibt

4. **`job_o_matic/lib/data/services/ai/gemini_cover_letter_ai_service.dart` – Retry mit Budget-Eskalation (Hauptlösung):**
   Da die genauen Modell-Limits schwanken und sich die reale Modelltabelle ständig ändert, wird nicht mehr auf einen festen Wert vertraut. Der Service macht bis zu `maxAttempts = 3` Versuche: Bei `finishReason == MAX_TOKENS` (abgeschnittene Antwort) wird das Output-Budget schrittweise erhöht (`8192 → 16384 → 32768`), das Denk-Budget bleibt auf `thinkingBudget = 1024`:
   ```dart
   for (int attempt = 0; attempt < maxAttempts; attempt++) {
     final maxTokens = _outputBudgetForAttempt(attempt);  // steigend
     // … Request mit maxOutputTokens & vision thinkingConfig …
     if (_finishReason(body) == 'MAX_TOKENS') { continue; }  // erneut
     // sonst: validieren, sanitizen, speichern
   }
   throw lastError;  // nur wenn ALLE Versuche abgeschnitten waren
   ```
   - Nur eine **vollständige** Antwort (kein `MAX_TOKENS`) wird gespeichert
   - Erst wenn alle 3 Versuche abbrechen, wird an die Fallback-Kette (Mistral/Groq/Template) weitergereicht
   - `isGarbage`-Heuristik bleibt als Netzfänger für bereits persistierte abgeschnittene Texte

## Bug Zertifikate werden bei Generierung nicht angehängt

Was der Titel sagt. Die PDF Varianten der Zertifikate werden bei der Generierung nicht angehängt, sind aber nötig.

**Root Cause (gefunden):**

1. Das Datenmodell `Certificate` hatte **kein Feld für eine PDF-Datei**, und die YAML (`cv_data.yaml`) enthielt keine Dateipfade – die Zertifikats-PDFs lagen ausschließlich außerhalb des Projekts (`OneDrive\Dokumente\CV\`).
2. `PdfGenerator.generateApplicationPdf()` speicherte nur das generierte Dokument (Deckblatt + Anschreiben + Lebenslauf). Es gab **keinerlei Merge-Schritt** für externe PDFs – das `pdf`-Paket kann generieren, aber keine fremden PDFs einlesen/anhängen.

**Fix (implementiert):**

1. **`pubspec.yaml`**
   - Neues Package `pdf_combiner: ^6.2.1` (Windows via gebündeltem Google-PDFium, kein Setup nötig)
   - `share_plus`: ^9.0.0 → **^10.0.0** ( Dependency-Konflikt: pdf_combiner braucht `web ^1.0`, share_plus 9 pinnt `web ^0.5`)
2. **Zertifikats-PDFs ins Projekt kopiert:** `assets/mydata/cv/certificates/` (4 Dateien: Scrum Master I, Scrum Developer I, Scrum Product Owner I, Agile Leadership I) und in pubspec unter `assets:` registriert
3. **`assets/mydata/cv/cv_data.yaml`**: Jedes Zertifikat mit verfügbarer PDF hat jetzt `pdf: "assets/mydata/cv/certificates/…"`; das appAkademie-Zertifikat hat einen Kommentar „keine PDF-Datei verfügbar"
4. **`lib/models/cv_data.dart`**: `Certificate` um Feld `final String? pdfPath;` erweitert (inkl. Konstruktor + copyWith)
5. **`lib/data/services/cv_data_parser.dart`**: YAML-Feld `pdf` wird nach `pdfPath` geparst
6. **`lib/data/services/pdf/pdf_generator.dart`**
   - Neue Methode `_loadCertificatePdfBytes(CvData)`: lädt alle hinterlegten Zertifikats-PDFs via `rootBundle`; fehlende Assets werden mit Warnung übersprungen (Generierung scheitert nicht)
   - Speichern-Schritt: Sind Zertifikate vorhanden, werden sie via `PdfCombiner.mergeMultiplePDFs()` **an die Bewerbungs-PDF angehängt**; Logging: „($pageCount Seiten + N Zertifikat(e))"
   - Fehlschlag des Merges → Bewerbung wird ohne Anhänge gespeichert (Graceful Degradation)

**Wichtig zu wissen:**
- `MergeInput` wird vom Haupt-Export von pdf_combiner **nicht re-exportiert** → eigener Import `package:pdf_combiner/models/merge_input.dart` nötig.

## Bug Zertifikate, Teil 2

Unter "assets/mydata/cv/Matthias_Struck_zertifikate.pdf" liegen alle Zertifikate, welche ebenfalls im generierten Dokument enthalten sein sollen. Dazu zählen ein Zertifikat von der AppAkademie, meine Zertifikate über das Bestehen der Kurse für den PSPO, PSM, PSD und PAL, aber auch Zeugnisse und dergleichen. Bisher scheinen einige der darin enthaltenen Dokumente im Original zu fehlen. Bitte einfügen.

**Analyse der Sammel-PDF (16 Seiten):**

| Seiten | Inhalt | Status |
|--------|--------|--------|
| 1 | appAkademie-Abschlusszertifikat „Moderne Anwendungsentwicklung" | **fehlte komplett** → jetzt extrahiert |
| 2–5 | PSM I / PSD I / PSPO I / PAL I | Duplikate der bereits vorhandenen Einzelfiles → übersprungen |
| 6–16 | 11 Seiten Arbeitszeugnisse (gescannt, ohne Textebene) | **fehlten komplett** → jetzt als Sammeldokument extrahiert |

**Fix (implementiert):**

1. **Extraktion aus der Sammel-PDF** (`OneDrive\Dokumente\CV\Matthias_Struck-Zertifikate.pdf`, via pypdf):
   - `assets/mydata/cv/certificates/appAkademie_Abschlusszertifikat_Moderne_Anwendungsentwicklung.pdf` (Seite 1)
   - `assets/mydata/cv/certificates/Zeugnisse_Matthias_Struck.pdf` (Seiten 6–16 als ein Dokument)
   - Beide komprimiert (150 DPI / JPEG-Qualität 70% → appAkademie ~2 MB, Zeugnisse ~1,2 MB), damit die App-Größe klein bleibt
2. **`assets/mydata/cv/cv_data.yaml`**: Das appAkademie-Zertifikat hat jetzt ebenfalls einen `pdf:`-Pfad (statt des bisherigen „keine PDF verfügbar"-Kommentars); neues YAML-Feld `attachments:` mit dem Zeugnisse-Dokument
3. **`lib/models/cv_data.dart`**: `CvData` um Feld `final List<String> additionalAttachments;` erweitert (Konstruktor + toJson + fromJson + copyWith)
4. **`lib/data/services/cv_data_parser.dart`**: Neues YAML-Feld `attachments:` (Liste von Pfad-Strings) wird nach `additionalAttachments` geparst; Logging zählt sie mit
5. **`lib/data/services/pdf/pdf_generator.dart`**: `_loadCertificatePdfBytes()` lädt jetzt Zertifikats-PDFs **und** zusätzliche Anhänge; Reihenfolge im Export: Bewerbung → Zertifikate → Anhänge
6. **`pubspec.yaml`**: Ordner `assets/mydata/cv/certificates/` registriert

Ergebnis: Jede Bewerbungs-PDF enthält am Ende alle 5 Einzelzertifikate (inkl. appAkademie) plus das Zeugnisse-Dokument (11 Seiten).

## Bug Zertifikat AppAkademie

Bei der Generierung ist das Zertifikat von der AppAkademie, das direkt nach dem Lebenslauf, sehr viel zu groß im Vergleich zu allen anderen Seiten des PDF. Muss das so sein?

**Root Cause (gefunden):**

Nein, das muss nicht so sein. Die extrahierte appAkademie-Seite hatte ein **Seitenformat von 3735 × 5286 pt** – das ist der **6,3-fache A4-Maßstab** (A4 = 595,3 × 841,9 pt), vermutlich ein hochauflösender Scan mit übernommener Pixelgröße als Seitenformat. Der `PdfCombiner`-Merge übernimmt die Seitengrößen der angehängten PDFs **unverändert** (kein Rescaling), deshalb erschien die Seite im Bewerbungs-PDF riesig.

Zum Vergleich die übrigen Anhänge:
- Scrum-/PAL-Zertifikate: 792 × 612 pt (US-Letter, **Querformat** – so kommen sie von Scrum.org, beabsichtigt und ok)
- Zeugnisse: 596 × 842 pt (A4-Hochformat)

**Fix (implementiert):**

Die appAkademie-Seite wurde mit pypdf (`page.scale_by()`) auf **exakt A4-Hochformat (595,3 × 842,3 pt)** herunter skaliert (Faktor 0,1594). Die enthaltene Grafik bleibt in voller Auflösung erhalten – nur das Seitenformat wurde normalisiert, die Dateigröße bleibt ~1,95 MB. Keine Code-Änderung nötig; beim nächsten Generieren erscheint die Seite in einheitlicher Größe.

**Verifikation:**
- Neue Seitenmaße geprüft: 595,3 × 842,3 pt (A4), 1 Seite
- Alle 109 Tests bestanden, `dart analyze lib` ohne Fehler (nur vorbestehende Info-Lints)

**Verifikation:**
- Alle Tests bestanden, `dart analyze lib` ohne Fehler (nur vorbestehende Info-Lints)

**Verifikation (frühere Fixes):**
- 5 Unit-Tests für `CoverLetterSanitizer.isGarbage` in `test/services/ai/cover_letter_sanitizer_test.dart`
- 4 Gemini-Tests angepasst/ergänzt: thinkingConfig mit `thinkingBudget` + erstem `maxOutputTokens`, neuer Retry-Test „erhöht Output-Budget bei MAX_TOKENS und liefert vollständige Antwort beim nächsten Versuch", Test „bricht bei finishReason MAX_TOKENS ab"
- Alle 109 Tests bestanden, `dart analyze` ohne Issues.

### Bug Anschreibengenerierung
Ich habe festgestellt, dass in den generierten Anschreiben hin und wieder Texte auftauchen, die da nicht hingehören. Beispiel aus "/assets/mydata/1_Bliq.md":
"(...)
Sehr geehrte Damen und Herren,
mit großem Interesse habe ich Ihre Stellenausschreibung für die Position als Senior Flutter Developer / Client Engineer, AI-Native and Rust-Friendly (m/f/d) bei der Bliq gelesen. With Bliq our vision is to build a Neo-OEM that is turning existing cars into driverless vehicles that can be used by everyone. Our company operates vertically integrated across hardware, software, electronics, operations to put driverless cars on real roads.
(...)"
Ein Teil des Absatzes sieht aus wie ein Teil dero originalen Jobbeschreibung. Woher kommt das? 
**Root Cause (gefunden):**

Das Anschreiben in `/assets/mydata/1_Bliq.pdf` stammt **nicht von der KI**, sondern von der **Template-Generierung** (`cover_letter_default.txt` → `TemplateRenderer` + `PdfGenerator`). Dieser Pfad wird genutzt, wenn die KI-Anschreiben deaktiviert sind oder alle Anbieter fehlschlagen (Template-Fallback).

Das Template enthielt im ersten Absatz den Platzhalter `{{job_description_excerpt}}`:

> „mit großem Interesse habe ich Ihre Stellenausschreibung für die Position als {{jobTitle}} bei der {{company}} gelesen. **{{job_description_excerpt}}**"

`PdfGenerator._extractDescriptionExcerpt()` kopierte die **ersten zwei Sätze der gescrapten Stellenbeschreibung wörtlich** in den Brief. Bei Bliq begann die gescrapte Anzeige mit der (englischen) Firmen-Vorstellung „With Bliq our vision is to build a Neo-OEM …", daher landet dieses Marketing-Blau gerade im deutschen Anschreiben.

Zusätzlicher Effekt (erklärt das „hin und wieder"): Auch die **KI-Generierung** bekommt die komplette Anzeige im Prompt (`<stellenanzeige>`-Block) – LLMs zitieren Anzeigen-Sätze gerne 1:1. Template-Pfad = deterministisch, KI-Antwort = variabel. Beide Wege wurden deshalb abgesichert.

**Fix (implementiert):**

1. **`assets/mydata/vorlagen/cover_letter_default.txt`** – `{{job_description_excerpt}}` aus dem ersten Absatz entfernt. Der Eröffnungssatz ist jetzt sauber und generisch; die Individualisierung übernimmt die KI.
2. **`lib/data/services/pdf/template_loader.dart`** – Fallback-Template (`_defaultCoverLetterTemplate`) auf die neue, saubere Struktur umgestellt.
3. **`lib/data/services/ai/cover_letter_sanitizer.dart`** – Neue statische Methode **`removeJobDescriptionQuotes(text, jobDescription)`**: verwirft jeden Satz, der **wörtlich** (normalisiert: lowercase, Leerraum zusammengefasst) in der Stellenbeschreibung vorkommt und länger als `minQuoteLength` (25 Zeichen) ist. Die Absatzstruktur (`\n\n`) bleibt erhalten – DIN-5008-konform.
4. **`lib/data/services/pdf/pdf_generator.dart`** – Der finale Anschreiben-Text (KI **und** Template) wird vor dem Rendern durch `removeJobDescriptionQuotes` bereinigt. Dadurch werden auch **bereits persistierte**, alte Anschreiben beim nächsten PDF-Export bereinigt – ohne dass die DB geändert werden müsste.
5. **`lib/data/repositories/job_repository.dart`** – `_ensureCoverLetterText()` bereinigt den KI-Text vor dem Speichern in der DB, damit Vorschau/Editor und PDF auf identischem, sauberem Text basieren.

### Bug Zwischenfrage
Auf dem Deckblatt taucht das Datum unten rechts auf. Ist das DIN ISO 5008 konform?

**Antwort (Analyse):**

Nein–doch: DIN 5008 unterscheidet zwei Aspekte:
- **Format**: Yes — `TT.MM.JJJJ` (z.B. `31.08.2026`), numerisch mit Punkt und vierstelliger Jahreszahl, ist exakt die DIN-5008-Schreibweise.

- **Position**: Regelt DIN 5008 nur **im Brief** (DIN 676: rechts oben auf Höhe des Empfängerblocks) — ein **Deckblatt ist kein Brief**, dafür gibt es keine Position-Vorgabe. Rechts unten ist gängige Praxis und zulässig. Das Projekt hat das Deckblatt-Datum bewusst auf `Alignment.centerRight` gestellt (siehe `12-DIN5008.md` Zeile 19/37–39).

**Umsetzung (Option 2, auf Wunsch des Nutzers):**

Die in DIN 5008 dokumentierte Orts-Schreibweise **„Ort, den TT.MM.JJJJ"** wird jetzt verwendet:
1. **`lib/data/services/pdf/pdf_utils.dart`** – Neue statische Helperfunktion **`extractCityFromAddress(String? address)`**: extrahiert die Stadt aus der deutschen Adresse (Muster „…PLZ Ort", z.B. `Glacisweg 9,13583 Berlin` → `Berlin`; `null` bei fehlender PLZ).
2. **`lib/data/services/pdf/cover_page_generator.dart`** – Datumszeile: `Datum: 31.08.2026` ersetzt durch **`Berlin, den 31.08.2026`** (Ort aus `personalData.address` abgeleitet; Fallback ohne Ortsangabe: nacktes Datum `31.08.2026`). Das `Datum:`-Label ist damit entfernt – reine DIN-5008-Schreibweise.- Rechtsbündig bleibt es weiterhin.

**Verifikation:**
- 3 neue Unit-Tests für `extractCityFromAddress` in `test/services/pdf/pdf_utils_test.dart`: „Glacisweg 9,13583 Berlin" → „Berlin"Musterstraße-Variante, nachgestelltes Komma; sowie `null` bei null/leer/ohne PLZ/PLZ-ohne-Ort.

- **Verifikation (frühere Fixes):**
- 6 neue Unit-Tests für `removeJobDescriptionQuotes`: wörtliche Zitate, beide Zitate (Template-Excerpt-Fall), eigene Formulierungen bleiben erhalten, kurze Allerwelts-Sätze trotz Treffer, Groß-/Kleinschreibung + Leerraum, leere/null-Stellenbeschreibung
- Alle **115 Tests** bestanden, `dart analyze` (geänderte Dateien) ohne Issues.

### Anfrage KI-generierung von ANschreiben
Ich habe irgendwie das Gefühl, dass Anschreiben, trotz eingeschalteter Option, nicht immer von der KI generiert werden. Ist das so oder irre ich mich?

**Antwort (Analyse): Berechtigter Verdacht – die Option heißt „KI wird versucht", nicht „KI wird garantiert verwendet".**

Die Kette in `JobRepository.generatePdf()` → `_ensureCoverLetterText()` zeigt vier Fälle, in denen ein Anschreiben trotz eingeschalteter KI-Option **nicht** von der KI stammt:

1. **Stiller Template-Fallback nach Fehlschlag (häufigster Fall):** Sind für alle drei Anbieter (Gemini → Mistral → Groq) keine gültigen API-Keys hinterlegt bzw. schlagen sie fehl (Kontingent, Netzwerk), wirft der `FallbackCoverLetterAiService` eine `CoverLetterAiException`. `_ensureCoverLetterText()` fängt sie ab und generiert **keinen Text** – die PDF wird still mit der Vorlage (`cover_letter_default.txt`) erzeugt. **Es gibt keinen UI-Hinweis**; nur ein Log-Warnung.

2. **Schon vorhandener Text wird wiederverwendet („einmal pro Bewerbung"):** Existiert bereits ein gespeicherter, nicht als Müll erkannter `coverLetterText` (z. B. aus einer früheren Generierung oder manueller Bearbeitung), bricht `_ensureCoverLetterText()` ab – **die KI wird gar nicht erst gefragt**. Auch „Erneut generieren" ändert daran nichts, denn `resetToQueued()` löscht `coverLetterText` nicht.

3. **Manuell bearbeitete Texte** werden absichtlich nie überschrieben (`_hasValidCoverLetterText` → beibehalten).

4. **KI deaktiviert / Service null:** Ohne `ki_anschreiben`-Flag bzw. ohne injizierten Service wird immer die Vorlage verwendet.

Ein gespeicherter Text ist außerdem **nicht zwingend ein KI-Text**: Vor der KI-Phase gab es die Spalte nicht (alte Bewerbungen → `null`), aber auch ein einmal von der KI erzeugter Text bleibt danach unverändert erhalten – selbst wenn die KI-Einstellung später geändert oder der Code korrigiert wird.

**Unterscheidungsmerkmal in der Praxis:** KI-Briefe formulieren individuell pro Stelle (variieren stark); Vorlagen-Briefe sind fast wörtlich identisch und enthalten Sätze wie „Ich verfüge über {{experience_years}} Berufserfahrung…". Das Beispiel `/assets/mydata/1_Bliq.pdf` (mit dem englischen Bliq-Slogan) stammte aus dem Vorlagen-Pfad.

**Fix (implementiert):**

1. **`lib/data/repositories/job_repository.dart`** – Neue Methode **`regenerateCoverLetterWithAi(int applicationId)`**: erzwingt eine sofortige KI-Neugenerierung (Fallback-Kette + Quote-Bereinigung), überschreibt den persistierten Text in der DB und gibt den neuen Text zurück. Wirft `CoverLetterAiException`, wenn alle Anbieter scheitern oder die KI deaktiviert ist.
2. **`lib/presentation/screens/application_detail_screen.dart`** – Neuer Button **„Mit KI neu generieren"** in der Anschreiben-Karte (sichtbar, wenn `kiAnschreibenEnabled`): befragt die KI sofort, speichert den Text und zeigt Erfolg/Fehler als Snackbar (mit Variantes falls kein Key o. Ä.). Zusätzlich transparenter Hint-Text, wenn noch kein Text existiert („wird die KI versucht; schlägt sie fehl, wird automatisch die Vorlage verwendet").
3. **Hinweis für die Bedienung:** Nach dem Button muss die PDF neu generiert werden, damit der neue Text in der Datei landet.

**Verifikation:**
- `dart analyze` (geänderte Dateien) ohne Issues; vollständige Test-Suite läuft grün (117 Tests). Der Button ist standardmäßig verborgen (KI aus) – Widget-Tests unberührt.