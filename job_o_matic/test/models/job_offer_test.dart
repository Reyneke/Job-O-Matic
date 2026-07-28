import 'package:flutter_test/flutter_test.dart';
import 'package:job_o_matic/data/models/job_offer.dart';

void main() {
  group('JobOffer', () {
    test('fromJson creates correct object', () {
      final json = {
        'id': '123',
        'title': 'Softwareentwickler',
        'company': 'Tech GmbH',
        'location': 'Berlin',
        'description': 'Spannende Stelle',
        'url': 'https://example.com/job/123',
        'salaryRange': '50000 - 70000 EUR',
        'employmentType': 'fullTime',
        'workModel': 'hybrid',
        'publishedAt': '2024-01-15T10:00:00.000',
        'source': 'ba',
      };

      final job = JobOffer.fromJson(json);

      expect(job.id, '123');
      expect(job.title, 'Softwareentwickler');
      expect(job.company, 'Tech GmbH');
      expect(job.location, 'Berlin');
      expect(job.description, 'Spannende Stelle');
      expect(job.url, 'https://example.com/job/123');
      expect(job.salaryRange, '50000 - 70000 EUR');
      expect(job.employmentType, EmploymentType.fullTime);
      expect(job.workModel, WorkModel.hybrid);
      expect(job.publishedAt, DateTime(2024, 1, 15, 10, 0, 0));
      expect(job.source, 'ba');
    });

    test('fromJson handles null fields', () {
      final json = {
        'id': '456',
        'title': 'Test Job',
        'company': 'Test Corp',
        'url': 'https://example.com/job/456',
        'source': 'manual',
      };

      final job = JobOffer.fromJson(json);

      expect(job.id, '456');
      expect(job.location, isNull);
      expect(job.description, isNull);
      expect(job.salaryRange, isNull);
      expect(job.employmentType, isNull);
      expect(job.workModel, isNull);
      expect(job.publishedAt, isNull);
    });

    test('toJson produces correct map', () {
      final job = JobOffer(
        id: '789',
        title: 'Flutter Developer',
        company: 'App Co',
        location: 'Hamburg',
        description: 'Mobile development',
        url: 'https://example.com/job/789',
        salaryRange: '60000 - 80000 EUR',
        employmentType: EmploymentType.fullTime,
        workModel: WorkModel.remote,
        publishedAt: DateTime(2024, 6, 1),
        source: 'adzuna',
      );

      final json = job.toJson();

      expect(json['id'], '789');
      expect(json['title'], 'Flutter Developer');
      expect(json['company'], 'App Co');
      expect(json['location'], 'Hamburg');
      expect(json['employmentType'], 'fullTime');
      expect(json['workModel'], 'remote');
      expect(json['source'], 'adzuna');
    });

    test('toJson/fromJson roundtrip', () {
      final original = JobOffer(
        id: '1',
        title: 'DevOps Engineer',
        company: 'Cloud Inc',
        url: 'https://example.com/job/1',
        source: 'ba',
      );

      final json = original.toJson();
      final restored = JobOffer.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.company, original.company);
      expect(restored.url, original.url);
      expect(restored.source, original.source);
    });
  });

  group('JobApiException', () {
    test('toString includes message and status code', () {
      final exception = JobApiException('Not found', statusCode: 404);
      final str = exception.toString();
      expect(str, contains('Not found'));
      expect(str, contains('404'));
    });

    test('toString with only message', () {
      final exception = JobApiException('Error');
      expect(exception.toString(), contains('Error'));
    });
  });
}