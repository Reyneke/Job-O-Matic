import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:job_o_matic/data/database/database_helper.dart';
import 'package:job_o_matic/data/repositories/database_repository.dart';
import 'package:job_o_matic/data/repositories/sent_email_log_repository.dart';
import 'package:job_o_matic/data/services/api/api_key_service.dart';
import 'package:job_o_matic/data/services/email/circuit_breaker.dart';
import 'package:job_o_matic/data/services/email/email_service.dart';
import 'package:job_o_matic/data/services/email/email_template_service.dart';
import 'package:job_o_matic/data/services/email/mail_dispatcher.dart';
import 'package:job_o_matic/data/services/email/mail_queue_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase F - Integrationstests des Versands (MailDispatcher + MailQueue +
/// Audit-Log + persistenter Tageslimit-Zaehler) gegen MockClient und
/// In-Memory-SQLite. Siehe doc/plan/14-Email.md Phase F.
void main() {
  late DatabaseHelper dbHelper;
  late DatabaseRepository dbRepo;
  late SentEmailLogRepository logRepo;
  late Directory tmpDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('job_o_matic_integration');
    dbHelper = DatabaseHelper();
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: DatabaseHelper.schemaVersion,
        onCreate: (db, version) => dbHelper.createSchemaForTesting(db),
      ),
    );
    dbHelper.overrideDatabaseForTesting(db);
    dbRepo = DatabaseRepository(dbHelper: dbHelper);
    logRepo = SentEmailLogRepository(dbHelper: dbHelper);
  });

  tearDown(() async {
    await dbHelper.close();
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  Future<File> makePdf() async {
    final f = File(
      '${tmpDir.path}/bewerbung_${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    await f.writeAsBytes([1, 2, 3, 4]);
    return f;
  }

  MailDispatcher createDispatcher({
    required MockClient client,
    CircuitBreaker? circuitBreaker,
    MailQueueService? queueService,
  }) {
    final dispatcher = MailDispatcher(
      queueService: queueService ?? MailQueueService(),
      emailService: EmailService(
        keyService: ApiKeyService(),
        client: client,
        apiKeyLoader: () async => 'test-api-key',
      ),
      templateService: EmailTemplateService(),
      circuitBreaker: circuitBreaker,
      sentEmailLogRepository: logRepo,
      databaseRepository: dbRepo,
    );
    dispatcher.start(interval: const Duration(hours: 1));
    addTearDown(dispatcher.dispose);
    return dispatcher;
  }

  http.Response okResponse() =>
      http.Response(jsonEncode({'messageId': 'm-1'}), 201);

  group('Versand-Integration', () {
    test(
      'Erfolgsfall: sendet mit Anhang+CC/BCC und schreibt Audit-Log',
      () async {
        http.Request? captured;
        var requests = 0;
        final dispatcher = createDispatcher(
          client: MockClient((request) async {
            requests++;
            captured = request;
            return okResponse();
          }),
        );

        final pdf = await makePdf();
        await dispatcher.enqueueApplicationEmail(
          to: 'hr@firma.de',
          position: 'Flutter-Entwickler',
          company: 'Firma GmbH',
          fullName: 'Max Mustermann',
          pdfPath: pdf.path,
          applicationId: '42',
          cc: ['cc@firma.de'],
          bcc: ['bcc@firma.de'],
        );
        await dispatcher.processQueue();

        expect(requests, 1);
        final payload = jsonDecode(captured!.body) as Map<String, dynamic>;
        expect((payload['attachment'] as List<dynamic>), hasLength(1));
        expect(payload['cc'], hasLength(1));
        expect(payload['bcc'], hasLength(1));
        expect(await logRepo.hasSent(42), isTrue);
        expect(await dbRepo.getMailCountForToday(), 1);
      },
    );

    test('HTTP 429 bleibt failed und erhoeht den Tageszaehler nicht', () async {
      var requests = 0;
      final dispatcher = createDispatcher(
        client: MockClient((request) async {
          requests++;
          return http.Response('{"code":"too_many_requests"}', 429);
        }),
      );

      final pdf = await makePdf();
      await dispatcher.enqueueApplicationEmail(
        to: 'hr@firma.de',
        position: 'Flutter-Entwickler',
        company: 'Firma GmbH',
        fullName: 'Max Mustermann',
        pdfPath: pdf.path,
        applicationId: '42',
      );
      await dispatcher.processQueue();

      expect(requests, 1, reason: 'genau 1 Versuch, dann Retry-Backoff');
      expect(await logRepo.hasSent(42), isFalse);
      expect(await dbRepo.getMailCountForToday(), 0);
    });

    test(
      'Tageslimit 300 (persistenter Zaehler) verhindert den Versand',
      () async {
        final today = _todayStamp();
        await dbRepo.saveFilter(DatabaseRepository.mailSentDateKey, today);
        await dbRepo.saveFilter(DatabaseRepository.mailSentCountKey, '300');

        var requests = 0;
        final dispatcher = createDispatcher(
          client: MockClient((request) async {
            requests++;
            return okResponse();
          }),
        );

        final pdf = await makePdf();
        await dispatcher.enqueueApplicationEmail(
          to: 'hr@firma.de',
          position: 'Flutter-Entwickler',
          company: 'Firma GmbH',
          fullName: 'Max Mustermann',
          pdfPath: pdf.path,
          applicationId: '42',
        );
        await dispatcher.processQueue();

        expect(requests, 0, reason: 'kein Request bei erreichtem Tageslimit');
        expect(await logRepo.hasSent(42), isFalse);
        expect(await dbRepo.getMailCountForToday(), 300);
      },
    );

    test(
      'HTTP 401 (Key/Absender nicht verifiziert) ist permanent – kein Retry',
      () async {
        final queue = MailQueueService();
        var requests = 0;
        final dispatcher = createDispatcher(
          client: MockClient((request) async {
            requests++;
            return http.Response(
              '{"message":"Key not found","code":"unauthorized"}',
              401,
            );
          }),
          queueService: queue,
        );

        final pdf = await makePdf();
        await dispatcher.enqueueApplicationEmail(
          to: 'hr@firma.de',
          position: 'Flutter-Entwickler',
          company: 'Firma GmbH',
          fullName: 'Max Mustermann',
          pdfPath: pdf.path,
          applicationId: '42',
        );
        await dispatcher.processQueue();

        // Genau 1 Versuch – ein 401 korrigiert sich nicht durch erneutes Senden.
        expect(
          requests,
          1,
          reason: '401 = permanenter Fehler, kein Backoff-Retry',
        );
        expect(await logRepo.hasSent(42), isFalse);
        expect(await dbRepo.getMailCountForToday(), 0);

        final entry = queue.allEntries.single;
        expect(entry.status, MailStatus.failed);
        expect(entry.errorMessage, contains('401'));
        expect(
          entry.nextTryAt,
          isNull,
          reason: 'permanenter Fehler plant keinen weiteren Versuch',
        );
      },
    );

    test('Circuit Breaker OPEN blockiert den Versand (kein Request)', () async {
      final breaker = CircuitBreaker(
        failureThreshold: 1,
        timeout: const Duration(minutes: 30),
      );
      breaker.onFailure(); // 1 Fehler >= Threshold -> OPEN

      var requests = 0;
      final dispatcher = createDispatcher(
        client: MockClient((request) async {
          requests++;
          return okResponse();
        }),
        circuitBreaker: breaker,
      );

      final pdf = await makePdf();
      await dispatcher.enqueueApplicationEmail(
        to: 'hr@firma.de',
        position: 'Flutter-Entwickler',
        company: 'Firma GmbH',
        fullName: 'Max Mustermann',
        pdfPath: pdf.path,
        applicationId: '42',
      );
      await dispatcher.processQueue();

      expect(requests, 0);
      expect(await logRepo.hasSent(42), isFalse);
    });

    test(
      'Wiederholungen erzeugen je einen eigenen Audit-Log-Eintrag',
      () async {
        final dispatcher = createDispatcher(
          client: MockClient((_) async => okResponse()),
        );

        final pdf = await makePdf();
        await dispatcher.enqueueApplicationEmail(
          to: 'hr@firma.de',
          position: 'Flutter-Entwickler',
          company: 'Firma GmbH',
          fullName: 'Max Mustermann',
          pdfPath: pdf.path,
          applicationId: '42',
        );
        await dispatcher.processQueue();
        await dispatcher.enqueueApplicationEmail(
          to: 'hr@firma.de',
          position: 'Flutter-Entwickler',
          company: 'Firma GmbH',
          fullName: 'Max Mustermann',
          pdfPath: pdf.path,
          applicationId: '42',
        );
        await dispatcher.processQueue();

        final db = await dbHelper.database;
        final logRows = await db.query('sent_email_log');
        expect(logRows, hasLength(2));
        expect(logRows.every((r) => r['status'] == 'sent'), isTrue);
        expect(await dbRepo.getMailCountForToday(), 2);
      },
    );
  });
}

String _todayStamp() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}
