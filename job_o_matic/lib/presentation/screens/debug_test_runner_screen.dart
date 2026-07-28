import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

/// Debug Screen to run Flutter tests directly from the app.
///
/// Uses `dart:io` Process to execute `flutter test` commands.
/// Only available on Desktop platforms (Windows/Linux/macOS).
/// Can be hidden behind a `--dart-define=debug=true` flag in release builds.
class DebugTestRunnerScreen extends StatefulWidget {
  const DebugTestRunnerScreen({super.key});

  @override
  State<DebugTestRunnerScreen> createState() => _DebugTestRunnerScreenState();
}

class _DebugTestRunnerScreenState extends State<DebugTestRunnerScreen> {
  final Logger _log = Logger('DebugTestRunner');
  final List<_TestResult> _results = [];
  bool _isRunning = false;
  String _currentOutput = '';

  static const _testFiles = [
    'test/models/job_offer_test.dart',
    'test/services/circuit_breaker_test.dart',
    'test/services/api_cache_test.dart',
  ];

  Future<void> _runAllTests() async {
    setState(() {
      _isRunning = true;
      _results.clear();
      _currentOutput = '';
    });

    try {
      final projectDir = Directory.current.path;
      _log.info('Starte Tests in: $projectDir');

      final output = await _runFlutterTest(projectDir, []);

      setState(() {
        _currentOutput = output;
        _parseResults(output);
      });
    } catch (e) {
      setState(() {
        _currentOutput = 'Fehler: $e';
      });
    } finally {
      setState(() => _isRunning = false);
    }
  }

  Future<void> _runSingleTest(String testFile) async {
    setState(() {
      _isRunning = true;
      _results.clear();
      _currentOutput = '';
    });

    try {
      final projectDir = Directory.current.path;
      final output = await _runFlutterTest(projectDir, [testFile]);

      setState(() {
        _currentOutput = output;
        _parseResults(output);
      });
    } catch (e) {
      setState(() {
        _currentOutput = 'Fehler: $e';
      });
    } finally {
      setState(() => _isRunning = false);
    }
  }

  Future<String> _runFlutterTest(
      String workingDir, List<String> testFiles) async {
    final args = ['test', ...testFiles, '--reporter', 'expanded'];

    final process = await Process.start(
      'flutter',
      args,
      workingDirectory: workingDir,
      runInShell: true,
    );

    final stdoutBuffer = StringBuffer();

    await for (final chunk in process.stdout.transform(utf8.decoder)) {
      stdoutBuffer.write(chunk);
      setState(() {
        _currentOutput = stdoutBuffer.toString();
      });
    }

    final stderrBuffer = StringBuffer();
    await for (final chunk in process.stderr.transform(utf8.decoder)) {
      stderrBuffer.write(chunk);
    }

    final exitCode = await process.exitCode;
    final combined = stdoutBuffer.toString();
    if (stderrBuffer.isNotEmpty) {
      return '$combined\n--- STDERR (exit: $exitCode) ---\n${stderrBuffer.toString()}';
    }
    return combined;
  }

  void _parseResults(String output) {
    final lines = output.split('\n');
    final testResults = <_TestResult>[];

    for (final line in lines) {
      // Match success lines: e.g. "00:01 +14: test_name"
      final passMatch =
          RegExp(r'\+(\d+): (.+): (.+)').firstMatch(line);
      if (passMatch != null && !line.contains('-')) {
        testResults.add(_TestResult(
          testName: '${passMatch.group(2)}: ${passMatch.group(3)}',
          passed: true,
        ));
        continue;
      }

      // Match failure lines
      final failMatch =
          RegExp(r'\+(\d+) -(\d+): (.+): (.+) \[E\]').firstMatch(line);
      if (failMatch != null) {
        testResults.add(_TestResult(
          testName: '${failMatch.group(3)}: ${failMatch.group(4)}',
          passed: false,
        ));
        continue;
      }
    }

    final failed = testResults.where((r) => !r.passed).length;
    _log.info('Testergebnis: ${testResults.length} Tests, $failed fehlgeschlagen');

    setState(() {
      _results.addAll(testResults);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final passed = _results.where((r) => r.passed).length;
    final failed = _results.where((r) => !r.passed).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('🧪 Debug Test Runner'),
        centerTitle: true,
        actions: [
          if (_results.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Erneut testen',
              onPressed: _isRunning ? null : _runAllTests,
            ),
        ],
      ),
      body: Column(
        children: [
          // Control panel
          Container(
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.bug_report, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Debug-Modus (nur für Entwicklung)',
                        style: theme.textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Führt Flutter-Tests direkt aus der App aus. '
                  'Nicht für Release-Builds geeignet.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _isRunning ? null : _runAllTests,
                      icon: _isRunning
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.play_arrow),
                      label: Text(
                          _isRunning ? 'Läuft...' : 'Alle Tests starten'),
                    ),
                    OutlinedButton(
                      onPressed: _results.isEmpty
                          ? null
                          : () => setState(() {
                                _results.clear();
                                _currentOutput = '';
                              }),
                      child: const Text('Ergebnisse löschen'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Test file quick access
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text('Einzeltests:', style: theme.textTheme.labelLarge),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _testFiles.map((file) {
                        final fileName = file
                            .split('/')
                            .last
                            .replaceAll('_test.dart', '');
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            label: Text(fileName),
                            onPressed: _isRunning
                                ? null
                                : () => _runSingleTest(file),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Results summary
          if (_results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                color: failed > 0
                    ? Colors.red.withValues(alpha: 0.05)
                    : Colors.green.withValues(alpha: 0.05),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        failed > 0 ? Icons.cancel : Icons.check_circle,
                        color: failed > 0 ? Colors.red : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$passed bestanden',
                        style: TextStyle(color: Colors.green.shade700),
                      ),
                      if (failed > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '$failed fehlgeschlagen',
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

          // Test results list
          if (_results.isNotEmpty)
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final result = _results[index];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      result.passed ? Icons.check_circle : Icons.error,
                      color: result.passed ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    title: Text(
                      result.testName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        decoration: result.passed
                            ? null
                            : TextDecoration.underline,
                      ),
                    ),
                  );
                },
              ),
            ),

          // Raw output (terminal style)
          if (_currentOutput.isNotEmpty)
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _currentOutput,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.greenAccent,
                    ),
                  ),
                ),
              ),
            ),

          if (_currentOutput.isEmpty && _results.isEmpty)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.science, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'Noch keine Tests ausgeführt.\n'
                      'Klicke auf "Alle Tests starten"',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TestResult {
  final String testName;
  final bool passed;

  const _TestResult({
    required this.testName,
    required this.passed,
  });
}