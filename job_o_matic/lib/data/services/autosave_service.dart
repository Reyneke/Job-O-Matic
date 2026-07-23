import 'dart:async';
import 'package:logging/logging.dart';

/// Service für automatisches Speichern mit Debounding.
///
/// Speichert nach der letzten Änderung nach einer konfigurierbaren
/// Verzögerung (Standard: 5 Sekunden).
class AutosaveService {
  final Logger _log = Logger('AutosaveService');
  final Duration _delay;
  Timer? _timer;
  Future<void> Function()? _saveCallback;

  AutosaveService({Duration? delay})
      : _delay = delay ?? const Duration(seconds: 5);

  /// Startet die Überwachung. Ruft [onSave] nach Verzögerung auf.
  void start(Future<void> Function() onSave) {
    _saveCallback = onSave;
    _log.fine('Autosave gestartet (Intervall: ${_delay.inSeconds}s)');
  }

  /// Wird bei jeder Änderung aufgerufen. Setzt den Timer zurück.
  void notifyChange() {
    _timer?.cancel();
    _timer = Timer(_delay, _doSave);
  }

  Future<void> _doSave() async {
    if (_saveCallback != null) {
      try {
        await _saveCallback!();
        _log.fine('Autosave durchgeführt');
      } catch (e) {
        _log.severe('Autosave fehlgeschlagen: $e');
      }
    }
  }

  /// Sofort speichern (ohne Verzögerung).
  Future<void> saveNow() async {
    _timer?.cancel();
    await _doSave();
  }

  /// Stoppt die Überwachung.
  void stop() {
    _timer?.cancel();
    _saveCallback = null;
    _log.fine('Autosave gestoppt');
  }

  void dispose() {
    stop();
  }
}