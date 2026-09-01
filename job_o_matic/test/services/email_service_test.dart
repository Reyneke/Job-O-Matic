import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:job_o_matic/data/services/api/api_key_service.dart';
import 'package:job_o_matic/data/services/email/email_service.dart';

EmailService _service(
  MockClient client, {
  Future<String?> Function()? apiKeyLoader,
}) {
  return EmailService(
    keyService: ApiKeyService(),
    client: client,
    apiKeyLoader: apiKeyLoader ?? (() async => 'test-api-key'),
  );
}

http.Response _successResponse({String messageId = 'msg-123'}) => http.Response(
  jsonEncode({'messageId': messageId}),
  201,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('EmailService', () {
    test(
      'sendet E-Mail und baut Payload mit replyTo, cc, bcc und Anhang',
      () async {
        http.Request? captured;
        final client = MockClient((request) async {
          captured = request;
          return _successResponse();
        });
        final service = _service(client);

        final bytes = [1, 2, 3, 4];
        final result = await service.sendEmail(
          to: 'hr@firma.de',
          subject: 'Bewerbung als Flutter-Entwickler',
          htmlContent: '<p>Bewerbung</p>',
          senderName: 'Max Mustermann',
          senderEmail: 'kleitmiandefoot@gmail.com',
          replyToName: 'Max Mustermann',
          replyToEmail: 'kleitmiandefoot@gmail.com',
          cc: ['karriere@firma.de'],
          bcc: ['personal@firma.de'],
          attachments: [
            EmailAttachment(filename: 'bewerbung.pdf', bytes: bytes),
          ],
        );

        expect(result.success, isTrue);
        expect(result.messageId, 'msg-123');
        expect(result.failure, isNull);

        expect(captured, isNotNull);
        expect(captured!.url.path, '/v3/smtp/email');
        final payload = jsonDecode(captured!.body) as Map<String, dynamic>;

        expect(payload['sender'], {
          'name': 'Max Mustermann',
          'email': 'kleitmiandefoot@gmail.com',
        });
        expect(payload['to'], [
          {'email': 'hr@firma.de'},
        ]);
        expect(payload['replyTo'], {
          'name': 'Max Mustermann',
          'email': 'kleitmiandefoot@gmail.com',
        });
        expect(payload['cc'], [
          {'email': 'karriere@firma.de'},
        ]);
        expect(payload['bcc'], [
          {'email': 'personal@firma.de'},
        ]);
        expect(payload['attachment'], hasLength(1));
        final attachment =
            (payload['attachment'] as List<dynamic>).single
                as Map<String, dynamic>;
        expect(attachment['name'], 'bewerbung.pdf');
        expect(attachment['content'], base64Encode(bytes));
      },
    );
    test(
      'verwendet verifizierte Standard-Absenderadresse, wenn keine angegeben',
      () async {
        http.Request? captured;
        final client = MockClient((request) async {
          captured = request;
          return _successResponse();
        });
        final service = _service(client);

        await service.sendEmail(
          to: 'hr@firma.de',
          subject: 'Bewerbung',
          htmlContent: 'Body',
        );

        final payload = jsonDecode(captured!.body) as Map<String, dynamic>;
        expect(payload['sender'], {
          'name': 'Job-O-Matic',
          'email': 'kleitmiandefoot@gmail.com',
        });
        expect(payload.containsKey('replyTo'), isFalse);
      },
    );

    test('parst messageId aus JSON-Response', () async {
      final service = _service(
        MockClient((_) async => _successResponse(messageId: 'abc-123')),
      );
      final result = await service.sendEmail(
        to: 'hr@firma.de',
        subject: 'Bewerbung',
        htmlContent: 'Body',
      );
      expect(result.success, isTrue);
      expect(result.messageId, 'abc-123');
    });

    test('klassifiziert HTTP 401 als unverifiedSender', () async {
      final service = _service(
        MockClient((_) async => http.Response('{"code":"unauthorized"}', 401)),
      );
      final result = await service.sendEmail(
        to: 'hr@firma.de',
        subject: 'Bewerbung',
        htmlContent: 'Body',
      );
      expect(result.success, isFalse);
      expect(result.failure, EmailFailure.unverifiedSender);
      expect(result.errorMessage, contains('401'));
    });

    test('klassifiziert HTTP 429 als rateLimited', () async {
      final service = _service(
        MockClient((_) async => http.Response('{"code":"rate-limit"}', 429)),
      );
      final result = await service.sendEmail(
        to: 'hr@firma.de',
        subject: 'Bewerbung',
        htmlContent: 'Body',
      );
      expect(result.success, isFalse);
      expect(result.failure, EmailFailure.rateLimited);
    });

    test('klassifiziert HTTP 500 als server', () async {
      final service = _service(
        MockClient((_) async => http.Response('{"code":"error"}', 500)),
      );
      final result = await service.sendEmail(
        to: 'hr@firma.de',
        subject: 'Bewerbung',
        htmlContent: 'Body',
      );
      expect(result.success, isFalse);
      expect(result.failure, EmailFailure.server);
    });

    test('liefert network-Fehler bei Exception', () async {
      final service = _service(
        MockClient(
          (_) async => throw http.ClientException('Verbindung fehlgeschlagen'),
        ),
      );
      final result = await service.sendEmail(
        to: 'hr@firma.de',
        subject: 'Bewerbung',
        htmlContent: 'Body',
      );
      expect(result.success, isFalse);
      expect(result.failure, EmailFailure.network);
    });

    test('fehlender API-Key → success false ohne Request', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return _successResponse();
      });
      final service = _service(client, apiKeyLoader: () async => null);

      final result = await service.sendEmail(
        to: 'hr@firma.de',
        subject: 'Bewerbung',
        htmlContent: 'Body',
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('API-Key'));
      expect(captured, isNull);
    });
  });
}
