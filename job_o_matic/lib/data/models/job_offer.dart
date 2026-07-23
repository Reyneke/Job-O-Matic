/// Beschäftigungsart.
enum EmploymentType { fullTime, partTime, both }

/// Arbeitsmodell.
enum WorkModel { onSite, hybrid, remote, any }

/// Repräsentiert ein Stellenangebot aus einer beliebigen Quelle.
class JobOffer {
  final String id;
  final String title;
  final String company;
  final String? location;
  final String? description;
  final String url;
  final String? salaryRange;
  final EmploymentType? employmentType;
  final WorkModel? workModel;
  final DateTime? publishedAt;
  final String source; // 'ba', 'adzuna', 'serpapi', 'manual', 'scrape'

  const JobOffer({
    required this.id,
    required this.title,
    required this.company,
    this.location,
    this.description,
    required this.url,
    this.salaryRange,
    this.employmentType,
    this.workModel,
    this.publishedAt,
    required this.source,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'company': company,
        'location': location,
        'description': description,
        'url': url,
        'salaryRange': salaryRange,
        'employmentType': employmentType?.name,
        'workModel': workModel?.name,
        'publishedAt': publishedAt?.toIso8601String(),
        'source': source,
      };

  factory JobOffer.fromJson(Map<String, dynamic> json) => JobOffer(
        id: json['id'] as String,
        title: json['title'] as String,
        company: json['company'] as String,
        location: json['location'] as String?,
        description: json['description'] as String?,
        url: json['url'] as String,
        salaryRange: json['salaryRange'] as String?,
        employmentType: json['employmentType'] != null
            ? EmploymentType.values.firstWhere(
                (e) => e.name == json['employmentType'])
            : null,
        workModel: json['workModel'] != null
            ? WorkModel.values.firstWhere(
                (e) => e.name == json['workModel'])
            : null,
        publishedAt: json['publishedAt'] != null
            ? DateTime.parse(json['publishedAt'] as String)
            : null,
        source: json['source'] as String,
      );
}

/// Exception für API-Fehler.
class JobApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? details;

  const JobApiException(this.message, {this.statusCode, this.details});

  @override
  String toString() =>
      'JobApiException: $message${statusCode != null ? ' (HTTP $statusCode)' : ''}';
}