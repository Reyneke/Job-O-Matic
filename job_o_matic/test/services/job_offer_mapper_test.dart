import 'package:flutter_test/flutter_test.dart';
import 'package:job_o_matic/data/models/job_offer.dart';
import 'package:job_o_matic/data/services/api/job_offer_mapper.dart';

void main() {
  group('JobOfferMapper', () {
    group('parseDate', () {
      test('parses ISO date', () {
        expect(JobOfferMapper.parseDate('2026-07-24'), DateTime(2026, 7, 24));
      });

      test('returns null for null and empty', () {
        expect(JobOfferMapper.parseDate(null), isNull);
        expect(JobOfferMapper.parseDate(''), isNull);
      });

      test('returns null for invalid input', () {
        expect(JobOfferMapper.parseDate('kein-datum'), isNull);
      });
    });

    group('formatSalaryAmount', () {
      test('adds german thousand separators', () {
        expect(JobOfferMapper.formatSalaryAmount(45000), '45.000');
        expect(JobOfferMapper.formatSalaryAmount(78000.0), '78.000');
        expect(JobOfferMapper.formatSalaryAmount(1200), '1.200');
      });

      test('keeps small amounts unchanged', () {
        expect(JobOfferMapper.formatSalaryAmount(900), '900');
      });
    });

    group('employmentTypeFromBooleans', () {
      test('maps BA flags', () {
        expect(
          JobOfferMapper.employmentTypeFromBooleans(
            isFullTime: true,
            isPartTime: false,
          ),
          EmploymentType.fullTime,
        );
        expect(
          JobOfferMapper.employmentTypeFromBooleans(
            isFullTime: false,
            isPartTime: true,
          ),
          EmploymentType.partTime,
        );
        expect(
          JobOfferMapper.employmentTypeFromBooleans(
            isFullTime: true,
            isPartTime: true,
          ),
          EmploymentType.both,
        );
        expect(
          JobOfferMapper.employmentTypeFromBooleans(
            isFullTime: false,
            isPartTime: false,
          ),
          isNull,
        );
      });
    });

    group('employmentTypeFromContract', () {
      test('maps Adzuna contract types (case-insensitive)', () {
        expect(JobOfferMapper.employmentTypeFromContract('permanent'),
            EmploymentType.fullTime);
        expect(JobOfferMapper.employmentTypeFromContract('part_time'),
            EmploymentType.partTime);
        expect(JobOfferMapper.employmentTypeFromContract('FULL_TIME'),
            EmploymentType.fullTime);
      });

      test('returns null for null and unknown', () {
        expect(JobOfferMapper.employmentTypeFromContract(null), isNull);
        expect(JobOfferMapper.employmentTypeFromContract('unknown'), isNull);
      });
    });

    group('workModelFromDescription', () {
      test('detects remote', () {
        expect(
          JobOfferMapper.workModelFromDescription(
              'Remote Arbeit von zu Hause'),
          WorkModel.remote,
        );
      });

      test('detects hybrid', () {
        expect(
          JobOfferMapper.workModelFromDescription('Hybrides Arbeiten im Büro'),
          WorkModel.hybrid,
        );
      });

      test('detects on-site', () {
        expect(
          JobOfferMapper.workModelFromDescription('Arbeiten vor Ort im Büro'),
          WorkModel.onSite,
        );
      });

      test('returns null when there is no hint', () {
        expect(
          JobOfferMapper.workModelFromDescription(
              'Ein spannendes Team sucht Verstärkung'),
          isNull,
        );
        expect(JobOfferMapper.workModelFromDescription(null), isNull);
      });
    });
  });
}