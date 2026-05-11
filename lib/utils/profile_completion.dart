import '../models/user_model.dart';

class ProfileCompletionResult {
  final int percent;
  final int completedFields;
  final int totalFields;
  final String nextStep;
  final bool meetsDiscoveryThreshold;
  final bool hasStrongProfile;

  ProfileCompletionResult({
    required this.percent,
    required this.completedFields,
    required this.totalFields,
    required this.nextStep,
    required this.meetsDiscoveryThreshold,
    required this.hasStrongProfile,
  });
}

const int kProfileCompletionDiscoveryThreshold = 70;
const int kStrongProfileThreshold = 90;

class WeightedProfileSectionResult {
  final String id;
  final String title;
  final int weight;
  final int completedFields;
  final int totalFields;
  final int earnedPercent;
  final String helperText;
  final bool requiredForDiscovery;

  const WeightedProfileSectionResult({
    required this.id,
    required this.title,
    required this.weight,
    required this.completedFields,
    required this.totalFields,
    required this.earnedPercent,
    required this.helperText,
    required this.requiredForDiscovery,
  });

  bool get isComplete => completedFields >= totalFields;
}

class WeightedProfileCompletionResult {
  final int percent;
  final List<WeightedProfileSectionResult> sections;

  const WeightedProfileCompletionResult({
    required this.percent,
    required this.sections,
  });

  WeightedProfileSectionResult? get nextIncompleteSection {
    for (final section in sections) {
      if (!section.isComplete) return section;
    }
    return null;
  }

  bool get meetsDiscoveryThreshold => percent >= kProfileCompletionDiscoveryThreshold;
  bool get hasStrongProfile => percent >= kStrongProfileThreshold;
}

typedef _SectionCheck = ({String label, bool complete});

bool _hasText(String? value) => value?.trim().isNotEmpty == true;

int? calculateAgeFromDob(DateTime? dob) {
  if (dob == null) return null;
  final now = DateTime.now();
  var age = now.year - dob.year;
  final birthdayThisYear = DateTime(now.year, dob.month, dob.day);
  if (birthdayThisYear.isAfter(now)) {
    age -= 1;
  }
  return age;
}

int inferJourneyStep(UserModel? profile) {
  final weighted = calculateWeightedProfileCompletion(profile);
  final order = ['basic', 'religious', 'personal', 'family', 'about', 'photos'];
  final next = weighted.nextIncompleteSection;
  if (next == null) return order.length - 1;
  final index = order.indexOf(next.id);
  return index < 0 ? 0 : index;
}

Map<String, dynamic> buildProfileCompletionSnapshot(
  UserModel? profile, {
  Object? updatedAt,
}) {
  final weighted = calculateWeightedProfileCompletion(profile);
  return {
    'profileCompletion': weighted.percent.toDouble(),
    'profileSetupCompleted': weighted.meetsDiscoveryThreshold,
    ...?updatedAt == null ? null : {'profileCompletionUpdatedAt': updatedAt},
  };
}

