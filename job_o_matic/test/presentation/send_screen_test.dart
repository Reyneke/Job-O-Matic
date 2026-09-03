import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:job_o_matic/core/providers/providers.dart';
import 'package:job_o_matic/data/repositories/database_repository.dart';
import 'package:job_o_matic/data/repositories/job_repository.dart';
import 'package:job_o_matic/data/repositories/sent_email_log_repository.dart';
import 'package:job_o_matic/data/services/api/api_key_service.dart';
import 'package:job_o_matic/data/services/email/email_service.dart';
import 'package:job_o_matic/data/services/email/email_template_service.dart';
import 'package:job_o_matic/data/services/email/mail_dispatcher.dart';
import 'package:job_o_matic/data/services/email/mail_queue_service.dart';
import 'package:job_o_matic/models/application.dart';
import 'package:job_o_matic/models/sent_email_log_entry.dart';
import 'package:job_o_matic/presentation/screens/send_screen.dart';

/// Reproduziert die Exception beim Aufklappen eines Eintrags im
/// Versand-Screen (ExpansionTile-Pfeil). DB-/Netzwerk-frei (Stubs), damit der
/// Widget-Test ohne echte async-I/O im FakeAsync-Kontext laeuft.

class _FakeApiKeyService extends ApiKeyService {
  @override
  Future<String?> loadKey(String name) async => 'xkeysib-test-key';
  @override
  Future<bool> hasKey(String name) async => true;
}

/// DB-Repos, die nichts persistieren (nur In-Memory-Zustand von JobRepository).
class _NoopDatabaseRepository extends DatabaseRepository {
  @override
  Future<int> insertApplication(Application app) async => 1;
  @override
  Future<void> updateApplication(Application app) async {}
  @override
  Future<void> deleteApplication(int id) async {}
}

/// Audit-Log ohne DB-Zugriff (sofortige Antworten).
class _FakeSentEmailLogRepository extends SentEmailLogRepository {
  @override
  Future<bool> hasSent(int applicationId) async => false;
  @override
  Future<DateTime?> latestSentAt(int applicationId) async => null;
  @override
  Future<int> insert(SentEmailLogEntry entry) async => 0;
  @override
  Future<int> deleteOlderThan(DateTime cutoff) async => 0;
  @override
  Future<int> deleteAll() async => 0;
}

void main() {
  JobRepository seedRepository() {
    final repo = JobRepository(dbRepo: _NoopDatabaseRepository());
    // Versandfaehige Bewerbung: completed + pdfPath gesetzt.
    repo.addApplication(
      jobTitle: 'Senior Flutter Developer / Client Engineer (m/f/d)',
      company: 'Firma GmbH',
      jobUrl: 'https://example.com/job/1',
    );
    final app = repo.applications.single;
    repo.updateApplicationStatus(
      app.id,
      ApplicationStatus.completed,
      pdfPath: 'C:/tmp/bewerbung.pdf',
    );
    return repo;
  }

  MailDispatcher buildDispatcher() {
    return MailDispatcher(
      queueService: MailQueueService(),
      emailService: EmailService(
        keyService: _FakeApiKeyService(),
        client: MockClient((_) async => http.Response('{}', 200)),
      ),
      templateService: EmailTemplateService(),
      sentEmailLogRepository: _FakeSentEmailLogRepository(),
      databaseRepository: _NoopDatabaseRepository(),
    );
  }

  testWidgets('Aufklappen eines Eintrags wirft keine Exception', (
    tester,
  ) async {
    final repo = seedRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyServiceProvider.overrideWithValue(_FakeApiKeyService()),
          jobRepositoryProvider.overrideWith((ref) => repo),
          sentEmailLogRepositoryProvider.overrideWithValue(
            _FakeSentEmailLogRepository(),
          ),
          mailDispatcherProvider.overrideWithValue(buildDispatcher()),
        ],
        child: const MaterialApp(home: SendScreen()),
      ),
    );

    // Async-Init (isConfigured/Refresh) abarbeiten lassen.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byType(ExpansionTile),
      findsWidgets,
      reason: 'Versand-Eintrag ist vorhanden',
    );

    // Aufklappen (Pfeil nach unten auf dem Eintrag).
    await tester.tap(
      find.textContaining('Senior Flutter Developer').first,
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Nach dem Aufklappen muessen die Detail-Felder sichtbar sein.
    expect(find.text('Empfänger (E-Mail)'), findsOneWidget);
    expect(find.text('Betreff'), findsOneWidget);

    // Cleanup: SendScreen abmontieren (Timer canceln), kein hängender Timer.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
