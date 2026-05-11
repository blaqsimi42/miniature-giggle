import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../models/interaction_models.dart';
import '../../models/user_model.dart';
import '../../services/user_service.dart';
import '../../services/interactions_service.dart';
import '../../services/auth_service.dart';

// Events
abstract class DiscoverProfileEvent extends Equatable {
  const DiscoverProfileEvent();

  @override
  List<Object?> get props => [];
}

class LoadDiscoverProfiles extends DiscoverProfileEvent {
  final String? gender;
  final int? minAge;
  final int? maxAge;
  final String? city;
  final String? religion;
  final String? education;

  const LoadDiscoverProfiles({
    this.gender,
    this.minAge,
    this.maxAge,
    this.city,
    this.religion,
    this.education,
  });

  @override
  List<Object?> get props => [gender, minAge, maxAge, city, religion, education];
}

class LoadMoreProfiles extends DiscoverProfileEvent {
  const LoadMoreProfiles();
}

class SendInterestToProfile extends DiscoverProfileEvent {
  final String targetUserId;
  final String? message;

  const SendInterestToProfile(
    this.targetUserId, {
    this.message,
  });

  @override
  List<Object?> get props => [targetUserId, message];
}

class LikeProfile extends DiscoverProfileEvent {
  final String profileUserId;

  const LikeProfile(this.profileUserId);

  @override
  List<Object?> get props => [profileUserId];
}

class UnlikeProfile extends DiscoverProfileEvent {
  final String profileUserId;
  final String? successMessage;

  const UnlikeProfile(
    this.profileUserId, {
    this.successMessage,
  });

  @override
  List<Object?> get props => [profileUserId, successMessage];
}

class AddToShortlist extends DiscoverProfileEvent {
  final String profileUserId;
  final String? notes;

  const AddToShortlist(
    this.profileUserId, {
    this.notes,
  });

  @override
  List<Object?> get props => [profileUserId, notes];
}

class RemoveFromShortlist extends DiscoverProfileEvent {
  final String profileUserId;
  final String? successMessage;

  const RemoveFromShortlist(
    this.profileUserId, {
    this.successMessage,
  });

  @override
  List<Object?> get props => [profileUserId, successMessage];
}

class RecordProfileView extends DiscoverProfileEvent {
  final String profileUserId;

  const RecordProfileView(this.profileUserId);

  @override
  List<Object?> get props => [profileUserId];
}

// States
abstract class DiscoverProfileState extends Equatable {
  const DiscoverProfileState();

  @override
  List<Object?> get props => [];
}

class DiscoverProfileInitial extends DiscoverProfileState {
  const DiscoverProfileInitial();
}

class DiscoverProfileLoading extends DiscoverProfileState {
  const DiscoverProfileLoading();
}

class DiscoverProfileLoaded extends DiscoverProfileState {
  final List<UserModel> profiles;
  final bool hasMoreProfiles;
  final Map<String, bool> likedProfiles; // profileId -> liked
  final Map<String, bool> shortlistedProfiles; // profileId -> shortlisted
  final Map<String, bool> interestSent; // profileId -> interest sent
  final String? feedbackMessage;
  final bool feedbackIsError;
  final int feedbackKey;

  const DiscoverProfileLoaded({
    required this.profiles,
    this.hasMoreProfiles = true,
    this.likedProfiles = const {},
    this.shortlistedProfiles = const {},
    this.interestSent = const {},
    this.feedbackMessage,
    this.feedbackIsError = false,
    this.feedbackKey = 0,
  });

  @override
  List<Object?> get props =>
      [
        profiles,
        hasMoreProfiles,
        likedProfiles,
        shortlistedProfiles,
        interestSent,
        feedbackMessage,
        feedbackIsError,
        feedbackKey,
      ];

