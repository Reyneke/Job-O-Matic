import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/cv_data_parser.dart';
import '../../models/cv_data.dart';

/// Provider that holds the currently loaded CV data.
///
/// Initialized asynchronously during app startup via [CvDataLoader].
/// Shows `null` until loading is complete.
final cvDataProvider = FutureProvider<CvData?>((ref) async {
  final parser = CvDataParser();
  final result = await parser.loadFromAssets();
  if (result.isSuccess && result.data != null) {
    return result.data;
  }
  // Log errors silently – the app can work without CV data
  return null;
});

/// Provider for the CV data parser (singleton).
final cvDataParserProvider = Provider<CvDataParser>((ref) {
  return CvDataParser();
});

/// Provider that exposes the parse result (for debugging/display).
final cvParseResultProvider = FutureProvider<CvParseResult>((ref) async {
  final parser = ref.read(cvDataParserProvider);
  return parser.loadFromAssets();
});