WeightedProfileCompletionResult calculateWeightedProfileCompletion(UserModel? profile) {
  final basicChecks = <_SectionCheck>[
    (label: 'full name', complete: _hasText(profile?.fullName)),
    (label: 'date of birth', complete: profile?.dateOfBirth != null),
    (label: 'gender', complete: _hasText(profile?.gender)),
    (label: 'city/location', complete: _hasText(profile?.city) || profile?.location?.isNotEmpty == true),
  ];
  final religiousChecks = <_SectionCheck>[
    (label: 'religion', complete: _hasText(profile?.religion)),
    (label: 'sect', complete: _hasText(profile?.sect)),
    (label: 'prayer level', complete: _hasText(profile?.prayerLevel)),
    (label: 'religious practice level', complete: _hasText(profile?.religiousPracticeLevel)),
  ];
  final personalChecks = <_SectionCheck>[
    (label: 'education', complete: _hasText(profile?.education)),
    (label: 'profession', complete: _hasText(profile?.profession) || _hasText(profile?.occupation)),
    (label: 'height', complete: profile?.height != null),
    (label: 'marital status', complete: _hasText(profile?.maritalStatus)),
  ];
  final familyChecks = <_SectionCheck>[
    (label: 'father name', complete: _hasText(profile?.fatherName)),
    (label: 'father occupation', complete: _hasText(profile?.fatherOccupation)),
    (label: 'mother name', complete: _hasText(profile?.motherName)),
    (label: 'mother occupation', complete: _hasText(profile?.motherOccupation)),
    (label: 'brothers/sisters', complete: profile?.numberOfBrothers != null || profile?.numberOfSisters != null),
    (label: 'family type', complete: _hasText(profile?.familyType)),
  ];
  final aboutChecks = <_SectionCheck>[
    (
      label: 'about you',
      complete: ((profile?.aboutMe ?? '').trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length) >= 20,
    ),
    (label: 'what you are looking for', complete: profile?.lookingFor?.isNotEmpty == true),
  ];
  final photoChecks = <_SectionCheck>[
    (
      label: 'profile photo',
      complete: _hasText(profile?.profilePhotoUrl) ||
          _hasText(profile?.profilePictureUrl) ||
          profile?.photos?.isNotEmpty == true ||
          profile?.profileImages?.isNotEmpty == true,
    ),
  ];

  WeightedProfileSectionResult buildSection({
    required String id,
    required String title,
    required int weight,
    required List<_SectionCheck> checks,
    required String helperText,
    required bool requiredForDiscovery,
  }) {
    final completed = checks.where((check) => check.complete).length;
    final total = checks.length;
    final ratio = total == 0 ? 0.0 : completed / total;
    return WeightedProfileSectionResult(
      id: id,
      title: title,
      weight: weight,
      completedFields: completed,
      totalFields: total,
      earnedPercent: (ratio * weight).round(),
      helperText: helperText,
      requiredForDiscovery: requiredForDiscovery,
    );
  }

  final sections = [
    buildSection(
      id: 'basic',
      title: 'Basic Info',
      weight: 20,
      checks: basicChecks,
      helperText: 'Add the basics so your profile has a clear identity.',
      requiredForDiscovery: true,
    ),
    buildSection(
      id: 'religious',
      title: 'Religious Info',
      weight: 20,
      checks: religiousChecks,
      helperText: 'Tell us a little about your deen and practice.',
      requiredForDiscovery: true,
    ),
    buildSection(
      id: 'personal',
      title: 'Personal Info',
      weight: 20,
      checks: personalChecks,
      helperText: 'Education, work, and marital status help improve match quality.',
      requiredForDiscovery: true,
    ),
    buildSection(
      id: 'family',
      title: 'Family Details',
      weight: 10,
      checks: familyChecks,
      helperText: 'Optional, but helpful for family-involved matching.',
      requiredForDiscovery: false,
    ),
    buildSection(
      id: 'about',
      title: 'About & Preferences',
      weight: 15,
      checks: aboutChecks,
      helperText: 'Let future matches understand you and what matters to you.',
      requiredForDiscovery: true,
    ),
    buildSection(
      id: 'photos',
      title: 'Photos & Privacy',
      weight: 15,
      checks: photoChecks,
      helperText: 'At least one photo is needed before you can fully start discovering.',
      requiredForDiscovery: true,
    ),
  ];

  final percent = sections.fold<int>(0, (sum, section) => sum + section.earnedPercent).clamp(0, 100);
  return WeightedProfileCompletionResult(percent: percent, sections: sections);
}

ProfileCompletionResult calculateProfileCompletion(UserModel? profile) {
  final checks = <_SectionCheck>[
    (label: 'full name', complete: _hasText(profile?.fullName)),
    (label: 'email', complete: _hasText(profile?.email)),
    (label: 'phone', complete: _hasText(profile?.phone)),
    (label: 'gender', complete: _hasText(profile?.gender)),
    (label: 'date of birth', complete: profile?.dateOfBirth != null),
    (label: 'religion', complete: _hasText(profile?.religion)),
    (label: 'sect', complete: _hasText(profile?.sect) || _hasText(profile?.caste)),
    (label: 'education', complete: _hasText(profile?.education)),
    (label: 'occupation', complete: _hasText(profile?.profession) || _hasText(profile?.occupation)),
    (label: 'height', complete: profile?.height != null),
    (label: 'city/country', complete: _hasText(profile?.city) || profile?.location?.isNotEmpty == true),
    (label: 'about me', complete: _hasText(profile?.aboutMe)),
    (
      label: 'profile photo',
      complete: _hasText(profile?.profilePhotoUrl) ||
          _hasText(profile?.profilePictureUrl) ||
          profile?.photos?.isNotEmpty == true ||
          profile?.profileImages?.isNotEmpty == true,
    ),
  ];

  final completedFields = checks.where((entry) => entry.complete).length;
  final totalFields = checks.length;
  final weighted = calculateWeightedProfileCompletion(profile);
  // Always derive the visible completion score from the live profile fields
  // so profile surfaces stay in sync even if a stored snapshot is stale.
  final percent = weighted.percent;
  final nextMissing = checks.cast<_SectionCheck?>().firstWhere((entry) => entry != null && !entry.complete, orElse: () => null);
  final meetsDiscoveryThreshold = percent >= kProfileCompletionDiscoveryThreshold;
  final hasStrongProfile = percent >= kStrongProfileThreshold;

  return ProfileCompletionResult(
    percent: percent,
    completedFields: completedFields,
    totalFields: totalFields,
    nextStep: nextMissing == null
        ? 'Your profile looks complete and ready for stronger matches.'
        : 'Add your ${nextMissing.label} to improve match quality.',
    meetsDiscoveryThreshold: meetsDiscoveryThreshold,
    hasStrongProfile: hasStrongProfile,
  );
}
