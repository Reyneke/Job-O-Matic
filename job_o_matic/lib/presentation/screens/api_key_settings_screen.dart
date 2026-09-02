import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import '../../core/providers/providers.dart';
import '../../data/repositories/job_repository.dart';
import '../../data/services/api/api_key_service.dart';

/// Screen for configuring API keys (Brevo, Adzuna, SerpAPI, etc.).
///
/// Allows the user to securely store API keys using flutter_secure_storage.
/// Keys are never hardcoded or stored in plain text.
class ApiKeySettingsScreen extends ConsumerStatefulWidget {
  const ApiKeySettingsScreen({super.key});

  @override
  ConsumerState<ApiKeySettingsScreen> createState() =>
      _ApiKeySettingsScreenState();
}

class _ApiKeySettingsScreenState extends ConsumerState<ApiKeySettingsScreen> {
  final Logger _log = Logger('ApiKeySettingsScreen');
  Map<String, bool> _keyStatus = {};
  final _baKeyController = TextEditingController();
  final _adzunaAppIdController = TextEditingController();
  final _adzunaApiKeyController = TextEditingController();
  final _serpApiKeyController = TextEditingController();
  final _brevoApiKeyController = TextEditingController();
  final _geminiApiKeyController = TextEditingController();
  final _mistralApiKeyController = TextEditingController();
  final _groqApiKeyController = TextEditingController();
  bool _isLoading = true;
  bool _obscureText = true;

  // Mapping of key names to user-friendly labels
  static const _keyLabels = <String, String>{
    ApiKeyService.baApiKey: 'BA JOBBÖRSE',
    ApiKeyService.adzunaAppId: 'Adzuna App-ID',
    ApiKeyService.adzunaApiKey: 'Adzuna API-Key',
    ApiKeyService.serpApiKey: 'SerpAPI',
    ApiKeyService.brevoApiKey: 'Brevo (E-Mail)',
  };

  static const _keyDescriptions = <String, String>{
    ApiKeyService.baApiKey: 'Öffentlicher Schlüssel für die BA-JOBBÖRSE-API '
        '(Standard: "jobboerse-jobsuche")',
    ApiKeyService.adzunaAppId: 'App-ID aus dem Adzuna Developer Dashboard',
    ApiKeyService.adzunaApiKey: 'API-Key aus dem Adzuna Developer Dashboard',
    ApiKeyService.serpApiKey: 'API-Key für Google Jobs via SerpAPI',
    ApiKeyService.brevoApiKey: 'API-Key v3 aus dem Brevo SMTP & API Bereich',
    ApiKeyService.geminiApiKey: 'API-Key aus Google AI Studio '
        '(kostenloses Kontingent, für KI-generierte Anschreiben)',
    ApiKeyService.mistralApiKey: 'API-Key von La Plateforme (mistral.ai) '
        '- EU-Alternative für KI-Anschreiben',
    ApiKeyService.groqApiKey: 'API-Key von console.groq.com '
        '- schnelle Alternative für KI-Anschreiben',
  };

  static const _keyIcons = <String, IconData>{
    ApiKeyService.baApiKey: Icons.work,
    ApiKeyService.adzunaAppId: Icons.apps,
    ApiKeyService.adzunaApiKey: Icons.vpn_key,
    ApiKeyService.serpApiKey: Icons.search,
    ApiKeyService.brevoApiKey: Icons.email,
    ApiKeyService.geminiApiKey: Icons.auto_awesome,
    ApiKeyService.mistralApiKey: Icons.alternate_email,
    ApiKeyService.groqApiKey: Icons.bolt,
  };

  @override
  void initState() {
    super.initState();
    _loadKeyStatus();
  }

