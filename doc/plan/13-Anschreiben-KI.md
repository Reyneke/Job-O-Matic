# Anschreiben mit KI generieren

## Ausgangsüberlegung

Das Anschreiben soll dynamisch durch eine KI generiert werden, um es passend zum jeweiligen Jobangebot zu formulieren – statt nur statische Platzhalter (`{{jobTitle}}`, `{{company}}`, …) in der Vorlage `cover_letter_default.txt` zu ersetzen.

**Wichtige Korrektur der ursprünglichen Idee:** Das Anschreiben sollte **nicht bei jedem Aufruf neu** generiert werden, sondern **einmal pro Bewerbung** erzeugt und anschließend persistiert werden (z. B. in der SQLite-Datenbank neben dem Status des Jobs). Gründe:

- **Konsistenz:** Ein LLM liefert bei jedem Aufruf andere Ergebnisse. Der Nutzer muss später immer dasselbe Anschreiben sehen wie im PDF.
- **Kosten:** Regenerierung bei jedem Aufruf verbraucht unnötig das kostenlose Kontingent der Anbieter.
- **Reproduzierbarkeit:** PDF-Generierung und Vorschau müssen auf identischem Text basieren.

---

## Anforderungen

| Kriterium | Anforderung |
|-----------|-------------|
| **Kosten** | Möglichst kostenlos (Free-Tier reicht für den persönlichen Gebrauch) |
| **Sprache** | Hochwertiges Deutsch (Anschreiben sind auf Deutsch) |
| **DSGVO** | Persönliche Daten (Name, Adresse, Werdegang) dürfen nur an Anbieter mit datenschutzkonformer Verarbeitung übermittelt werden |
| **Integration** | Einfache REST-Anbindung aus Dart (`http`-Paket ist bereits vorhanden) |
| **Fallback** | Bei Ausfall/Kontingent-Erschöpfung: Rückfall auf die bestehende Template-basierte Generierung |
| **Fakten-Treue** | Die KI darf keine Fakten erfinden – ausschließlich Inhalte aus `cv_data.yaml` und dem Stellenangebot verwenden |

---

## Optionen im Vergleich

### Cloud-Anbieter (mit Free-Tier)

| Anbieter | Modelle (kostenlos) | Free-Tier-Limit | Deutsch-Qualität | DSGVO | Bemerkung |
|----------|--------------------|-----------------|------------------|-------|-----------|
| **Google Gemini API** | Gemini 3.5 Flash | Großzügig (Requests/Minute + Requests/Tag kostenlos) | ✅ Sehr gut | ⚠️ Verarbeitung auch außerhalb EU möglich | ⭐ Beste Gratis-Kombination aus Qualität und Kontingent; EU-Rechenzentren wählbar |
| **Groq** | Llama 3.3 70B, u. a. | Kostenloses Kontingent mit Tageslimit | ✅ Gut | ⚠️ US-Anbieter | ⭐ Extrem schnell (LPUs), offene Modelle |
| **Mistral La Plateforme** | Mistral Small/Large | Kostenloser Tier nach Registrierung | ✅ Sehr gut (stark in EU-Sprachen) | ✅ EU-Firma (Frankreich) | ⭐ Datenschutzfreundlichste Cloud-Option |
| **Cerebras** | Llama-Modelle | Kostenloses Kontingent | ✅ Gut | ⚠️ US-Anbieter | Sehr hohe Geschwindigkeit |
| **OpenRouter** | Verschiedene `:free`-Modelle | Tageslimit für Free-Modelle | Je nach Modell | ⚠️ Router zwischen vielen Anbietern | Praktisch zum Experimentieren, nicht als Primärquelle |
| **GitHub Models** | GPT-4o-mini, Llama, Mistral u. a. | Kostenloses Kontingent (Rate-Limits) | ✅ Gut | ⚠️ | Gut zum Prototypen, Limits für Produktion knapp |

### Ohne Free-Tier (nur kostenpflichtig)

| Anbieter | Bemerkung |
|----------|-----------|
| OpenAI (GPT-4o etc.) | Beste Qualität, aber ab ~0,005 $/Anschreiben; keine kostenlose Nutzung |
| Anthropic (Claude) | Sehr gute Texte, ebenfalls nur bezahlt |

### Lokale Modelle (völlig kostenlos, DSGVO-freundlich)

