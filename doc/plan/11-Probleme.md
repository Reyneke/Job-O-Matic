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