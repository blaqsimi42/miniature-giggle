import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../models/user_model.dart';
import '../../services/user_service.dart';
import '../../services/storage_service.dart';
import '../../services/auth_service.dart';
import '../../utils/profile_completion.dart';

// Events
abstract class EditProfileEvent extends Equatable {
  const EditProfileEvent();

  @override
  List<Object?> get props => [];
}

class LoadProfileForEditing extends EditProfileEvent {
  final String userId;

  const LoadProfileForEditing(this.userId);

  @override
  List<Object?> get props => [userId];
}

class UpdateProfileField extends EditProfileEvent {
  final String fieldName;
  final dynamic value;

  const UpdateProfileField(this.fieldName, this.value);

  @override
  List<Object?> get props => [fieldName, value];
}

class SaveProfile extends EditProfileEvent {
  const SaveProfile();
}

class UploadProfileImage extends EditProfileEvent {
  final String imagePath;
  final Uint8List? imageBytes;
  final bool setAsProfilePicture;

  const UploadProfileImage(
    this.imagePath, {
    this.imageBytes,
    this.setAsProfilePicture = false,
  });

  @override
  List<Object?> get props => [imagePath, imageBytes, setAsProfilePicture];
}

class RemoveProfileImage extends EditProfileEvent {
  final String imageUrl;

  const RemoveProfileImage(this.imageUrl);

  @override
  List<Object?> get props => [imageUrl];
}

class SetProfilePicture extends EditProfileEvent {
  final String imageUrl;

  const SetProfilePicture(this.imageUrl);

  @override
  List<Object?> get props => [imageUrl];
}

// States
abstract class EditProfileState extends Equatable {
  const EditProfileState();

  @override
  List<Object?> get props => [];
}

class EditProfileInitial extends EditProfileState {
  const EditProfileInitial();
}

class EditProfileLoading extends EditProfileState {
  const EditProfileLoading();
}

class EditProfileLoaded extends EditProfileState {
  final UserModel profile;
  final Map<String, dynamic> unsavedChanges;
  final bool hasChanges;
  final List<String> uploadingImages;
  final bool isSaving;
  final String? noticeMessage;
  final bool isErrorNotice;
  final int noticeVersion;

  const EditProfileLoaded({
    required this.profile,
    this.unsavedChanges = const {},
    this.hasChanges = false,
    this.uploadingImages = const [],
    this.isSaving = false,
    this.noticeMessage,
    this.isErrorNotice = false,
    this.noticeVersion = 0,
  });

  @override
  List<Object?> get props => [
        profile,
        unsavedChanges,
        hasChanges,
        uploadingImages,
      isSaving,
        noticeMessage,
        isErrorNotice,
        noticeVersion,
      ];

  EditProfileLoaded copyWith({
    UserModel? profile,
    Map<String, dynamic>? unsavedChanges,
    bool? hasChanges,
    List<String>? uploadingImages,
    bool? isSaving,
    String? noticeMessage,
    bool? isErrorNotice,
    int? noticeVersion,
  }) {
    return EditProfileLoaded(
      profile: profile ?? this.profile,
      unsavedChanges: unsavedChanges ?? this.unsavedChanges,
      hasChanges: hasChanges ?? this.hasChanges,
      uploadingImages: uploadingImages ?? this.uploadingImages,
      isSaving: isSaving ?? this.isSaving,
      noticeMessage: noticeMessage,
      isErrorNotice: isErrorNotice ?? this.isErrorNotice,
      noticeVersion: noticeVersion ?? this.noticeVersion,
    );
  }
}

class EditProfileSaving extends EditProfileState {
  const EditProfileSaving();
}

class EditProfileSaved extends EditProfileState {
  final UserModel savedProfile;

  const EditProfileSaved(this.savedProfile);

  @override
  List<Object?> get props => [savedProfile];
}

class EditProfileError extends EditProfileState {
  final String message;

  const EditProfileError(this.message);

  @override
  List<Object?> get props => [message];
}

// Bloc
class EditProfileBloc extends Bloc<EditProfileEvent, EditProfileState> {
  final UserService _userService;
  final StorageService _storageService;
  final AuthService _authService;

  UserModel? _currentProfile;
  Map<String, dynamic> _changes = {};

