import 'package:flutter_test/flutter_test.dart';
import 'package:job_o_matic/data/services/api/stable_hash.dart';

void main() {
  group('fnv1a32', () {
    test('is deterministic', () {
      final input = 'https://example.com/job/1|Flutter Developer';
      expect(fnv1a32(input), fnv1a32(input));
    });

    test('is non-negative and fits in signed 31 bits', () {
      final hash = fnv1a32('https://example.com/job/5|Dart Engineer');
      expect(hash, inInclusiveRange(0, 0x7FFFFFFF));
    });

    test('differs for different inputs', () {
      expect(fnv1a32('a|b'), isNot(fnv1a32('a|c')));
    });
  });
}