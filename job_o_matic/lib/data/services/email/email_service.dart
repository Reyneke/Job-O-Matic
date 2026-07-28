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

  static const _baseUrl = 'api.brevo.com';
  static const _sendPath = '/v3/smtp/email';

  EmailService({
    required ApiKeyService keyService,
    http.Client? client,
  })  : _keyService = keyService,
        _client = client ?? http.Client();

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
  }) async {
    final apiKey = await _keyService.loadKey(ApiKeyService.brevoApiKey);
    if (apiKey == null || apiKey.isEmpty) {
      return EmailResult(
        success: false,
        errorMessage: 'Brevo API-Key nicht konfiguriert. '
            'Bitte in den Einstellungen hinterlegen.',
      );
    }

    final payload = <String, dynamic>{
      'sender': {
        'name': senderName ?? 'Job-O-Matic',
        'email': senderEmail ?? 'noreply@job-o-matic.local',
      },
      'to': [
        {'email': to},
      ],
      'subject': subject,
      'htmlContent': htmlContent,
    };

    if (attachments != null && attachments.isNotEmpty) {
      payload['attachment'] = attachments.map((a) => {
        'name': a.filename,
        'content': base64Encode(a.bytes),
      }).toList();
    }

    final uri = Uri.https(_baseUrl, _sendPath);
    final response = await _client.post(
      uri,
      headers: {
        'api-key': apiKey,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      _log.info('E-Mail erfolgreich gesendet an $to: $subject');
      return EmailResult(success: true, messageId: response.body);
    } else {
      final errorBody = response.body;
      _log.severe('E-Mail-Versand fehlgeschlagen (HTTP ${response.statusCode}): $errorBody');
      return EmailResult(
        success: false,
        errorMessage: 'HTTP ${response.statusCode}: $errorBody',
      );
    }
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

  const EmailResult({
    required this.success,
    this.messageId,
    this.errorMessage,
  });
}

/// Anhang für E-Mails.
class EmailAttachment {
  final String filename;
  final List<int> bytes;

  const EmailAttachment({
    required this.filename,
    required this.bytes,
  });
}