/// Status eines Eintrags im Versand-Audit-Log.
///
/// Werte orientieren sich an doc/plan/14-Email.md (DB-Schema `sent_email_log`):
/// `sent` | `failed` | `bounced` | `draft_exported`.
enum SentEmailLogStatus {
  sent('sent'),
  failed('failed'),
  bounced('bounced'),
  draftExported('draft_exported');

  /// Persistierter Wert in der DB.
  final String storeValue;

  const SentEmailLogStatus(this.storeValue);

  static SentEmailLogStatus fromStoreValue(String value) => values.firstWhere(
    (e) => e.storeValue == value,
    orElse: () => SentEmailLogStatus.failed,
  );

  String get displayName {
    switch (this) {
      case SentEmailLogStatus.sent:
        return 'Gesendet';
      case SentEmailLogStatus.failed:
        return 'Fehlgeschlagen';
      case SentEmailLogStatus.bounced:
        return 'Zurückgewiesen';
      case SentEmailLogStatus.draftExported:
        return 'Als Entwurf exportiert';
    }
  }
}

/// Ein Eintrag im Versand-Audit-Log (Tabelle `sent_email_log`).
///
/// Jeder Versandversuch (auch Wiederholungen und „Als Entwurf exportieren“)
/// erhält einen eigenen Eintrag – die „Zuletzt gesendet am“-Auswertung nutzt
/// MAX(sent_at) je application_id.
class SentEmailLogEntry {
  final int? id;
  final int applicationId;
  final String recipientEmail;
  final String subject;
  final String? messageId;
  final SentEmailLogStatus status;
  final String? errorMessage;
  final DateTime sentAt;

  const SentEmailLogEntry({
    this.id,
    required this.applicationId,
    required this.recipientEmail,
    required this.subject,
    this.messageId,
    this.status = SentEmailLogStatus.sent,
    this.errorMessage,
    required this.sentAt,
  });
}