  EditProfileBloc({
    required UserService userService,
    required StorageService storageService,
    required AuthService authService,
  })  : _userService = userService,
        _storageService = storageService,
        _authService = authService,
        super(const EditProfileInitial()) {
    on<LoadProfileForEditing>(_onLoadProfile);
    on<UpdateProfileField>(_onUpdateField);
    on<SaveProfile>(_onSaveProfile);
    on<UploadProfileImage>(_onUploadImage);
    on<RemoveProfileImage>(_onRemoveImage);
    on<SetProfilePicture>(_onSetProfilePicture);
  }

  Future<void> _onLoadProfile(
    LoadProfileForEditing event,
    Emitter<EditProfileState> emit,
  ) async {
    emit(const EditProfileLoading());
    try {
      final requestedUserId = event.userId.trim();
      if (requestedUserId.isEmpty) {
        emit(
          const EditProfileError(
            'No signed-in profile was available to load. Please reopen the app and try again.',
          ),
        );
        return;
      }

      final profile = await _userService.getUser(requestedUserId);
      if (profile == null) {
        emit(const EditProfileError('Profile not found'));
        return;
      }

      _currentProfile = profile;
      _changes = {};

      emit(
        EditProfileLoaded(
          profile: profile,
          unsavedChanges: {},
          hasChanges: false,
          noticeMessage: null,
        ),
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('[EditProfileBloc] _onLoadProfile error: $e\n$st');
      emit(EditProfileError('Failed to load profile: $e'));
    }
  }

  Future<void> _onUpdateField(
    UpdateProfileField event,
    Emitter<EditProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! EditProfileLoaded || _currentProfile == null) return;

    _changes[event.fieldName] = event.value;

    emit(
      currentState.copyWith(
        unsavedChanges: Map.from(_changes),
        hasChanges: true,
      ),
    );
  }

  Future<void> _onSaveProfile(
    SaveProfile event,
    Emitter<EditProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! EditProfileLoaded || _currentProfile == null) return;

    emit(currentState.copyWith(isSaving: true));
    try {
      if (_changes.isEmpty) {
        emit(currentState.copyWith(isSaving: false));
        return;
      }

      final mergedProfile = UserModel.fromMaps({
        ..._currentProfile!.toMap(),
        ..._changes,
      });
      final changesToSave = <String, dynamic>{
        ..._changes,
        ...buildProfileCompletionSnapshot(
          mergedProfile,
          updatedAt: Timestamp.now(),
        ),
      };

      await _userService.updateUser(
        _currentProfile!.uid,
        changesToSave,
      );

      // Reload profile to get updated data
      final updatedProfile = await _userService.getUser(_currentProfile!.uid);
      if (updatedProfile == null) {
        emit(const EditProfileError('Failed to reload profile after update'));
        return;
      }

      _currentProfile = updatedProfile;
      _changes = {};

      emit(EditProfileSaved(updatedProfile));
      
      // Emit loaded state after a short delay
      await Future.delayed(const Duration(milliseconds: 500));
      emit(
        EditProfileLoaded(
          profile: updatedProfile,
          unsavedChanges: {},
          hasChanges: false,
        ),
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('[EditProfileBloc] _onSaveProfile error: $e\n$st');
      emit(EditProfileError('Failed to save profile: $e'));
    }
  }

  Future<void> _onUploadImage(
    UploadProfileImage event,
    Emitter<EditProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! EditProfileLoaded ||
        _currentProfile == null ||
        _authService.getCurrentUser() == null) {
      return;
    }

    final currentUserId = _authService.getCurrentUser()!.uid;

