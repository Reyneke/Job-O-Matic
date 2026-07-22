/// Personal data of the applicant.
class PersonalData {
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final String? address;
  final String? photoPath;

  const PersonalData({
    required this.firstName,
    required this.lastName,
    this.email,
    this.phone,
    this.address,
    this.photoPath,
  });

  String get fullName => '$firstName $lastName';

  Map<String, dynamic> toJson() => {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
        'address': address,
        'photoPath': photoPath,
      };

  factory PersonalData.fromJson(Map<String, dynamic> json) => PersonalData(
        firstName: json['firstName'] as String,
        lastName: json['lastName'] as String,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        address: json['address'] as String?,
        photoPath: json['photoPath'] as String?,
      );
}

/// A single work experience entry.
class WorkExperience {
  final String company;
  final String position;
  final DateTime startDate;
  final DateTime? endDate;
  final String? description;

  const WorkExperience({
    required this.company,
    required this.position,
    required this.startDate,
    this.endDate,
    this.description,
  });

  bool get isCurrent => endDate == null;

  Map<String, dynamic> toJson() => {
        'company': company,
        'position': position,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'description': description,
      };

  factory WorkExperience.fromJson(Map<String, dynamic> json) =>
      WorkExperience(
        company: json['company'] as String,
        position: json['position'] as String,
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: json['endDate'] != null
            ? DateTime.parse(json['endDate'] as String)
            : null,
        description: json['description'] as String?,
      );
}

/// A single education entry.
class Education {
  final String institution;
  final String degree;
  final DateTime startDate;
  final DateTime? endDate;
  final String? field;

  const Education({
    required this.institution,
    required this.degree,
    required this.startDate,
    this.endDate,
    this.field,
  });

  Map<String, dynamic> toJson() => {
        'institution': institution,
        'degree': degree,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'field': field,
      };

  factory Education.fromJson(Map<String, dynamic> json) => Education(
        institution: json['institution'] as String,
        degree: json['degree'] as String,
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: json['endDate'] != null
            ? DateTime.parse(json['endDate'] as String)
            : null,
        field: json['field'] as String?,
      );
}

/// A skill with proficiency level.
class Skill {
  final String name;
  final double proficiency; // 0.0 – 1.0

  const Skill({
    required this.name,
    required this.proficiency,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'proficiency': proficiency,
      };

  factory Skill.fromJson(Map<String, dynamic> json) => Skill(
        name: json['name'] as String,
        proficiency: (json['proficiency'] as num).toDouble(),
      );
}

/// Complete CV data container.
class CvData {
  final PersonalData personalData;
  final List<WorkExperience> workExperience;
  final List<Education> education;
  final List<Skill> skills;

  const CvData({
    required this.personalData,
    this.workExperience = const [],
    this.education = const [],
    this.skills = const [],
  });

  Map<String, dynamic> toJson() => {
        'personalData': personalData.toJson(),
        'workExperience': workExperience.map((e) => e.toJson()).toList(),
        'education': education.map((e) => e.toJson()).toList(),
        'skills': skills.map((e) => e.toJson()).toList(),
      };

  factory CvData.fromJson(Map<String, dynamic> json) => CvData(
        personalData: PersonalData.fromJson(
            json['personalData'] as Map<String, dynamic>),
        workExperience: (json['workExperience'] as List<dynamic>?)
                ?.map((e) =>
                    WorkExperience.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        education: (json['education'] as List<dynamic>?)
                ?.map(
                    (e) => Education.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        skills: (json['skills'] as List<dynamic>?)
                ?.map((e) => Skill.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}