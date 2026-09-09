/// Ansprechpartner-Extraktion aus deutschen Stellenbeschreibungen
/// (doc/plan/17, „Ansprechpartner“; offener Punkt in 16-Jobsuche-BA.md).
///
/// Bewusst **best effort**: Die realen Schreibweisen sind sehr uneinheitlich.
/// Erkannt werden typische Formulierungen mit einem klaren Label
/// (`Ansprechpartner(in)`, `Kontaktperson`, `Kontakt`) bzw. „wenden Sie sich
/// an …“, gefolgt von einer Anrede (`Herr`/`Frau`) und einem Namen (1–2
/// Wort-Tokens). Nicht erkannte oder unklare Fälle liefern `null` (kein
/// falscher Name).
library;

/// Ein Name beginnt mit Herr/Frau + 1–2 Wort-Tokens (Buchstaben, Umlaute,
/// Bindestrich, Punkte für Initialen). Konservativ, damit keine Rollen-/
/// Tel.-Wörter als Name übernommen werden.
final RegExp _name = RegExp(
  r'(?:herr(?:n)?|frau)\s+'
  r'[A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß.\-]*'
  r'(?:\s+[A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß.\-]*)?',
  caseSensitive: false,
);

/// „Ansprechpartner: Name“, „Kontaktperson ist Herr X“, „Kontakt: Frau Y“
/// (optional mit Doppelpunkt bzw. „ist“/Artikel).
final RegExp _labeled = RegExp(
  r'(?:ansprechpartner(?:in)?|kontaktperson|kontakt)'
  r'\s*:?\s*(?:ist\s+)?(?:der\s+|die\s+)?(' +
      // Group 1: der Name inkl. Anrede.
      _name.pattern +
      r')',
  caseSensitive: false,
);

/// „wenden Sie sich an Frau X“, „melden Sie sich bei Herrn Y“.
final RegExp _wenden = RegExp(
  r'(?:wenden\s+sie\s+sich|kontaktieren\s+sie|melden\s+sie\s+sich)'
  r'\s+(?:bei|an)\s+(' +
      _name.pattern +
      r')',
  caseSensitive: false,
);

/// Liefert den ersten plausiblen Ansprechpartner-Namen in [text] oder `null`.
///
/// Die Anrede bleibt im Ergebnis erhalten (z. B. für die Anrede im
/// Anschreiben); überzählige Wörter nach dem Namen werden abgeschnitten.
String? firstContactPersonIn(String? text) {
  if (text == null || text.trim().isEmpty) return null;

  final labeledMatch = _labeled.firstMatch(text);
  if (labeledMatch != null) {
    final name = labeledMatch.group(1);
    if (name != null && name.isNotEmpty) return _cleanName(name);
  }

  final wendenMatch = _wenden.firstMatch(text);
  if (wendenMatch != null) {
    final name = wendenMatch.group(1);
    if (name != null && name.isNotEmpty) return _cleanName(name);
  }

  return null;
}

/// Namen bereinigen: Whitespace normalisieren, abschließende Satz-/
/// Füllzeichen entfernen und „Herrn“ (Akkusativ) auf „Herr“ normalisieren.
String _cleanName(String raw) {
  var name = raw
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[,;.:]+$'), '')
      .trim();
  if (name.toLowerCase().startsWith('herrn ')) {
    name = 'Herr ${name.substring(6)}';
  }
  return name.trim();
}