| Variante | Bemerkung |
|----------|-----------|
| **Ollama / llama.cpp auf dem eigenen PC** | Modelle wie `llama3.3`, `gemma3`, `mistral` (7–14B) laufen auf normaler Hardware. Ollama bietet eine lokale REST-API (`http://localhost:11434`) → gleiche Integration wie Cloud, aber **keine Daten verlassen den Rechner**. Da Job-O-Matic eine Desktop-/Windows-App ist, realistisch machbar – **aber mit Einschränkungen auf leistungsschwachen PCs** (siehe [Offene Fragen](#offene-fragen--antworten)). |

---

## Empfehlung

**Strategie: Abstraktion + Primäranbieter + Fallback**

1. **Primär:** Google Gemini API (bestes Preis-Leistungs-Verhältnis im Free-Tier, sehr gutes Deutsch).
2. **Alternative:** Mistral (EU-Anbieter, wenn DSGVO-Priorität höchste ist) oder lokales Ollama (null Kosten, null Datenabfluss, aber schlechtere Qualität und Setup-Aufwand).
3. **Fallback:** Bestehende Template-Generierung über `TemplateRenderer` – falls API fehlschlägt oder das Kontingent erschöpft ist.

### Architektur-Entwurf

```dart
/// Abstrakte Schnittstelle – konkrete Anbieter sind austauschbar.
abstract class CoverLetterAiService {
  /// Erzeugt ein Stellen-spezifisches Anschreiben.
  Future<String> generateCoverLetter({
    required CvData cvData,
    required Application application, // vorhandenes Bewerbungs-Modell
  });
}

class GeminiCoverLetterAiService implements CoverLetterAiService { ... }
class OllamaCoverLetterAiService implements CoverLetterAiService { ... }
```

- Neuer Service unter `lib/data/services/ai/` (analog zur Struktur von `lib/data/services/api/`).
- API-Key-Speicherung über den bereits vorhandenen `ApiKeyService` bzw. die `ApiKeySettingsScreen`.
- Aufrufort: `JobRepository.generateApplicationPdf()` – das Anschreiben wird vor der PDF-Erzeugung generiert und in der DB gespeichert.
- Der Prompt enthält: strukturierte CV-Daten, Stellenbeschreibung (aus Scraper/API), DIN-5008-Vorgaben (Absätze statt fester Zeilenumbrüche, siehe `12-DIN5008.md`) und die harte Regel **"Erfinde keine Fakten"**.

---

## Risiken

| Risiko | Gegenmaßnahme |
|--------|---------------|
| **Halluzinationen** (erfundene Qualifikationen/Erfahrungen) | Prompt-Regel "nur CV-Daten verwenden"; Stichproben-Review durch den Nutzer vor dem Versand |
| **Datenschutz/DSGVO** | Anbieter mit EU-Verarbeitung wählen oder lokales Modell; nur so viele persönliche Daten wie nötig in den Prompt |
| **Prompt-Injection** aus gescrapeten Stellenanzeigen | Stellenanzeige klar als Daten (nicht als Instruktion) kennzeichnen, z. B. XML-Tags im Prompt |
| **Kontingent erschöpft / API-Ausfall** | Automatischer Fallback auf die Template-Generierung |
| **Nicht DIN-5008-konforme Textstruktur** | Nachbearbeitung: Absatzerhaltung, Zeilenumbruch-Normalisierung (nutzt `_normalizeLineBreaks()` aus `template_loader.dart`); Markdown-Auszeichnungen (`**fett**`, Listen, Überschriften) aus der KI-Antwort strippen; Längenbegrenzung im Prompt (max. ~5 Absätze) |
| **Layout-Zerstörung durch KI-Output** (z. B. zu langer Text → Überlauf auf Seite 2) | KI liefert **nur reinen Fließtext** – Layout bleibt vollständig in den PDF-Generatoren; Länge im Prompt begrenzen und in der App validieren; bestehende DIN-5008-Tests erweitern |
| **API-Änderungen (Breaking Changes)** | Versionierte Endpunkte, Integrationstest gegen reale API |

---

## Nächste Schritte

### Phase 1: Grundlage ✅
- [x] **Interface `CoverLetterAiService` definieren** – Entkoppelung von konkreten Anbietern ✅ (`lib/data/services/ai/cover_letter_ai_service.dart`; nutzt das vorhandene `Application`-Modell statt `JobOffer`, da zur Generierungszeit im `JobRepository` nur `Application` verfügbar ist; inkl. `CoverLetterAiException` und Vertrag "nur reiner Fließtext")
- [x] **API-Key-Management erweitern** – Gemini-Key über `ApiKeyService.geminiApiKey` verwalbar, Eingabefeld in der `ApiKeySettingsScreen` ergänzt ✅
- [x] **Persistenz klären** – Neue Spalte `cover_letter_text` in `applications` (DB-Migration auf Version 6), Feld in `Application`, Konverter in `DatabaseRepository`, sowie `saveCoverLetterText()` / `getCoverLetterText()` im `JobRepository` ✅ (Unit-Tests: 12 neue Tests, alle 55 bestanden)

### Phase 2: Erster Anbieter ✅
- [x] **`GeminiCoverLetterAiService` implementieren** – REST-Aufruf via `http`/`ApiClient` (Retry mit Backoff), Timeout 90 s (LLM-Antworten brauchen länger als klassische REST-Calls) ✅
- [x] **Prompt entwickelt** – CV-Daten + Stellenbeschreibung (klar als `<stellenanzeige>`-Daten markiert gegen Prompt-Injection) + harte Regeln: "Erfinde KEINE Fakten", nur Fließtext, max. 5 Absätze, 250–350 Wörter (eine Din-A4-Seite), Anrede/Grußformel inklusive ✅
- [x] **Unit-Tests** – Request-Building und Response-Parsing mit `MockClient` (valide Antwort, HTTP 500, fehlender Key, leere candidates, zu kurze Antwort, Markdown-Antwort) ✅
- [x] **Output-Sanitizing** – `CoverLetterSanitizer` (`cover_letter_sanitizer.dart`): stript Markdown (fett/kursiv/code/Überschriften/Bullets/Nummerierung), entfernt Emojis, normalisiert Absätze, begrenzt auf max. 6 Absätze ✅
- **Neu:** Provider `geminiCoverLetterAiServiceProvider` + `coverLetterAiServiceProvider` in `providers.dart` registriert; `ApiClient.keyService` ist jetzt optional (rückwärtskompatibel)
- **Verifikation:** Alle 75 Tests bestanden, Analyzer ohne neue Issues

### Phase 3: Fallback & UX ✅
- [x] **Prompt-Builder extrahiert** – `CoverLetterPromptBuilder` (`cover_letter_prompt_builder.dart`): gemeinsamer, getesteter Prompt für alle Anbieter; Gemini-Service darauf umgestellt (~30 min wie geplant) ✅
- [x] **Fallback-Kette aufgebaut** – `FallbackCoverLetterAiService`: probiert die Kette der Reihe nach durch, sammelt Fehler, wirft erst wenn ALLE fehlschlagen; `coverLetterAiServiceProvider` liefert jetzt **Gemini → Mistral → Groq**, danach greift der Template-Fallback des Aufrufers ✅
- [x] **`MistralCoverLetterAiService`** – OpenAI-kompatible API (`api.mistral.ai/v1/chat/completions`, Standardmodell `mistral-small-latest`) über gemeinsame Basisklasse `OpenAiCompatibleCoverLetterAiService`; EU-Anbieter ✅
- [x] **`GroqCoverLetterAiService`** – identisches Schema (`api.groq.com/openai/v1/chat/completions`, Standardmodell `llama-3.3-70b-versatile`) – nur ~20 Zeilen Eigencode dank Basisklasse ✅
- [x] **API-Keys erweitert** – `mistralApiKey` + `groqApiKey` in `ApiKeyService`, Eingabefelder in der Settings-Screen ✅
- [x] **UI-Option umgesetzt** – Schalter "KI-Anschreiben" in der API-Key-Verwaltung (persistiert via DB-Filter `ki_anschreiben`, Standard: aus); **Verdrahtung**: `generatePdf()` ruft bei aktivierter KI einmalig pro Bewerbung die Fallback-Kette auf und speichert den Text via `saveCoverLetterText()`; schlägt sie fehl, wird das PDF mit dem Template-Anschreiben erzeugt; `PdfGenerator.generateApplicationPdf()` akzeptiert optionalen `coverLetterText` als Override ✅
- [x] **Anschreiben-Editor umgesetzt** – Karte "Anschreiben" in der Detail-Ansicht: zeigt den gespeicherten Text (Vorschau, 12 Zeilen), Bearbeiten-Dialog speichert Änderungen zurück in die DB; manuelle Korrekturen ohne KI-Neugenerierung ✅
- **Verifikation:** Alle 94 Tests bestanden, Analyzer ohne neue Issues

### Phase 4 (optional): Lokale Variante
- [ ] **`OllamaCoverLetterAiService`** – für maximalen Datenschutz und Null-Kosten-Betrieb
- [ ] **Hardware-Check** – vor Aktivierung prüfen, ob der PC genug RAM hat; sonst Hinweis auf Cloud-/Template-Fallback

---

## Offene Fragen & Antworten

### Funktioniert Ollama auch auf leistungsschwachen PCs?

**Teilweise – es hängt von RAM und GPU ab, nicht von der Internetleitung** (Ollama läuft lokal, es wird keine Bandbreite benötigt):

| Hardware | Machbare Modelle | Qualität für dt. Anschreiben |
|----------|------------------|------------------------------|
| ≥ 16 GB RAM + dedizierte GPU (≥ 8 GB VRAM) | 7–14B-Modelle (z. B. `llama3.3:8b`, `gemma3:12b`) | Gut bis sehr gut |
| 8–16 GB RAM, nur CPU/iGPU | Kleine Modelle (z. B. `gemma3:4b`, `qwen2.5:3b`, quantisiert `Q4_K_M`) | Brauchbar, aber spürbar schwächer; Generierung dauert ggf. 30–120 s pro Brief |
| < 8 GB RAM | Praktisch nicht sinnvoll | ❌ Empfehlung: Cloud-Anbieter oder Template-Fallback nutzen |

**Konsequenz für Job-O-Matic:** Ollama bleibt bewusst **Phase 4 (optional)**. Die App sollte vor der Nutzung prüfen, ob genug RAM vorhanden ist, und dem Nutzer sonst den Cloud-Anbieter bzw. den Template-Fallback empfehlen.

### Wurde das Speichern der Briefe als Vorlage in der DB berücksichtigt?

**Ja.** Genau das ist der Kern der "Wichtigen Korrektur der ursprünglichen Idee" (siehe oben): Jedes Anschreiben wird **einmal pro Bewerbung generiert und in der SQLite-Datenbank persistiert** – verankert in:

- **Phase 1 → "Persistenz klären":** Generiertes Anschreiben wird pro Bewerbung gespeichert, kein Regenerieren bei jedem Aufruf.
- **Phase 3 → "Anschreiben-Editor":** Der Nutzer kann den gespeicherten Brief anschließend manuell nachbessern (kleine Änderungen), ohne die KI erneut zu befragen.

Damit ist genau der gewünschte Workflow abgedeckt: einmal generieren → speichern → bei Bedarf nur kleine manuelle Änderungen statt kompletter Neugenerierung. Eine darüber hinausgehende **Wiederverwendung als allgemeine Vorlage für mehrere ähnliche Jobs** (z. B. "dieses Anschreiben als Basis für einen anderen Job nutzen") ist derzeit nicht geplant und kann bei Bedarf als eigene Phase ergänzt werden.

### Sind unsere Anschreiben auch weiterhin DIN 5008 kompatibel?

**Ja – weil die KI nur den Inhalt liefert, nicht die Form.** Die Aufgabenteilung bleibt strikt:

| Bereich | Zuständig | DIN-5008-Relevanz |
|---------|-----------|-------------------|
| **Formales Layout** (Absender, Empfängerblock, Datum `TT.MM.JJJJ`, Betreff fett, Seitenränder 25/20 mm, Grußformel linksbündig, Fußzeile ab Seite 2) | `cover_letter_generator.dart` + `PdfUtils` (Ergebnisse aus `12-DIN5008.md`) | ✅ Unverändert vom KI-Text unabhängig |
| **Fließtext** (Inhalt der Absätze) | KI bzw. Template-Fallback | Wird nachbearbeitet: `_normalizeLineBreaks()` sorgt für Absatztrennung statt fester Zeilenumbrüche; der PDF-Renderer setzt Blocksatz |

Die KI erhält im Prompt explizit die Vorgabe "nur Fließtext in Absätzen, keine Listen, keine Überschriften, keine Formatierung". Zusätzlich stript das Output-Sanitizing (Phase 2) etwaige Markdown-Reste (`**fett**`, `# Überschriften`, Bullet-Points), bevor der Text an den Generator übergeben wird.

**Restrisiko:** Die KI könnte untypische Strukturen erzeugen (z. B. Aufzählungen statt Fließtext). Gegenmaßnahme: Prompt-Regeln + Sanitizing + stichprobenartige Sichtprüfung der generierten PDFs gegen die Checkliste aus `12-DIN5008.md`.

### Wie hoch ist die Gefahr, dass generierte Anschreiben das Design zerstören?

**Gering – wenn die geplante Architektur eingehalten wird.** Der Grund ist dieselbe Trennung wie bei DIN 5008: Das Design (Schrift, Farben, Ränder, Layout) lebt vollständig in den PDF-Generatoren (`pdf_utils.dart`, `cover_letter_generator.dart`) und den Vorlagen. Die KI-Antwort ist und bleibt **plain text**, der an derselben Stelle landet wie heute der gerenderte Template-Text.

Verbleibende konkrete Gefahren und ihre Eindämmung:

| Mögliche Störung | Wahrscheinlichkeit | Gegenmaßnahme |
|------------------|--------------------|---------------|
| Markdown-/Formatierungsreste im Text | Mittel (LLMs neigen dazu) | Output-Sanitizing (Phase 2): Strippen von `*`, `#`, `-` am Absatzanfang etc. |
| Zu langer Text → Anschreiben läuft auf Seite 2 über (Anschreiben sollte eine Seite bleiben) | Mittel | Längenbegrenzung im Prompt (~5 Absätze); Validierung in der App mit Warnung an den Nutzer; ggf. automatisches Kürzen |
| Ungewollte Sonderzeichen / Emojis | Niedrig | Sanitizing + Prompt-Regel "keine Emojis, keine Sonderzeichen" |
| Kaputter Text bei API-Störung (abgebrochene Antwort) | Niedrig | Retry analog `ApiClient`; bei leerem/zu kurzem Ergebnis Fallback auf Template-Generierung |

**Fazit:** Das Design kann durch die KI nicht direkt zerstört werden, da sie keinen Einfluss auf das Rendering hat. Die realen Risiken (Textlänge, Formatierungsreste) werden durch Prompt-Regeln, Sanitizing und Validierung abgedeckt – beides ist als fester Bestandteil von Phase 2 eingeplant.

### Wie groß wäre der Aufwand, Mistral und Groq (in dieser Reihenfolge) als Alternativen einzubinden, falls Gemini unerreichbar ist?

**Kurz: Gering – ca. 0,5–1 Tag für beide Anbieter zusammen** (je Anbieter ~1–2 Stunden inkl. Tests). Der Grund: Phase 1+2 haben genau die Struktur geschaffen, die solche Erweiterungen billig macht.

| Arbeitsschritt pro Anbieter | Aufwand | Bemerkung |
|----------------------------|---------|-----------|
| Neue Service-Klasse (`MistralCoverLetterAiService` / `GroqCoverLetterAiService`) | ~30–45 min | Implementiert das vorhandene Interface; beide Anbieter bieten **OpenAI-kompatible Chat-APIs**, daher fast identischer Code |
| API-Key-Konstante + Feld in der Settings-Screen | ~15 min | Analog zum Gemini-Key aus Phase 1 (Label, Beschreibung, Icon) |
| Unit-Tests mit `MockClient` | ~20–30 min | Gleiche Teststruktur wie bei Gemini (valide Antwort, HTTP-Fehler, fehlender Key) |
| Provider-Registrierung + Fallback-Kette | ~15 min | In `providers.dart`; gehört eigentlich zu Phase 3 |

**Warum so einfach?**

1. **Schnittstelle existiert:** Beide Services implementieren nur `CoverLetterAiService` – Aufrufer merken keinen Unterschied.
2. **OpenAI-kompatible APIs:**
   - **Mistral:** `POST https://api.mistral.ai/v1/chat/completions`, Body `{model, messages, temperature, max_tokens}`, Antwort `choices[0].message.content`
   - **Groq:** `POST https://api.groq.com/openai/v1/chat/completions` – identisches Schema, nur andere Domain/Modelle (z. B. `llama-3.3-70b-versatile`)
   - Beide sind also strukturell **einfacher als Gemini** (dessen `candidates/parts`-Format eigenes Parsing brauchte).
3. **Prompt & Sanitizing wiederverwendbar:** Der Prompt-Builder sollte vorab (~30 min) aus dem Gemini-Service in einen gemeinsamen Helper (z. B. `CoverLetterPromptBuilder`) extrahiert werden – danach nutzen alle drei Anbieter denselben getesteten Prompt. Der `CoverLetterSanitizer` wird unverändert übernommen.
4. **Testinfrastruktur steht:** `MockClient`-Muster, Sample-Daten und Exception-Tests können kopiert und angepasst werden.

**Empfohlene Reihenfolge passt:** Erst Mistral (EU-Anbieter, DSGVO-freundlich), dann Groq (extrem schnell, offene Modelle). Als letzte Stufe bleibt der Template-Fallback ohne KI – die Kette wäre also: **Gemini → Mistral → Groq → Template**.

**Vorschlag zur Einordnung:** Nicht als eigene Phase, sondern als Teil von **Phase 3 (Fallback & UX)** einplanen – dort entsteht ohnehin die Fallback-Kette, an die die beiden Anbieter einfach angehängt werden. Vorab-Empfehlung: erst den kleinen Refactor (Prompt-Builder extrahieren), damit nicht drei Kopien des Prompts entstehen.

=> Okay, dann machen wir es so.