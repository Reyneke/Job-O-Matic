/// Deterministischer 32-Bit-FNV-1a-Hash.
///
/// Ersetzt `String.hashCode`, das in Dart nicht garantiert über Läufe und
/// Plattformen stabil ist (Jobsuche-Revison, Punkt 9: „Stabile Job-ID im
/// Scraper“). FNV-1a ist deterministisch, kollisionsarm und ohne zusätzliche
/// Abhängigkeiten implementierbar.
int fnv1a32(String input) {
  // FNV-1a-Offset-Basis (2166136261) und Primzahl (16777619).
  var hash = 0x811C9DC5;
  for (final codeUnit in input.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  // Ergebnis auf nicht-negative 32 Bit begrenzen (stabil über Plattformen).
  return hash & 0x7FFFFFFF;
}