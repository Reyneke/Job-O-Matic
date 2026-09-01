import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:job_o_matic/data/services/api/api_key_service.dart';
import 'package:job_o_matic/data/services/email/email_service.dart';
import 'package:job_o_matic/data/services/email/email_template_service.dart';
import 'package:job_o_matic/data/services/email/mail_dispatcher.dart';
import 'package:job_o_matic/data/services/email/mail_queue_service.dart';

http.Response _successResponse() =>
    http.Response(jsonEncode({'messageId': 'm1'}), 201);

MailDispatcher _dispatcher({
  required MockClient client,
  MailQueueService? queue,
}) {
  final queueService = queue ?? MailQueueService();
  final dispatcher = MailDispatcher(
    queueService: queueService,
    emailService: EmailService(
      keyService: ApiKeyService(),
      client: client,
      apiKeyLoader: () async => 'test-api-key',
    ),
    templateService: EmailTemplateService(),
  );
  // Startet den periodischen Timer nicht sofort (Intervall 1h), der Callback
  // wird aber gesetzt – processQueue() kann manuell ausgelöst werden.
  dispatcher.start(interval: const Duration(hours: 1));
  return dispatcher;
}

void main() {
  group('MailDispatcher (E-Mail-Versand über Queue)', () {
    test('lädt PDF-Anhang und sendet mit replyTo/cc/bcc', () async {
      final tmpDir = await Directory.systemTemp.createTemp(
        'job_o_matic_mail_test',
      );
      addTearDown(() => tmpDir.delete(recursive: true));
      final pdfFile = File('${tmpDir.path}/bewerbung.pdf');
      await pdfFile.writeAsBytes([1, 2, 3, 4]);

      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return _successResponse();
      });
      final queue = MailQueueService();
      final dispatcher = _dispatcher(client: client, queue: queue);
      addTearDown(dispatcher.dispose);

      await dispatcher.enqueueApplicationEmail(
        to: 'hr@firma.de',
        position: 'Flutter-Entwickler',
        company: 'Firma GmbH',
        fullName: 'Max Mustermann',
        pdfPath: pdfFile.path,
        applicationId: '42',
        senderName: 'Max Mustermann',
        senderEmail: 'kleitmiandefoot@gmail.com',
        cc: ['cc@firma.de'],
        bcc: ['bcc@firma.de'],
      );

      await dispatcher.processQueue();

      final payload = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(payload['attachment'], hasLength(1));
      final attachment =
          (payload['attachment'] as List<dynamic>).single
              as Map<String, dynamic>;
      expect(attachment['name'], 'bewerbung.pdf');
      expect(attachment['content'], base64Encode([1, 2, 3, 4]));
      expect(payload['replyTo'], {
        'name': 'Max Mustermann',
        'email': 'kleitmiandefoot@gmail.com',
      });
      expect(payload['cc'], [
        {'email': 'cc@firma.de'},
      ]);
      expect(payload['bcc'], [
        {'email': 'bcc@firma.de'},
      ]);
      expect(payload['sender'], {
        'name': 'Max Mustermann',
        'email': 'kleitmiandefoot@gmail.com',
      });
      expect(queue.allEntries.single.status, MailStatus.sent);
    });

    test('ohne pdfPath → Eintrag wird failed (PDF fehlt)', () async {
      final client = MockClient((_) async => _successResponse());
      final queue = MailQueueService();
      final dispatcher = _dispatcher(client: client, queue: queue);
      addTearDown(dispatcher.dispose);

      await dispatcher.enqueueApplicationEmail(
        to: 'hr@firma.de',
        position: 'Flutter-Entwickler',
        company: 'Firma GmbH',
        fullName: 'Max Mustermann',
      );

      await dispatcher.processQueue();

      expect(queue.allEntries.single.status, MailStatus.failed);
      expect(queue.allEntries.single.errorMessage, isNotNull);
    });

    test(
      'bei HTTP 401 (Absender nicht verifiziert) → Eintrag bleibt failed',
      () async {
        final tmpDir = await Directory.systemTemp.createTemp(
          'job_o_matic_mail_test_401',
        );
        addTearDown(() => tmpDir.delete(recursive: true));
        final pdfFile = File('${tmpDir.path}/bewerbung.pdf');
        await pdfFile.writeAsBytes([1]);

        final client = MockClient(
          (_) async => http.Response('{"code":"unauthorized"}', 401),
        );
        final queue = MailQueueService();
        final dispatcher = _dispatcher(client: client, queue: queue);
        addTearDown(dispatcher.dispose);

        await dispatcher.enqueueApplicationEmail(
          to: 'hr@firma.de',
          position: 'Flutter-Entwickler',
          company: 'Firma GmbH',
          fullName: 'Max Mustermann',
          pdfPath: pdfFile.path,
        );

        await dispatcher.processQueue();

        expect(queue.allEntries.single.status, MailStatus.failed);
      },
    );
  });
}