    try {
      // Show uploading state
      final uploadingImages = [...currentState.uploadingImages, event.imagePath];
      emit(currentState.copyWith(uploadingImages: uploadingImages));

      // Upload image
      final bytes = event.imageBytes ?? await _readImageBytes(event.imagePath);
      if (bytes == null) {
        emit(const EditProfileError('Failed to read image file'));
        return;
      }

      final pathParts = event.imagePath.split(RegExp(r'[\\/]'));
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${pathParts.isNotEmpty ? pathParts.last : 'profile.jpg'}';
      final url = await _storageService.uploadProfileImage(
        bytes: bytes,
        uid: currentUserId,
        filename: fileName,
      );

      final previousProfile = _currentProfile!;
      final currentImages = previousProfile.profileImages ?? [];
      final updatedImages = [...currentImages, url];
      final mergedProfile = previousProfile.copyWith(
        profileImages: updatedImages,
        profilePictureUrl: event.setAsProfilePicture ? url : previousProfile.profilePictureUrl,
      );
      final photoChanges = <String, dynamic>{
        'profileImages': updatedImages,
        ...buildProfileCompletionSnapshot(
          mergedProfile,
          updatedAt: Timestamp.now(),
        ),
      };

      if (event.setAsProfilePicture) {
        photoChanges['profilePictureUrl'] = url;
      }
      await _userService.updateUser(previousProfile.uid, photoChanges);

      _currentProfile = mergedProfile;

      // Remove from uploading
      uploadingImages.remove(event.imagePath);

      emit(
        currentState.copyWith(
          profile: _currentProfile!,
          unsavedChanges: Map.from(_changes),
          uploadingImages: uploadingImages,
          hasChanges: _changes.isNotEmpty,
          noticeMessage: event.setAsProfilePicture
              ? 'Profile picture uploaded successfully.'
              : 'Photo successfully uploaded.',
          isErrorNotice: false,
          noticeVersion: currentState.noticeVersion + 1,
        ),
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('[EditProfileBloc] _onUploadImage error: $e\n$st');
      final failedUploads = [...currentState.uploadingImages]..remove(event.imagePath);
      emit(
        currentState.copyWith(
          uploadingImages: failedUploads,
          noticeMessage: event.setAsProfilePicture
              ? 'Profile picture upload failed.'
              : 'Photo upload failed.',
          isErrorNotice: true,
          noticeVersion: currentState.noticeVersion + 1,
        ),
      );
    }
  }

  Future<void> _onRemoveImage(
    RemoveProfileImage event,
    Emitter<EditProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! EditProfileLoaded || _currentProfile == null) return;

    try {
      final previousProfile = _currentProfile!;
      final currentImages = previousProfile.profileImages ?? [];
      final updatedImages = currentImages.where((img) => img != event.imageUrl).toList();
      final wasProfilePicture = previousProfile.profilePictureUrl == event.imageUrl;
      final mergedProfile = previousProfile.copyWith(
        profileImages: updatedImages,
        profilePictureUrl: wasProfilePicture ? null : previousProfile.profilePictureUrl,
      );
      final photoChanges = <String, dynamic>{
        'profileImages': updatedImages,
        ...buildProfileCompletionSnapshot(
          mergedProfile,
          updatedAt: Timestamp.now(),
        ),
      };

      // If this was the profile picture, clear it
      if (wasProfilePicture) {
        photoChanges['profilePictureUrl'] = null;
      }

      await _userService.updateUser(previousProfile.uid, photoChanges);

      _currentProfile = mergedProfile;

      emit(
        currentState.copyWith(
          profile: _currentProfile!,
          unsavedChanges: Map.from(_changes),
          hasChanges: _changes.isNotEmpty,
        ),
      );

      // Clean up on Cloudinary (stub - requires backend)
      await _storageService.deleteFileByUrl(event.imageUrl);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[EditProfileBloc] _onRemoveImage error: $e\n$st');
      emit(EditProfileError('Failed to remove image: $e'));
    }
  }

  Future<void> _onSetProfilePicture(
    SetProfilePicture event,
    Emitter<EditProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! EditProfileLoaded || _currentProfile == null) return;

    try {
      await _userService.updateUser(
        _currentProfile!.uid,
        {
          'profilePictureUrl': event.imageUrl,
          ...buildProfileCompletionSnapshot(
            _currentProfile!.copyWith(profilePictureUrl: event.imageUrl),
            updatedAt: Timestamp.now(),
          ),
        },
      );

      _currentProfile = _currentProfile!.copyWith(profilePictureUrl: event.imageUrl);

      emit(
        currentState.copyWith(
          profile: _currentProfile!,
          unsavedChanges: Map.from(_changes),
          hasChanges: _changes.isNotEmpty,
        ),
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('[EditProfileBloc] _onSetProfilePicture error: $e\n$st');
      emit(EditProfileError('Failed to set profile picture: $e'));
    }
  }

  Future<Uint8List?> _readImageBytes(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        return null;
      }
      return await file.readAsBytes();
    } catch (e) {
      if (kDebugMode) debugPrint('[DEBUG] Failed to read image bytes: $e');
      return null;
    }
  }
}