  Future<void> _loadKeyStatus() async {
    setState(() => _isLoading = true);
    try {
      final keyService = ref.read(apiKeyServiceProvider);
      final status = await keyService.getKeyStatus();
      final baKey = await keyService.loadKey(ApiKeyService.baApiKey);
      final adzunaAppId =
          await keyService.loadKey(ApiKeyService.adzunaAppId);
      final adzunaApiKey =
          await keyService.loadKey(ApiKeyService.adzunaApiKey);
      final serpKey = await keyService.loadKey(ApiKeyService.serpApiKey);
      final brevoKey = await keyService.loadKey(ApiKeyService.brevoApiKey);
      final geminiKey = await keyService.loadKey(ApiKeyService.geminiApiKey);
      final mistralKey =
          await keyService.loadKey(ApiKeyService.mistralApiKey);
      final groqKey = await keyService.loadKey(ApiKeyService.groqApiKey);

      if (mounted) {
        setState(() {
          _keyStatus = status;
          _baKeyController.text = baKey ?? '';
          _adzunaAppIdController.text = adzunaAppId ?? '';
          _adzunaApiKeyController.text = adzunaApiKey ?? '';
          _serpApiKeyController.text = serpKey ?? '';
          _brevoApiKeyController.text = brevoKey ?? '';
          _geminiApiKeyController.text = geminiKey ?? '';
          _mistralApiKeyController.text = mistralKey ?? '';
          _groqApiKeyController.text = groqKey ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      _log.severe('Fehler beim Laden der API-Keys: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveKey(String keyName, String value) async {
    try {
      final keyService = ref.read(apiKeyServiceProvider);
      if (value.trim().isEmpty) {
        await keyService.deleteKey(keyName);
      } else {
        await keyService.saveKey(keyName, value.trim());
      }
      await _loadKeyStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_keyLabels[keyName] ?? keyName} ${value.trim().isEmpty ? 'gelöscht' : 'gespeichert'}',
            ),
          ),
        );
      }
    } catch (e) {
      _log.severe('Fehler beim Speichern von $keyName: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _baKeyController.dispose();
    _adzunaAppIdController.dispose();
    _adzunaApiKeyController.dispose();
    _serpApiKeyController.dispose();
    _brevoApiKeyController.dispose();
    _geminiApiKeyController.dispose();
    _mistralApiKeyController.dispose();
    _groqApiKeyController.dispose();
    super.dispose();
  }

  Widget _buildKeyField(String keyName) {
    final isConfigured = _keyStatus[keyName] ?? false;
    final label = _keyLabels[keyName] ?? keyName;
    final description = _keyDescriptions[keyName];
    final icon = _keyIcons[keyName] ?? Icons.vpn_key;

    TextEditingController getController() {
      switch (keyName) {
        case ApiKeyService.baApiKey:
          return _baKeyController;
        case ApiKeyService.adzunaAppId:
          return _adzunaAppIdController;
        case ApiKeyService.adzunaApiKey:
          return _adzunaApiKeyController;
        case ApiKeyService.serpApiKey:
          return _serpApiKeyController;
        case ApiKeyService.brevoApiKey:
          return _brevoApiKeyController;
        case ApiKeyService.geminiApiKey:
          return _geminiApiKeyController;
        case ApiKeyService.mistralApiKey:
          return _mistralApiKeyController;
        case ApiKeyService.groqApiKey:
          return _groqApiKeyController;
        default:
          return _baKeyController;
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isConfigured
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isConfigured ? '✅ Konfiguriert' : '⚠️ Fehlt',
                    style: TextStyle(
                      fontSize: 12,
                      color: isConfigured ? Colors.green : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            if (description != null) ...[
              const SizedBox(height: 4),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: getController(),
              obscureText: _obscureText && keyName != ApiKeyService.adzunaAppId,
              decoration: InputDecoration(
                hintText: isConfigured ? '••••••••' : 'API-Key eingeben...',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureText ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscureText = !_obscureText),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () => _saveKey(keyName, getController().text),
                icon: const Icon(Icons.save, size: 18),
                label: const Text('Speichern'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('API-Key Verwaltung'),
        centerTitle: true,
        // Top-Level-Route (/settings): Flutter baut keinen automatischen
        // Back-Button – daher explizit zurück zum aufrufenden Bildschirm.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Zurück',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // KI-Anschreiben Schalter (Phase 3)
                Card(
                  child: SwitchListTile(
                    value: ref.watch(jobRepositoryProvider).kiAnschreibenEnabled,
                    onChanged: (value) {
                      setState(() {});
                      ref
                          .read(jobRepositoryProvider)
                          .setKiAnschreibenEnabled(value);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(value
                              ? 'KI-Anschreiben aktiviert. Neue Bewerbungen '
                                  'werden per KI personalisiert.'
                              : 'KI-Anschreiben deaktiviert. Es wird die '
                                  'Template-Vorlage verwendet.'),
                        ),
                      );
                    },
                    title: const Text('KI-Anschreiben',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                        'Anschreiben einmalig per KI generieren '
                        '(Fallback-Kette: Gemini → Mistral → Groq)'),
                    secondary: Icon(Icons.auto_awesome,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 8),
                // Info-Karte
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Sicherheitshinweis',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'API-Keys werden verschlüsselt auf Ihrem Gerät '
                        'gespeichert (flutter_secure_storage). Sie verlassen '
                        'niemals Ihr Gerät und werden nicht an Dritte '
                        'weitergegeben.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Übersicht
                Row(
                  children: [
                    Text('Verfügbare Dienste',
                        style: theme.textTheme.titleMedium),
                    const Spacer(),
                    Text(
                      '${_keyStatus.values.where((v) => v).length} / ${_keyStatus.length} konfiguriert',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Einzelne Key-Felder
                ...ApiKeyService.brevoApiKey == ''
                    ? _keyStatus.keys.map(_buildKeyField)
                    : [
                        _buildKeyField(ApiKeyService.baApiKey),
                        _buildKeyField(ApiKeyService.adzunaAppId),
                        _buildKeyField(ApiKeyService.adzunaApiKey),
                        _buildKeyField(ApiKeyService.serpApiKey),
                        _buildKeyField(ApiKeyService.brevoApiKey),
                        _buildKeyField(ApiKeyService.geminiApiKey),
                        _buildKeyField(ApiKeyService.mistralApiKey),
                        _buildKeyField(ApiKeyService.groqApiKey),
                      ],

                const SizedBox(height: 16),

                // Test-Button für Brevo
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Konnektivität prüfen',
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Text(
                          'Prüfen Sie, ob die konfigurierten API-Keys '
                          'gültig sind.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: null, // TODO: Implement connectivity test
                          icon: const Icon(Icons.wifi_tethering),
                          label: const Text('Verbindung testen'),
                        ),
                      ],
                    ),
                  ),
                ),

                // E-Mail-Versand-Verlauf (DSGVO, Phase F)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('E-Mail-Verlauf',
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Text(
                          'Gesendete E-Mails und Versandversuche (Audit-Log) '
                          'werden 6 Monate aufbewahrt und beim App-Start '
                          'automatisch bereinigt. Hier können Sie den '
                          'kompletten Verlauf manuell löschen.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _deleteMailLog(context),
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: const Text('E-Mail-Versand-Verlauf löschen'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                            side: BorderSide(color: theme.colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _deleteMailLog(BuildContext ctx) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('E-Mail-Verlauf löschen'),
        content: const Text(
          'Möchten Sie den kompletten Versand-Verlauf (Audit-Log) wirklich '
          'löschen? Dies kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final logRepo = ref.read(sentEmailLogRepositoryProvider);
    final deleted = await logRepo.deleteAll();
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(
          deleted > 0
              ? '$deleted Verlauf-Einträge gelöscht.'
              : 'Kein E-Mail-Verlauf vorhanden.',
        ),
      ),
    );
  }
}