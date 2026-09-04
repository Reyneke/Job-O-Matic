import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';

/// Verwaltet API-Keys sicher und plattformübergreifend.
///
/// Nutzt flutter_secure_storage für verschlüsselte Ablage:
/// - Android: EncryptedSharedPreferences
/// - iOS: Keychain Services
/// - Desktop: Verschlüsseltes Dateisystem
class ApiKeyService {
  final Logger _log = Logger('ApiKeyService');
  final FlutterSecureStorage _storage;

  static const _prefix = 'api_key_';

  /// Definierte API-Key-Namen
  static const String baApiKey = 'ba_jobboerse';
  static const String adzunaAppId = 'adzuna_app_id';
  static const String adzunaApiKey = 'adzuna_api_key';
  static const String adzunaCountry = 'adzuna_country';
  static const String serpApiKey = 'serpapi';
  static const String brevoApiKey = 'brevo';
  static const String geminiApiKey = 'gemini';
  static const String mistralApiKey = 'mistral';
  static const String groqApiKey = 'groq';

  ApiKeyService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// API-Key speichern.
  Future<void> saveKey(String name, String key) async {
    await _storage.write(key: '$_prefix$name', value: key);
    _log.info('API-Key "$name" gespeichert');
  }

  /// API-Key laden.
  Future<String?> loadKey(String name) async {
    return _storage.read(key: '$_prefix$name');
  }

  /// API-Key löschen.
  Future<void> deleteKey(String name) async {
    await _storage.delete(key: '$_prefix$name');
    _log.info('API-Key "$name" gelöscht');
  }

  /// Prüfen, ob ein Key existiert.
  Future<bool> hasKey(String name) async {
    final key = await loadKey(name);
    return key != null && key.isNotEmpty;
  }

  /// Lädt den konfigurierten Adzuna-Markt (2-Buchstaben-Ländercode).
  ///
  /// Default: `de` (Deutschland) – wie zuvor fest verdrahtet. Der Wert wird
  /// kleingeschrieben und ohne Leerzeichen zurückgegeben. Ein leerer Wert
  /// fällt auf `de` zurück.
  Future<String> loadAdzunaCountry() async {
    final country = (await loadKey(adzunaCountry))?.trim().toLowerCase() ?? 'de';
    return country.isEmpty ? 'de' : country;
  }

  /// Speichert den konfigurierten Adzuna-Markt (kleingeschrieben, getrimmt).
  ///
  /// Hinweis: Der kostenlose Adzuna-Developer-Key deckt i. d. R. nur den bei
  /// der Registrierung gewählten „Primary Market“ ab. Für Deutschland (`de`)
  /// ist er oft nicht freigeschaltet (dann HTTP 401 `AUTH_FAIL`).
  Future<void> saveAdzunaCountry(String code) =>
      saveKey(adzunaCountry, code.trim().toLowerCase());

  /// Alle gespeicherten Keys abrufen (für Konfigurationsscreen).
  Future<Map<String, bool>> getKeyStatus() async {
    final keys = [
      baApiKey,
      adzunaAppId,
      adzunaApiKey,
      serpApiKey,
      brevoApiKey,
      geminiApiKey,
      mistralApiKey,
      groqApiKey,
    ];
    final result = <String, bool>{};
    for (final name in keys) {
      result[name] = await hasKey(name);
    }
    return result;
  }
}