// Helper extension for UserModel
const Object _unset = Object();

extension UserModelCopyWith on UserModel {
  UserModel copyWith({
    String? uid,
    String? fullName,
    Object? email = _unset,
    Object? phone = _unset,
    Object? profileCreatedFor = _unset,
    Object? gender = _unset,
    Object? dateOfBirth = _unset,
    Object? religion = _unset,
    Object? caste = _unset,
    Object? familyDetails = _unset,
    Object? location = _unset,
    Object? education = _unset,
    Object? occupation = _unset,
    Object? income = _unset,
    Object? height = _unset,
    Object? heightUnit = _unset,
    Object? lifestyle = _unset,
    Object? hobbies = _unset,
    Object? aboutMe = _unset,
    Object? profilePictureUrl = _unset,
    Object? profileImages = _unset,
    bool? isVerified,
    bool? isPremium,
  }) {
    final current = this;
    return UserModel(
      uid: uid ?? current.uid,
      fullName: fullName ?? current.fullName,
      email: identical(email, _unset) ? current.email : email as String?,
      phone: identical(phone, _unset) ? current.phone : phone as String?,
      profileCreatedFor: identical(profileCreatedFor, _unset) ? current.profileCreatedFor : profileCreatedFor as String?,
      gender: identical(gender, _unset) ? current.gender : gender as String?,
      dateOfBirth: identical(dateOfBirth, _unset) ? current.dateOfBirth : dateOfBirth as DateTime?,
      age: current.age,
      religion: identical(religion, _unset) ? current.religion : religion as String?,
      caste: identical(caste, _unset) ? current.caste : caste as String?,
      sect: current.sect,
      prayerLevel: current.prayerLevel,
      religiousPracticeLevel: current.religiousPracticeLevel,
      familyDetails: identical(familyDetails, _unset) ? current.familyDetails : familyDetails as String?,
      location: identical(location, _unset) ? current.location : location as Map<String, String>?,
      city: current.city,
      education: identical(education, _unset) ? current.education : education as String?,
      profession: current.profession,
      occupation: identical(occupation, _unset) ? current.occupation : occupation as String?,
      annualIncome: current.annualIncome,
      income: identical(income, _unset) ? current.income : income as String?,
      height: identical(height, _unset) ? current.height : height as double?,
      heightUnit: identical(heightUnit, _unset) ? current.heightUnit : heightUnit as String?,
      maritalStatus: current.maritalStatus,
      lifestyle: identical(lifestyle, _unset) ? current.lifestyle : lifestyle as Map<String, bool>?,
      hobbies: identical(hobbies, _unset) ? current.hobbies : hobbies as List<String>?,
      aboutMe: identical(aboutMe, _unset) ? current.aboutMe : aboutMe as String?,
      lookingFor: current.lookingFor,
      preferredFamilyType: current.preferredFamilyType,
      familyType: current.familyType,
      fatherName: current.fatherName,
      fatherOccupation: current.fatherOccupation,
      motherName: current.motherName,
      motherOccupation: current.motherOccupation,
      numberOfSisters: current.numberOfSisters,
      numberOfBrothers: current.numberOfBrothers,
      profilePictureUrl: identical(profilePictureUrl, _unset) ? current.profilePictureUrl : profilePictureUrl as String?,
      profilePhotoUrl: current.profilePhotoUrl,
      profileImages: identical(profileImages, _unset) ? current.profileImages : profileImages as List<String>?,
      photos: current.photos,
      hidePhoto: current.hidePhoto,
      profilePrivacy: current.profilePrivacy,
      profileCompletion: current.profileCompletion,
      profileSetupCompleted: current.profileSetupCompleted,
      profileCompletionUpdatedAt: current.profileCompletionUpdatedAt,
      isVerified: isVerified ?? current.isVerified,
      isPremium: isPremium ?? current.isPremium,
      isOnline: current.isOnline,
      lastSeenAt: current.lastSeenAt,
      createdAt: current.createdAt,
      updatedAt: current.updatedAt,
    );
  }
}