  DiscoverProfileLoaded copyWith({
    List<UserModel>? profiles,
    bool? hasMoreProfiles,
    Map<String, bool>? likedProfiles,
    Map<String, bool>? shortlistedProfiles,
    Map<String, bool>? interestSent,
    String? feedbackMessage,
    bool? feedbackIsError,
    int? feedbackKey,
    bool clearFeedback = false,
  }) {
    return DiscoverProfileLoaded(
      profiles: profiles ?? this.profiles,
      hasMoreProfiles: hasMoreProfiles ?? this.hasMoreProfiles,
      likedProfiles: likedProfiles ?? this.likedProfiles,
      shortlistedProfiles: shortlistedProfiles ?? this.shortlistedProfiles,
      interestSent: interestSent ?? this.interestSent,
      feedbackMessage: clearFeedback ? null : (feedbackMessage ?? this.feedbackMessage),
      feedbackIsError: clearFeedback ? false : (feedbackIsError ?? this.feedbackIsError),
      feedbackKey: clearFeedback ? this.feedbackKey : (feedbackKey ?? this.feedbackKey),
    );
  }
}

class DiscoverProfileError extends DiscoverProfileState {
  final String message;

  const DiscoverProfileError(this.message);

  @override
  List<Object?> get props => [message];
}

// Bloc
class DiscoverProfileBloc extends Bloc<DiscoverProfileEvent, DiscoverProfileState> {
  final UserService _userService;
  final InteractionsService _interactionsService;
  final AuthService _authService;

  String? _currentUserId;
  String? _gender;
  int? _minAge;
  int? _maxAge;
  String? _city;
  String? _religion;
  String? _education;
  List<UserModel> _allProfiles = [];
  List<String> _likedProfiles = [];
  List<String> _shortlistedProfiles = [];
  List<String> _sentInterests = [];
  int _feedbackCounter = 0;
  StreamSubscription<List<String>>? _likedProfilesSub;
  StreamSubscription<List<ShortlistModel>>? _shortlistedProfilesSub;
  StreamSubscription<List<InterestModel>>? _sentInterestsSub;

  DiscoverProfileBloc({
    required UserService userService,
    required InteractionsService interactionsService,
    required AuthService authService,
  })  : _userService = userService,
        _interactionsService = interactionsService,
        _authService = authService,
        super(const DiscoverProfileInitial()) {
    on<LoadDiscoverProfiles>(_onLoadProfiles);
    on<LoadMoreProfiles>(_onLoadMoreProfiles);
    on<SendInterestToProfile>(_onSendInterest);
    on<LikeProfile>(_onLikeProfile);
    on<UnlikeProfile>(_onUnlikeProfile);
    on<AddToShortlist>(_onAddToShortlist);
    on<RemoveFromShortlist>(_onRemoveFromShortlist);
    on<RecordProfileView>(_onRecordProfileView);
  }

  Future<void> _onLoadProfiles(
    LoadDiscoverProfiles event,
    Emitter<DiscoverProfileState> emit,
  ) async {
    emit(const DiscoverProfileLoading());
    try {
      _currentUserId = _authService.getCurrentUser()?.uid;
      if (_currentUserId == null) {
        emit(const DiscoverProfileError('User not authenticated'));
        return;
      }

      // Store filters for pagination
      _gender = event.gender;
      _minAge = event.minAge;
      _maxAge = event.maxAge;
      _city = event.city;
      _religion = event.religion;
      _education = event.education;

      // Fetch profiles
      _allProfiles = await _userService.getDiscoverProfiles(
        currentUserId: _currentUserId,
        gender: _gender,
        minAge: _minAge,
        maxAge: _maxAge,
        city: _city,
        religion: _religion,
        education: _education,
        limit: 20,
      );

      // Load interaction states
      await _loadInteractionStates();

      emit(
        DiscoverProfileLoaded(
          profiles: _allProfiles,
          hasMoreProfiles: _allProfiles.length >= 20,
          likedProfiles: {
            for (final id in _likedProfiles) id: true,
          },
          shortlistedProfiles: {
            for (final id in _shortlistedProfiles) id: true,
          },
          interestSent: {
            for (final id in _sentInterests) id: true,
          },
        ),
      );
    } catch (e) {
      emit(DiscoverProfileError('Failed to load profiles: $e'));
    }
  }

