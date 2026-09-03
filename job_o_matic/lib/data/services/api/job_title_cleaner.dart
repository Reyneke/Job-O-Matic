import 'package:html/parser.dart' as html_parser;

/// Utility zur Bereinigung von Job-Titeln.
class JobTitleCleaner {
  JobTitleCleaner._();

  /// Normalisiert Mojibake, das entsteht, wenn UTF-8-kodierte Zeichen
  /// von Webseiten als Windows-1252 interpretiert werden (Scraping).
  ///
  /// Beispiel: en-Dash '–' (UTF-8: E2 80 93) dekodiert als Windows-1252
  /// ergibt 'â€“' (â + € + "). Dadurch schlagen die Trennzeichen-Regexen
  /// fehl. Diese Methode normalisiert zurück auf korrektes Unicode.
  static String _normalizeMojibake(String text) {
    return text
        // En-Dash – (U+2013, UTF-8: E2 80 93 → â€“)
        .replaceAll('\u00e2\u20ac\u201c', '\u2013')
        // Em-Dash — (U+2014, UTF-8: E2 80 94 → â€œ)
        .replaceAll('\u00e2\u20ac\u201d', '\u2014')
        // Right single quote ' (U+2019, UTF-8: E2 80 99 → â€™)
        .replaceAll('\u00e2\u20ac\u2122', '\u2019')
        // Left single quote ' (U+2018, UTF-8: E2 80 98 → â€˜)
        .replaceAll('\u00e2\u20ac\u02dc', '\u2018')
        // Left double quote " (U+201C, UTF-8: E2 80 9C → âœ)
        .replaceAll('\u00e2\u20ac\u0152', '\u201c')
        // Right double quote " (U+201D, UTF-8: E2 80 9D → âŸ)
        .replaceAll('\u00e2\u20ac\u0178', '\u201d')
        // Non-breaking space (U+00A0, UTF-8: C2 A0 → Â )
        .replaceAll('\u00c2\u00a0', '\u00a0')
        // Stray Â (from partially decoded UTF-8)
        .replaceAll('\u00c2', '')
        // German umlauts
        .replaceAll('\u00c3\u00a4', '\u00e4') // ä
        .replaceAll('\u00c3\u00b6', '\u00f6') // ö
        .replaceAll('\u00c3\u00bc', '\u00fc') // ü
        .replaceAll('\u00c3\u009f', '\u00df'); // ß
  }

  /// Bereinigt einen rohen Job-Titel.
  static String cleanJobTitle(String rawTitle) {
    if (rawTitle.isEmpty) return '';

    var title = rawTitle.trim();

    // 0. Mojibake normalisieren (UTF-8 als Windows-1252 interpretiert)
    title = _normalizeMojibake(title);

    // 0b. HTML-Entities dekodieren (z. B. &#x2F; → /, &amp; → &), die aus
    //     API-/Scrape-Quellen stammen können (Realszenario: „Senior Flutter
    //     Developer &#x2F; Client Engineer …“).
    if (title.contains('&')) {
      try {
        title = html_parser.parseFragment(title).text ?? title;
      } catch (_) {
        // Unverändert lassen, falls das Parsen fehlschlägt.
      }
    }

    // 1. Bekannte Trennzeichen für Suffixe entfernen.
    final separators = [
      RegExp(r'\s*\|\s*', caseSensitive: false),
      RegExp(r'\s*–\s*', caseSensitive: false),
      RegExp(r'\s*—\s*', caseSensitive: false),
      RegExp(r'\s*:\s*', caseSensitive: false),
      // Hyphen with surrounding spaces (not within compound words)
      RegExp(r'\s+-\s+', caseSensitive: false),
    ];

    for (final sep in separators) {
      final parts = title.split(sep);
      if (parts.length < 2) continue;
      final lastPart = parts.last.trim();
      if (_looksLikeSiteName(lastPart)) {
        title = parts.sublist(0, parts.length - 1).join(' ').trim();
        break;
      }
    }

    // 2. Leerraum normalisieren.
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();

    // 3. Fallback.
    if (title.isEmpty || title.length < 5) {
      return rawTitle.trim();
    }

    return title;
  }

  /// Heuristik: Sieht der Text wie ein Webseiten-/Portal-Name aus?
  static bool _looksLikeSiteName(String text) {
    if (text.isEmpty) return false;

    final portalWords = [
      'jobs',
      'job',
      'career',
      'careers',
      'stellenangebot',
      'stellenanzeige',
      'recruiting',
      'talent',
      'talents',
      'people',
      'hr',
      'work',
      'karriere',
      'join',
      'vacancy',
      'vacancies',
    ];
    final lower = text.toLowerCase();
    for (final word in portalWords) {
      if (lower.contains(word)) return true;
    }

    // TLD-ähnliche Endungen
    if (RegExp(
      r'\.(com|de|io|net|org|jobs|careers|co|eu)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return true;
    }

    // Kurz und ohne typische Job-Begriffe
    final wordCount = text.split(RegExp(r'\s+')).length;
    final jobKeywords = [
      'developer',
      'engineer',
      'manager',
      'lead',
      'senior',
      'junior',
      'flutter',
      'dart',
      'python',
      'java',
      'react',
      'frontend',
      'backend',
      'full',
      'stack',
      'software',
      'consultant',
      'spezialist',
      'fachkraft',
      'experte',
      'm/w/d',
      'w/m/d',
      '(m/f/d)',
      '(w/m/d)',
    ];
    final lowerText = text.toLowerCase();
    for (final kw in jobKeywords) {
      if (lowerText.contains(kw)) return false;
    }
    return wordCount <= 4;
  }
}
