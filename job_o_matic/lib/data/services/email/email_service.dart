import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import '../api/api_key_service.dart';

/// Service für den E-Mail-Versand über die Brevo-API.
///
/// Brevo (ehemals Sendinblue) REST-API:
/// - Endpunkt: https://api.brevo.com/v3/smtp/email
/// - Authentifizierung: API-Key im Header `api-key`
/// - Limit Free-Tier: 300 E-Mails/Tag
///
/// DSGVO-Hinweis: Brevo-Server stehen in der EU (Frankreich).
class EmailService {
  final Logger _log = Logger('EmailService');
  final http.Client _client;
  final ApiKeyService _keyService;
  final Future<String?> Function()? _apiKeyLoader;

  static const _baseUrl = 'api.brevo.com';
  static const _sendPath = '/v3/smtp/email';

  /// Verifizierte Brevo-Absenderadresse (doc/plan/14-Email.md) – zugleich Antwortadresse.

  static const String defaultSenderEmail = 'kleitmiandefoot@gmail.com';
  static const String defaultSenderName = 'Job-O-Matic';

  EmailService({
    required ApiKeyService keyService,
    http.Client? client,
    Future<String?> Function()? apiKeyLoader,
  }) : _keyService = keyService,
       _client = client ?? http.Client(),
       _apiKeyLoader = apiKeyLoader;

  /// Sendet eine E-Mail über die Brevo-API.
  ///
  /// [to] - Empfänger-E-Mail-Adresse
  /// [subject] - Betreffzeile
  /// [htmlContent] - HTML-Inhalt der E-Mail
  /// [senderName] - Absendername (optional)
  /// [senderEmail] - Absender-E-Mail (optional, muss bei Brevo verifiziert sein)
  /// [attachmentPaths] - Liste von Dateipfaden für Anhänge (optional)
  Future<EmailResult> sendEmail({
    required String to,
    required String subject,
    required String htmlContent,
    String? senderName,
    String? senderEmail,
    List<EmailAttachment>? attachments,
    String? replyToName,
    String? replyToEmail,
    List<String>? cc,
    List<String>? bcc,
  }) async {
    final apiKey = await _loadApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return EmailResult(
        success: false,
        errorMessage:
            'Brevo API-Key nicht konfiguriert. '
            'Bitte in den Einstellungen hinterlegen.',
      );
    }

    final effectiveSenderName = senderName ?? defaultSenderName;
    final effectiveSenderEmail = senderEmail ?? defaultSenderEmail;

    final payload = <String, dynamic>{
      'sender': {'name': effectiveSenderName, 'email': effectiveSenderEmail},
      'to': [
        {'email': to},
      ],
      'subject': subject,
      'htmlContent': htmlContent,
    };

    if (replyToEmail != null || replyToName != null) {
      payload['replyTo'] = {
        'name': replyToName ?? effectiveSenderName,
        'email': replyToEmail ?? effectiveSenderEmail,
      };
    }
    if (cc != null && cc.isNotEmpty) {
      payload['cc'] = cc.map((e) => {'email': e}).toList();
    }
    if (bcc != null && bcc.isNotEmpty) {
      payload['bcc'] = bcc.map((e) => {'email': e}).toList();
    }
    if (attachments != null && attachments.isNotEmpty) {
      payload['attachment'] = attachments
          .map((a) => {'name': a.filename, 'content': base64Encode(a.bytes)})
          .toList();
    }

    final uri = Uri.https(_baseUrl, _sendPath);
    http.Response response;
    try {
      response = await _client.post(
        uri,
        headers: {
          'api-key': apiKey,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(payload),
      );
    } catch (e) {
      _log.severe('Netzwerkfehler beim E-Mail-Versand: $e');
      return EmailResult(
        success: false,
        errorMessage: 'Netzwerkfehler: $e',
        failure: EmailFailure.network,
      );
    }

    if (response.statusCode == 201 || response.statusCode == 200) {
      final messageId = _extractMessageId(response.body);
      _log.info(
        'E-Mail erfolgreich gesendet an $to: $subject (messageId: $messageId)',
      );
      return EmailResult(success: true, messageId: messageId);
    } else {
      final errorBody = response.body;
      final failure = _classifyFailure(response.statusCode);
      _log.severe(
        'E-Mail-Versand fehlgeschlagen (HTTP ${response.statusCode}): $errorBody',
      );
      return EmailResult(
        success: false,
        errorMessage: 'HTTP ${response.statusCode}: $errorBody',
        failure: failure,
      );
    }
  }

  Future<String?> _loadApiKey() =>
      _apiKeyLoader?.call() ?? _keyService.loadKey(ApiKeyService.brevoApiKey);

  /// Extrahiert die messageId aus der Brevo-Response (JSON-Body).
  String? _extractMessageId(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      return decoded['messageId'] as String?;
    } catch (_) {
      _log.warning('Brevo-Response enthielt kein parsebares messageId-Format');
      return null;
    }
  }

  /// Klassifiziert einen Fehler-Statuscode der Brevo-API.
  EmailFailure _classifyFailure(int statusCode) {
    if (statusCode == 401) return EmailFailure.unverifiedSender;
    if (statusCode == 429) return EmailFailure.rateLimited;
    if (statusCode >= 500) return EmailFailure.server;
    return EmailFailure.unknown;
  }

  /// Prüft, ob der Brevo-API-Key konfiguriert ist.
  Future<bool> isConfigured() async {
    final key = await _keyService.loadKey(ApiKeyService.brevoApiKey);
    return key != null && key.isNotEmpty;
  }

  void dispose() {
    _client.close();
  }
}

/// Ergebnis eines E-Mail-Versands.
class EmailResult {
  final bool success;
  final String? messageId;
  final String? errorMessage;

  /// Klassifikation des Fehlers (null bei Erfolg).
  final EmailFailure? failure;

  const EmailResult({
    required this.success,
    this.messageId,
    this.errorMessage,
    this.failure,
  });
}

/// Klassifikation fehlgeschlagener Versuche – Grundlage für UI-Fallbacks.
enum EmailFailure {
  /// HTTP 401: Absender nicht verifiziert (→ „Als Entwurf exportieren“).
  unverifiedSender,

  /// HTTP 429: Tageslimit/Rate-Limit erreicht.
  rateLimited,

  /// HTTP 5xx: temporärer Brevo-Serverfehler.
  server,

  /// Netzwerk-/Timeout-Fehler.
  network,

  /// Sonstiger Fehler.
  unknown,
}

/// Anhang für E-Mails.
class EmailAttachment {
  final String filename;
  final List<int> bytes;

  const EmailAttachment({required this.filename, required this.bytes});
}