  Future<void> _onLoadMoreProfiles(
    LoadMoreProfiles event,
    Emitter<DiscoverProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DiscoverProfileLoaded) return;

    try {
      // Fetch more profiles (in real app, implement pagination)
      final moreProfiles = await _userService.getDiscoverProfiles(
        currentUserId: _currentUserId,
        gender: _gender,
        minAge: _minAge,
        maxAge: _maxAge,
        city: _city,
        religion: _religion,
        education: _education,
        limit: 20,
      );

      final updatedProfiles = [...currentState.profiles, ...moreProfiles];

      emit(
        currentState.copyWith(
          profiles: updatedProfiles,
          hasMoreProfiles: moreProfiles.length >= 20,
        ),
      );
    } catch (e) {
      emit(DiscoverProfileError('Failed to load more profiles: $e'));
    }
  }

  Future<void> _onSendInterest(
    SendInterestToProfile event,
    Emitter<DiscoverProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DiscoverProfileLoaded || _currentUserId == null) return;

    try {
      await _interactionsService.sendInterest(
        _currentUserId!,
        event.targetUserId,
        message: event.message,
      );

      _sentInterests.add(event.targetUserId);

      emit(
        currentState.copyWith(
          interestSent: {
            ...currentState.interestSent,
            event.targetUserId: true,
          },
          feedbackMessage: 'Interest sent successfully.',
          feedbackIsError: false,
          feedbackKey: ++_feedbackCounter,
        ),
      );
    } catch (e) {
      emit(
        currentState.copyWith(
          feedbackMessage: 'Failed to send interest: $e',
          feedbackIsError: true,
          feedbackKey: ++_feedbackCounter,
        ),
      );
    }
  }

  Future<void> _onLikeProfile(
    LikeProfile event,
    Emitter<DiscoverProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DiscoverProfileLoaded || _currentUserId == null) return;

    try {
      await _interactionsService.likeProfile(_currentUserId!, event.profileUserId);

      _likedProfiles.add(event.profileUserId);

      emit(
        currentState.copyWith(
          likedProfiles: {
            ...currentState.likedProfiles,
            event.profileUserId: true,
          },
          feedbackMessage: 'Profile liked',
          feedbackIsError: false,
          feedbackKey: ++_feedbackCounter,
        ),
      );
    } catch (e) {
      emit(
        currentState.copyWith(
          feedbackMessage: 'Failed to like profile: $e',
          feedbackIsError: true,
          feedbackKey: ++_feedbackCounter,
        ),
      );
    }
  }

  Future<void> _onUnlikeProfile(
    UnlikeProfile event,
    Emitter<DiscoverProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DiscoverProfileLoaded || _currentUserId == null) return;

    try {
      await _interactionsService.unlikeProfile(_currentUserId!, event.profileUserId);

      _likedProfiles.remove(event.profileUserId);

      final updatedLiked = Map<String, bool>.from(currentState.likedProfiles);
      updatedLiked.remove(event.profileUserId);

      emit(
        currentState.copyWith(
          likedProfiles: updatedLiked,
          feedbackMessage: event.successMessage ?? 'Profile unliked',
          feedbackIsError: false,
          feedbackKey: ++_feedbackCounter,
        ),
      );
    } catch (e) {
      emit(
        currentState.copyWith(
          feedbackMessage: 'Failed to unlike profile: $e',
          feedbackIsError: true,
          feedbackKey: ++_feedbackCounter,
        ),
      );
    }
  }

  Future<void> _onAddToShortlist(
    AddToShortlist event,
    Emitter<DiscoverProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DiscoverProfileLoaded || _currentUserId == null) return;

    try {
      await _interactionsService.addToShortlist(
        _currentUserId!,
        event.profileUserId,
        notes: event.notes,
      );

      _shortlistedProfiles.add(event.profileUserId);

      emit(
        currentState.copyWith(
          shortlistedProfiles: {
            ...currentState.shortlistedProfiles,
            event.profileUserId: true,
          },
          feedbackMessage: 'Profile saved',
          feedbackIsError: false,
          feedbackKey: ++_feedbackCounter,
        ),
      );
    } catch (e) {
      emit(
        currentState.copyWith(
          feedbackMessage: 'Failed to save profile: $e',
          feedbackIsError: true,
          feedbackKey: ++_feedbackCounter,
        ),
      );
    }
  }

  Future<void> _onRemoveFromShortlist(
    RemoveFromShortlist event,
    Emitter<DiscoverProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DiscoverProfileLoaded || _currentUserId == null) return;

    try {
      await _interactionsService.removeFromShortlist(
        _currentUserId!,
        event.profileUserId,
      );

      _shortlistedProfiles.remove(event.profileUserId);

      final updatedShortlist =
          Map<String, bool>.from(currentState.shortlistedProfiles);
      updatedShortlist.remove(event.profileUserId);

      emit(
        currentState.copyWith(
          shortlistedProfiles: updatedShortlist,
          feedbackMessage: event.successMessage ?? 'Profile unsaved',
          feedbackIsError: false,
          feedbackKey: ++_feedbackCounter,
        ),
      );
    } catch (e) {
      emit(
        currentState.copyWith(
          feedbackMessage: 'Failed to remove saved profile: $e',
          feedbackIsError: true,
          feedbackKey: ++_feedbackCounter,
        ),
      );
    }
  }

  Future<void> _onRecordProfileView(
    RecordProfileView event,
    Emitter<DiscoverProfileState> emit,
  ) async {
    if (_currentUserId == null) return;

    try {
      await _interactionsService.recordProfileView(_currentUserId!, event.profileUserId);
    } catch (e) {
      // Don't emit error for view tracking failure
      if (kDebugMode) debugPrint('[DEBUG] Failed to record profile view: $e');
    }
  }

  Future<void> _loadInteractionStates() async {
    if (_currentUserId == null) return;

    try {
      await _likedProfilesSub?.cancel();
      await _shortlistedProfilesSub?.cancel();
      await _sentInterestsSub?.cancel();

      // Load liked profiles
      final likedStream = _interactionsService.getLikedProfiles(_currentUserId!);
      _likedProfilesSub = likedStream.listen(
        (liked) {
          _likedProfiles = liked;
        },
        onError: (error, stackTrace) {
          if (kDebugMode) {
            debugPrint('[DEBUG] Failed to listen to liked profiles: $error');
          }
        },
      );

      // Load shortlisted profiles
      final shortlistStream =
          _interactionsService.getShortlistedProfiles(_currentUserId!);
      _shortlistedProfilesSub = shortlistStream.listen(
        (shortlisted) {
          _shortlistedProfiles = shortlisted
              .map((s) => s.shortlistedUserId)
              .toList();
        },
        onError: (error, stackTrace) {
          if (kDebugMode) {
            debugPrint('[DEBUG] Failed to listen to shortlisted profiles: $error');
          }
        },
      );

      // Load sent interests
      final interestsStream =
          _interactionsService.getSentInterests(_currentUserId!);
      _sentInterestsSub = interestsStream.listen(
        (interests) {
          _sentInterests = interests.map((i) => i.receiverId).toList();
        },
        onError: (error, stackTrace) {
          if (kDebugMode) {
            debugPrint('[DEBUG] Failed to listen to sent interests: $error');
          }
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[DEBUG] Failed to load interaction states: $e');
    }
  }

  @override
  Future<void> close() async {
    await _likedProfilesSub?.cancel();
    await _shortlistedProfilesSub?.cancel();
    await _sentInterestsSub?.cancel();
    return super.close();
  }
}
