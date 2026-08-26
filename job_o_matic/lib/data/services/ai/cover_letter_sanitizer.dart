/// Bereinigt KI-generierte Anschreiben-Texte (Output-Sanitizing).
///
/// Stellt sicher, dass die Antwort eines LLM dem Vertrag aus
/// `cover_letter_ai_service.dart` entspricht:
/// - Kein Markdown (`**fett**`, `*kursiv*`, `` `Code` ``, Überschriften)
/// - Keine Listen (Bullets, Nummerierungen)
/// - Keine Emojis
/// - Saubere Absatzstruktur (Leerzeile zwischen Absätzen)
/// - Begrenzte Länge (~max. [maxParagraphs] Absätze, damit das Anschreiben
///   auf einer Seite bleibt – siehe doc/plan/13-Anschreiben-KI.md)
class CoverLetterSanitizer {
  CoverLetterSanitizer._();

  /// Maximale Anzahl von Absätzen im fertigen Anschreiben.
  static const int maxParagraphs = 6;

  /// Bereinigt den Rohtext des LLM und liefert reinen Fließtext zurück.
  ///
  /// Gibt einen leeren String zurück, wenn nichts Brauchbares übrig bleibt.
  static String sanitize(String raw, {int maxParagraphs = maxParagraphs}) {
    var text = raw.replaceAll('\r\n', '\n');

    // Markdown-Auszeichnungen entfernen (Inhalt behalten)
    text = text.replaceAllMapped(
      RegExp(r'\*\*(.+?)\*\*', dotAll: true),
      (m) => m.group(1)!,
    );
    text = text.replaceAllMapped(
      RegExp(r'__(.+?)__', dotAll: true),
      (m) => m.group(1)!,
    );
    text = text.replaceAllMapped(
      RegExp(r'(?<!\*)\*([^*\n]+)\*(?!\*)'),
      (m) => m.group(1)!,
    );
    text = text.replaceAll('`', '');

    // Zeilenweise bereinigen: Überschriften-Marker und Listen-Bullets strippen
    final lines = text.split('\n').map((line) {
      var l = line.trim();
      l = l.replaceFirst(RegExp(r'^#{1,6}\s*'), ''); // Markdown-Überschrift
      l = l.replaceFirst(RegExp(r'^[-*•–]\s+'), ''); // Bullet
      l = l.replaceFirst(RegExp(r'^\d+[.)]\s+'), ''); // Nummerierung
      return l;
    }).toList();

    // Mehrfache Leerzeichen innerhalb der Zeilen zusammenfassen
    final collapsed = lines
        .map((l) => l.replaceAll(RegExp(r'[ \t]{2,}'), ' '))
        .join('\n');

    // Absätze rekonstruieren: an Leerzeilen trennen, leere verwerfen
    final paragraphs = collapsed
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.replaceAll('\n', ' ').trim())
        .where((p) => p.isNotEmpty)
        .map(_stripEmoji)
        .where((p) => p.isNotEmpty)
        .toList();

    // Länge begrenzen (Anschreiben soll auf eine Seite passen)
    final limited = paragraphs.length > maxParagraphs
        ? paragraphs.sublist(0, maxParagraphs)
        : paragraphs;

    return limited.join('\n\n');
  }

  /// Entfernt Emojis und ähnliche Symbolzeichen.
  static String _stripEmoji(String input) => input
      .replaceAll(
        RegExp(
          r'[\u{1F000}-\u{1FAFF}\u{2190}-\u{21FF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]',
          unicode: true,
        ),
        '',
      )
      .trim();

  /// Heuristik, ob ein gespeicherter Anschreiben-Text „Müll" ist und deshalb
  /// neu generiert werden sollte.
  ///
  /// Deckt die beiden bekannten Fehlermuster ab:
  /// 1. **Gedankenkette eines Reasoning-Modells** – englische Meta-Planung
  ///    wie „5: Formal closing …", „Refining …", „keep it to 4 or 5 paragraphs"
  /// 2. **Abgeschnittener Text** (z. B. `maxOutputTokens` war zu klein) – kein
  ///    regulärer Schluss „Mit freundlichen Grüßen" vorhanden.
  ///
  /// Nur-Text, der von der KI (oder manuell) sauber geschrieben wurde, hat
  /// weder diese Marker noch fehlt die Grußformel → ist NICHT korrupt.
  static bool isGarbage(String text) {
    if (text.trim().isEmpty) return true;
    // Deutlich zu kurz für ein Anschreiben → korrupt.
    if (text.trim().length < 80) return true;

    // 1) Marker der Gedankenkette / Modell-Planung (typisch englisch).
    final reasoningMarkers = RegExp(
      r'(formal closing|paragraphs?\s?(limit|each)|keep it to \d or \d '
      r'paragraphs|refining( the)? text|draft|structur(ing| e) the '
      r'paragraphs|5 paragraph|introductory paragraph|body paragraph|'
      r'opening paragraph|concluding paragraph|generate a|write a '
      r'professional)',
      caseSensitive: false,
    );
    if (reasoningMarkers.hasMatch(text)) return true;

    // Nummerierte Planungsmuster wie "5: Formal closing" / "1. Opening"
    final numberedPattern = RegExp(
      r'(^\s*\d+\s*[):.]\s+[A-Za-z])',
      multiLine: true,
      caseSensitive: false,
    );
    if (numberedPattern.hasMatch(text)) return true;

    // 2) Abgeschnitten – keine reguläre Grußformel.
    if (!text.contains('Mit freundlichen Grüßen')) return true;

    return false;
  }
}
