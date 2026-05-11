import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  static const Set<String> privateFieldKeys = {'email', 'phone'};

  static DateTime? _asDateTime(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static Timestamp? _asTimestamp(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value;
    if (value is DateTime) return Timestamp.fromDate(value);
    return null;
  }

  final String uid;
  final String fullName;
  final String? email;
  final String? phone;
  final String? profileCreatedFor;
  final String? gender;
  final DateTime? dateOfBirth;
  final int? age;
  final String? religion;
  final String? caste;
  final String? sect;
  final String? prayerLevel;
  final String? religiousPracticeLevel;
  final String? familyDetails;
  final Map<String, String>? location;
  final String? city;
  final String? education;
  final String? profession;
  final String? occupation;
  final String? annualIncome;
  final String? income;
  final double? height;
  final String? heightUnit;
  final String? maritalStatus;
  final Map<String, bool>? lifestyle;
  final List<String>? hobbies;
  final String? aboutMe;
  final List<String>? lookingFor;
  final String? preferredFamilyType;
  final String? familyType;
  final String? fatherName;
  final String? fatherOccupation;
  final String? motherName;
  final String? motherOccupation;
  final int? numberOfSisters;
  final int? numberOfBrothers;
  final String? profilePictureUrl;
  final String? profilePhotoUrl;
  final List<String>? profileImages;
  final List<String>? photos;
  final bool? hidePhoto;
  final String? profilePrivacy;
  final double? profileCompletion;
  final bool? profileSetupCompleted;
  final Timestamp? profileCompletionUpdatedAt;
  final bool isVerified;
  final bool isPremium;
  final bool isOnline;
  final Timestamp? lastSeenAt;
  final Timestamp createdAt;
  final Timestamp? updatedAt;

  UserModel({
    required this.uid,
    required this.fullName,
    this.email,
    this.phone,
    this.profileCreatedFor,
    this.gender,
    this.dateOfBirth,
    this.age,
    this.religion,
    this.caste,
    this.sect,
    this.prayerLevel,
    this.religiousPracticeLevel,
    this.familyDetails,
    this.location,
    this.city,
    this.education,
    this.profession,
    this.occupation,
    this.annualIncome,
    this.income,
    this.height,
    this.heightUnit,
    this.maritalStatus,
    this.lifestyle,
    this.hobbies,
    this.aboutMe,
    this.lookingFor,
    this.preferredFamilyType,
    this.familyType,
    this.fatherName,
    this.fatherOccupation,
    this.motherName,
    this.motherOccupation,
    this.numberOfSisters,
    this.numberOfBrothers,
    this.profilePictureUrl,
    this.profilePhotoUrl,
    this.profileImages,
    this.photos,
    this.hidePhoto,
    this.profilePrivacy,
    this.profileCompletion,
    this.profileSetupCompleted,
    this.profileCompletionUpdatedAt,
    this.isVerified = false,
    this.isPremium = false,
    this.isOnline = false,
    this.lastSeenAt,
    Timestamp? createdAt,
    this.updatedAt,
  }) : createdAt = createdAt ?? Timestamp.now();

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel.fromMaps(map);
  }

  factory UserModel.fromMaps(
    Map<String, dynamic> publicMap, [
    Map<String, dynamic>? privateMap,
  ]) {
    final merged = <String, dynamic>{...publicMap, ...?privateMap};
    return UserModel(
      uid: merged['uid'] as String? ?? '',
      fullName: merged['fullName'] as String? ?? '',
      email: merged['email'] as String?,
      phone: merged['phone'] as String?,
      profileCreatedFor: merged['profileCreatedFor'] as String?,
      gender: merged['gender'] as String?,
      dateOfBirth: _asDateTime(merged['dateOfBirth']),
      age: (merged['age'] as num?)?.toInt(),
      religion: merged['religion'] as String?,
      caste: merged['caste'] as String?,
      sect: merged['sect'] as String?,
      prayerLevel: merged['prayerLevel'] as String?,
      religiousPracticeLevel: merged['religiousPracticeLevel'] as String?,
      familyDetails: merged['familyDetails'] as String?,
      location: merged['location'] != null
          ? Map<String, String>.from(merged['location'])
          : null,
      city: merged['city'] as String? ?? (merged['location'] is Map ? (merged['location']['city'] as String?) : null),
      education: merged['education'] as String? ?? '',
      profession: merged['profession'] as String? ?? merged['occupation'] as String?,
      occupation: merged['occupation'] as String? ?? '',
      annualIncome: merged['annualIncome'] as String? ?? merged['income'] as String?,
      income: merged['income'] as String? ?? '',
      height: merged['height'] != null
          ? (merged['height'] as num).toDouble()
          : null,
      heightUnit: merged['heightUnit'] as String?,
      maritalStatus: merged['maritalStatus'] as String?,
      lifestyle: merged['lifestyle'] != null
          ? Map<String, bool>.from(merged['lifestyle'])
          : null,
      hobbies: merged['hobbies'] != null
          ? List<String>.from(merged['hobbies'] as List)
          : null,
      aboutMe: merged['aboutMe'] as String?,
      lookingFor: merged['lookingFor'] != null
          ? List<String>.from(merged['lookingFor'] as List)
          : null,
      preferredFamilyType: merged['preferredFamilyType'] as String?,
      familyType: merged['familyType'] as String?,
      fatherName: merged['fatherName'] as String?,
      fatherOccupation: merged['fatherOccupation'] as String?,
      motherName: merged['motherName'] as String?,
      motherOccupation: merged['motherOccupation'] as String?,
      numberOfSisters: (merged['numberOfSisters'] as num?)?.toInt(),
      numberOfBrothers: (merged['numberOfBrothers'] as num?)?.toInt(),
      profilePictureUrl: merged['profilePictureUrl'] as String?,
      profilePhotoUrl: merged['profilePhotoUrl'] as String? ?? merged['profilePictureUrl'] as String?,
      profileImages: merged['profileImages'] != null
          ? List<String>.from(merged['profileImages'] as List)
          : null,
      photos: merged['photos'] != null
          ? List<String>.from(merged['photos'] as List)
          : (merged['profileImages'] != null
              ? List<String>.from(merged['profileImages'] as List)
              : null),
      hidePhoto: merged['hidePhoto'] as bool?,
      profilePrivacy: merged['profilePrivacy'] as String?,
      profileCompletion: (merged['profileCompletion'] as num?)?.toDouble(),
      profileSetupCompleted: merged['profileSetupCompleted'] as bool?,
      profileCompletionUpdatedAt: _asTimestamp(
        merged['profileCompletionUpdatedAt'],
      ),
      isVerified: (merged['isVerified'] as bool?) ?? false,
      isPremium: (merged['isPremium'] as bool?) ?? false,
      isOnline: (merged['isOnline'] as bool?) ?? false,
      lastSeenAt: _asTimestamp(merged['lastSeenAt']),
      createdAt: _asTimestamp(merged['createdAt']) ?? Timestamp.now(),
      updatedAt: _asTimestamp(merged['updatedAt']),
    );
  }

  Map<String, dynamic> toPublicMap() {
    return {
      'uid': uid,
      'fullName': fullName,
      'profileCreatedFor': profileCreatedFor,
      'gender': gender,
      'dateOfBirth': dateOfBirth != null
          ? Timestamp.fromDate(dateOfBirth!)
          : null,
      'age': age,
      'religion': religion,
      'caste': caste,
      'sect': sect,
      'prayerLevel': prayerLevel,
      'religiousPracticeLevel': religiousPracticeLevel,
      'familyDetails': familyDetails,
      'location': location,
      'city': city ?? location?['city'],
      'education': education,
      'profession': profession ?? occupation,
      'occupation': occupation,
      'annualIncome': annualIncome ?? income,
      'income': income,
      'height': height,
      'heightUnit': heightUnit,
      'maritalStatus': maritalStatus,
      'lifestyle': lifestyle,
      'hobbies': hobbies,
      'aboutMe': aboutMe,
      'lookingFor': lookingFor,
      'preferredFamilyType': preferredFamilyType,
      'familyType': familyType,
      'fatherName': fatherName,
      'fatherOccupation': fatherOccupation,
      'motherName': motherName,
      'motherOccupation': motherOccupation,
      'numberOfSisters': numberOfSisters,
      'numberOfBrothers': numberOfBrothers,
      'profilePictureUrl': profilePictureUrl,
      'profilePhotoUrl': profilePhotoUrl ?? profilePictureUrl,
      'profileImages': profileImages,
      'photos': photos ?? profileImages,
      'hidePhoto': hidePhoto,
      'profilePrivacy': profilePrivacy,
      'profileCompletion': profileCompletion,
      'profileSetupCompleted': profileSetupCompleted,
      'profileCompletionUpdatedAt': profileCompletionUpdatedAt,
      'isVerified': isVerified,
      'isPremium': isPremium,
      'isOnline': isOnline,
      'lastSeenAt': lastSeenAt,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    }..removeWhere((key, value) => value == null);
  }

  Map<String, dynamic> toPrivateMap() {
    return {
      'email': email,
      'phone': phone,
    }..removeWhere((key, value) => value == null);
  }

  Map<String, dynamic> toMap() {
    return {
      ...toPublicMap(),
      ...toPrivateMap(),
    };
  }
}
