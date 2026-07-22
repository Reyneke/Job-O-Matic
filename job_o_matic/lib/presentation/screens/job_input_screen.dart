import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import '../../data/repositories/job_repository.dart';

/// Screen 1: Input mask for job URLs.
///
/// Allows the user to enter one or more job URLs in a textarea.
/// URLs are validated and persisted before navigating to the application list.
class JobInputScreen extends ConsumerStatefulWidget {
  const JobInputScreen({super.key});

  @override
  ConsumerState<JobInputScreen> createState() => _JobInputScreenState();
}

class _JobInputScreenState extends ConsumerState<JobInputScreen> {
  final Logger _log = Logger('JobInputScreen');
  final TextEditingController _urlController = TextEditingController();
  bool _isValidating = false; // ignore: prefer_final_fields

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// Validate the entered URLs.
  List<String> _validateUrls() {
    final lines = _urlController.text
        .split(RegExp(r'[\n,;]'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final validUrls = <String>[];
    final invalidUrls = <String>[];

    for (final line in lines) {
      final uri = Uri.tryParse(line);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        // Remove trailing slash and normalize
        String normalized = uri.toString();
        if (normalized.endsWith('/')) {
          normalized = normalized.substring(0, normalized.length - 1);
        }
        if (!validUrls.contains(normalized)) {
          validUrls.add(normalized);
        }
      } else {
        invalidUrls.add(line);
      }
    }

    _log.info('URL-Validierung: ${validUrls.length} gültig, ${invalidUrls.length} ungültig');
    return validUrls;
  }

  void _onContinue() {
    final urls = _validateUrls();

    if (urls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte geben Sie mindestens eine gültige URL ein.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Store in repository
    ref.read(jobRepositoryProvider).addValidatedUrls(urls);

    // Navigate to application list
    context.go('/applications');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Job-O-Matic'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Text(
              'Stellenangebote eingeben',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Geben Sie die URLs der Stellenangebote ein (eine URL pro Zeile).',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // URL Textarea
            Expanded(
              child: TextField(
                controller: _urlController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'https://example.com/job/123\nhttps://example.com/job/456',
                  border: OutlineInputBorder(),
                  labelText: 'Stellen-URLs',
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.newline,
              ),
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.go('/search'),
                    icon: const Icon(Icons.search),
                    label: const Text('Jobsuche'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isValidating ? null : _onContinue,
                    icon: _isValidating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward),
                    label: const Text('Weiter'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}