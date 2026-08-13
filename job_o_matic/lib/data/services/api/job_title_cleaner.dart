/// Utility zur Bereinigung von Job-Titeln.
class JobTitleCleaner {
  JobTitleCleaner._();

  /// Bereinigt einen rohen Job-Titel.
  static String cleanJobTitle(String rawTitle) {
    if (rawTitle.isEmpty) return '';

    var title = rawTitle.trim();

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
    if (RegExp(r'\.(com|de|io|net|org|jobs|careers|co|eu)\b',
            caseSensitive: false)
        .hasMatch(text)) {
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
