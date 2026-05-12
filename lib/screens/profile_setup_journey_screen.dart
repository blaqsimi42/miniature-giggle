import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user_model.dart';
import '../services/profile_completion_gate_service.dart';
import '../services/storage_service.dart';
import '../services/user_service.dart';
import '../utils/profile_completion.dart';
import '../widgets/profile_completion_widgets.dart';
import '../core/utils/currency_formatter.dart';

const List<String> _kSectOptions = [
  'Sunni',
  'Shia',
  'Other',
  'Prefer not to say',
];
const List<String> _kPrayerOptions = [
  'Regular',
  'Sometimes',
  'Learning',
  'Prefer not to say',
];
const List<String> _kPracticeOptions = [
  'Very practicing',
  'Moderately practicing',
  'Learning and improving',
  'Prefer not to say',
];
final List<String> _kIncomeOptions = [
  'Less than ${CurrencyFormatter.format(500000)}',
  '${CurrencyFormatter.format(500000)} - ${CurrencyFormatter.format(1000000)}',
  '${CurrencyFormatter.format(1000000)} - ${CurrencyFormatter.format(3000000)}',
  '${CurrencyFormatter.format(3000000)} - ${CurrencyFormatter.format(5000000)}',
  'Above ${CurrencyFormatter.format(5000000)}',
  'Prefer not to say',
];
const List<String> _kMaritalStatusOptions = [
  'Never married',
  'Divorced',
  'Widowed',
  'Prefer not to say',
];
const List<String> _kFamilyTypeOptions = [
  'Nuclear family',
  'Extended family',
  'Joint family',
  'Prefer not to say',
];
const List<String> _kLookingForOptions = [
  'Marriage soon',
  'Marriage within 1 year',
  'Getting to know seriously',
  'Family-involved process',
  'Practicing Muslim partner',
  'Educated partner',
  'Career-focused partner',
];
const List<String> _kPrivacyOptions = [
  'Show my profile to everyone',
  'Show only to verified users',
  'Show only after I approve interest',
  'Hide my photo until I accept request',
];

class ProfileSetupJourneyScreen extends StatefulWidget {
  const ProfileSetupJourneyScreen({super.key});

  @override
  State<ProfileSetupJourneyScreen> createState() => _ProfileSetupJourneyScreenState();
}

class _ProfileSetupJourneyScreenState extends State<ProfileSetupJourneyScreen> {
  final _userService = UserService();
  final _storageService = StorageService();
  final _imagePicker = ImagePicker();

  final _fullNameController = TextEditingController();
  final _dobController = TextEditingController();
  final _cityController = TextEditingController();
  final _educationController = TextEditingController();
  final _professionController = TextEditingController();
  final _heightController = TextEditingController();
  final _fatherNameController = TextEditingController();
  final _fatherOccupationController = TextEditingController();
  final _motherNameController = TextEditingController();
  final _motherOccupationController = TextEditingController();
  final _disciplineController = TextEditingController();
  final _collegeController = TextEditingController();
  final _aboutController = TextEditingController();

  UserModel? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _didLoadProfile = false;
  int _currentStep = 0;
  DateTime? _dob;
  String? _gender;
  String? _religion = 'Islam';
  String? _sect;
  String? _prayerLevel;
  String? _religiousPracticeLevel;
  String? _annualIncome;
  String? _maritalStatus;
  String? _familyType;
  String? _preferredFamilyType;
  String? _profilePrivacy;
  bool _hidePhoto = false;
  String? _caste;
  String? _degree;
  int? _sistersCount;
  int? _brothersCount;
  List<String> _lookingFor = <String>[];
  List<String> _photos = <String>[];
  Map<String, String> _errors = <String, String>{};

  @override
  void dispose() {
    _fullNameController.dispose();
    _dobController.dispose();
    _cityController.dispose();
    _educationController.dispose();
    _professionController.dispose();
    _heightController.dispose();
    _fatherNameController.dispose();
    _fatherOccupationController.dispose();
    _motherNameController.dispose();
    _motherOccupationController.dispose();
    _disciplineController.dispose();
    _collegeController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadProfile) return;
    _didLoadProfile = true;
    unawaited(_loadProfile());
  }

  Future<void> _loadProfile() async {
    final args = ModalRoute.of(context)?.settings.arguments;
    final initialStepArg = args is Map ? args['initialStep'] as int? : null;
    final profile = await ProfileCompletionGateService.loadCurrentProfile();
    if (!mounted) return;
    _profile = profile;
    _fullNameController.text = profile?.fullName ?? '';
    _dob = profile?.dateOfBirth;
    _dobController.text = _dob == null ? '' : _formatDate(_dob!);
    _gender = profile?.gender;
    _cityController.text = profile?.city ?? profile?.location?['city'] ?? '';
    _religion = profile?.religion?.trim().isNotEmpty == true ? profile!.religion : 'Islam';
    _sect = profile?.sect;
    _caste = profile?.caste;
    _prayerLevel = profile?.prayerLevel;
    _religiousPracticeLevel = profile?.religiousPracticeLevel;
    _educationController.text = profile?.education ?? '';
    _professionController.text = profile?.profession ?? profile?.occupation ?? '';
    _annualIncome = profile?.annualIncome ?? profile?.income;
    _heightController.text = profile?.height?.toString() ?? '';
    _maritalStatus = profile?.maritalStatus;
    _fatherNameController.text = profile?.fatherName ?? '';
    _fatherOccupationController.text = profile?.fatherOccupation ?? '';
    _motherNameController.text = profile?.motherName ?? '';
    _motherOccupationController.text = profile?.motherOccupation ?? '';
    _sistersCount = profile?.numberOfSisters;
    _brothersCount = profile?.numberOfBrothers;
    final profileMap = _profile?.toPublicMap();
    _degree = profileMap != null ? (profileMap['degree'] as String?) : null;
    _disciplineController.text = profileMap != null ? (profileMap['discipline'] as String? ?? '') : '';
    _collegeController.text = profileMap != null ? (profileMap['college'] as String? ?? '') : '';
    _familyType = profile?.familyType;
    _aboutController.text = profile?.aboutMe ?? '';
    _lookingFor = [...?profile?.lookingFor];
    _preferredFamilyType = profile?.preferredFamilyType;
    _photos = {...?profile?.photos, ...?profile?.profileImages}.toList();
    _hidePhoto = profile?.hidePhoto ?? false;
    _profilePrivacy = profile?.profilePrivacy;
    _currentStep = (initialStepArg ?? inferJourneyStep(profile)).clamp(0, 5);
    _loading = false;
    setState(() {});
  }

  String _formatDate(DateTime value) {
    final mm = value.month.toString().padLeft(2, '0');
    final dd = value.day.toString().padLeft(2, '0');
    return '${value.year}-$mm-$dd';
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(1998, 1, 1),
      firstDate: DateTime(1960),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
    );
    if (selected == null) return;
    setState(() {
      _dob = selected;
      _dobController.text = _formatDate(selected);
    });
  }

  Future<void> _pickPhoto() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    if (!mounted) return;

    setState(() => _saving = true);
    try {
      final Uint8List bytes = await image.readAsBytes();
      if (!mounted) return;
      final filename = '${DateTime.now().millisecondsSinceEpoch}_${image.name}';
      final url = await _storageService.uploadProfileImage(
        bytes: bytes,
        uid: authUser.uid,
        filename: filename,
        context: context,
      );
      final nextPhotos = {..._photos, url}.toList();
      _photos = nextPhotos;
      await _saveProgress(extraData: {
        'profileImages': nextPhotos,
        'photos': nextPhotos,
        'profilePictureUrl': (_profile?.profilePictureUrl?.trim().isNotEmpty == true)
            ? _profile!.profilePictureUrl
            : url,
        'profilePhotoUrl': (_profile?.profilePhotoUrl?.trim().isNotEmpty == true)
            ? _profile!.profilePhotoUrl
            : url,
      }, showSuccess: false);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  bool _validateCurrentStep() {
    final errors = <String, String>{};
    switch (_currentStep) {
      case 0:
        if (_fullNameController.text.trim().isEmpty) errors['fullName'] = 'Full name is required.';
        if (_dob == null) errors['dob'] = 'Date of birth is required.';
        if ((_gender ?? '').trim().isEmpty) errors['gender'] = 'Gender is required.';
        if (_cityController.text.trim().isEmpty) errors['city'] = 'City or location is required.';
        break;
      case 1:
        if ((_religion ?? '').trim().isEmpty) errors['religion'] = 'Religion is required.';
        if ((_sect ?? '').trim().isEmpty) errors['sect'] = 'Sect is required.';
        if ((_prayerLevel ?? '').trim().isEmpty) errors['prayerLevel'] = 'Prayer level is required.';
        if ((_religiousPracticeLevel ?? '').trim().isEmpty) {
          errors['religiousPracticeLevel'] = 'Religious practice level is required.';
        }
        break;
      case 2:
        if (_educationController.text.trim().isEmpty) errors['education'] = 'Education is required.';
        if (_professionController.text.trim().isEmpty) errors['profession'] = 'Profession is required.';
        if (_heightController.text.trim().isEmpty) errors['height'] = 'Height is required.';
        if ((_maritalStatus ?? '').trim().isEmpty) errors['maritalStatus'] = 'Marital status is required.';
        break;
      case 4:
        final aboutWords = _aboutController.text.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
        if (aboutWords < 20) errors['aboutMe'] = 'Write at least 20 words about yourself.';
        if (_lookingFor.isEmpty) errors['lookingFor'] = 'Choose at least one preference.';
        break;
      case 5:
        if (_photos.isEmpty) errors['photos'] = 'Add at least one photo before completing your profile.';
        break;
    }
    setState(() => _errors = errors);
    return errors.isEmpty;
  }

  Future<void> _saveProgress({
    Map<String, dynamic>? extraData,
    bool showSuccess = true,
  }) async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;
    final uid = authUser.uid;
    final height = double.tryParse(_heightController.text.trim());
    final age = calculateAgeFromDob(_dob);
    final payload = <String, dynamic>{
      'uid': uid,
      'fullName': _fullNameController.text.trim(),
      'dateOfBirth': _dob != null ? Timestamp.fromDate(_dob!) : null,
      'age': age,
      'gender': _gender,
      'city': _cityController.text.trim(),
      'location': _cityController.text.trim().isEmpty
          ? null
          : {
              'city': _cityController.text.trim(),
            },
      'religion': _religion,
      'sect': _sect,
      'caste': _caste,
      'prayerLevel': _prayerLevel,
      'religiousPracticeLevel': _religiousPracticeLevel,
      'education': _educationController.text.trim(),
      'degree': _degree,
      'discipline': _disciplineController.text.trim(),
      'college': _collegeController.text.trim(),
      'profession': _professionController.text.trim(),
      'occupation': _professionController.text.trim(),
      'annualIncome': _annualIncome,
      'income': _annualIncome,
      'height': height,
      'maritalStatus': _maritalStatus,
      'fatherName': _fatherNameController.text.trim(),
      'fatherOccupation': _fatherOccupationController.text.trim(),
      'motherName': _motherNameController.text.trim(),
      'motherOccupation': _motherOccupationController.text.trim(),
      'numberOfSisters': _sistersCount,
      'numberOfBrothers': _brothersCount,
      'familyType': _familyType,
      'preferredFamilyType': _preferredFamilyType,
      'aboutMe': _aboutController.text.trim(),
      'lookingFor': _lookingFor,
      'hidePhoto': _hidePhoto,
      'profilePrivacy': _profilePrivacy,
      'updatedAt': Timestamp.now(),
      ...?extraData,
    }..removeWhere((key, value) => value == null);

    final mergedProfile = UserModel.fromMaps({
      ...?_profile?.toPublicMap(),
      ...payload,
      'email': _profile?.email,
      'phone': _profile?.phone,
      'createdAt': _profile?.createdAt ?? Timestamp.now(),
    });
    payload.addAll(
      buildProfileCompletionSnapshot(
        mergedProfile,
        updatedAt: Timestamp.now(),
      ),
    );

    if (_profile == null) {
      await _userService.createUserProfile(UserModel.fromMaps({
        ...payload,
        'email': authUser.email ?? _profile?.email,
        'phone': authUser.phoneNumber ?? _profile?.phone,
        'profilePictureUrl': payload['profilePictureUrl'] ?? authUser.photoURL,
        'profilePhotoUrl': payload['profilePhotoUrl'] ?? authUser.photoURL,
      }));
    } else {
      await _userService.updateUser(uid, payload);
    }
    _profile = await _userService.getUser(uid) ?? mergedProfile;
    if (mounted && showSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Progress saved')),
      );
    }
  }

  Future<void> _goNext() async {
    if (!_validateCurrentStep()) return;
    setState(() => _saving = true);
    try {
      await _saveProgress();
      if (!mounted) return;
      if (_currentStep < 5) {
        setState(() {
          _currentStep += 1;
          _errors = <String, String>{};
        });
      } else {
        final completion = calculateWeightedProfileCompletion(_profile);
        if (completion.meetsDiscoveryThreshold) {
          if (!mounted) return;
          Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'You are at ${completion.percent}%. Add a little more to reach 70% before discovering matches.',
              ),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _skipFamily() async {
    setState(() => _saving = true);
    try {
      await _saveProgress(showSuccess: false);
      if (!mounted) return;
      setState(() {
        _currentStep = 4;
        _errors = <String, String>{};
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildStepBody() {
    switch (_currentStep) {
      case 0:
        return Column(
          children: [
            ProfileSetupTextField(
              controller: _fullNameController,
              label: 'Full name',
              errorText: _errors['fullName'],
            ),
            const SizedBox(height: 14),
            ProfileSetupTextField(
              controller: _dobController,
              label: 'Date of birth',
              hint: 'Select your date of birth',
              readOnly: true,
              onTap: _pickDate,
              errorText: _errors['dob'],
            ),
            const SizedBox(height: 14),
            ProfileSetupDropdown<String>(
              label: 'Gender',
              value: _gender,
              errorText: _errors['gender'],
              onChanged: (value) => setState(() => _gender = value),
              items: const ['Male', 'Female', 'Other']
                  .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
            ),
            const SizedBox(height: 14),
            ProfileSetupTextField(
              controller: _cityController,
              label: 'City / location',
              errorText: _errors['city'],
            ),
          ],
        );
      case 1:
        return Column(
          children: [
            ProfileSetupDropdown<String>(
              label: 'Religion',
              value: _religion,
              errorText: _errors['religion'],
              onChanged: (value) => setState(() => _religion = value),
              items: const ['Islam']
                  .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
            ),
            const SizedBox(height: 14),
            ProfileSetupDropdown<String>(
              label: 'Sect',
              value: _sect,
              errorText: _errors['sect'],
              onChanged: (value) => setState(() => _sect = value),
              items: _kSectOptions
                  .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
            ),
            const SizedBox(height: 14),
            ProfileSetupDropdown<String>(
              label: 'Caste',
              value: _caste,
              errorText: _errors['caste'],
              onChanged: (value) => setState(() => _caste = value),
              items: ['Prefer not to say', 'Syed', 'Sheikh', 'Other']
                  .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
            ),
            const SizedBox(height: 14),
            ProfileSetupDropdown<String>(
              label: 'Prayer level',
              value: _prayerLevel,
              errorText: _errors['prayerLevel'],
              onChanged: (value) => setState(() => _prayerLevel = value),
              items: _kPrayerOptions
                  .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
            ),
            const SizedBox(height: 14),
            ProfileSetupDropdown<String>(
              label: 'Religious practice level',
              value: _religiousPracticeLevel,
              errorText: _errors['religiousPracticeLevel'],
              onChanged: (value) => setState(() => _religiousPracticeLevel = value),
              items: _kPracticeOptions
                  .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
            ),
          ],
        );
      case 2:
        return Column(
          children: [
            ProfileSetupTextField(
              controller: _educationController,
              label: 'Education',
              errorText: _errors['education'],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ProfileSetupDropdown<String>(
                    label: 'Degree',
                    value: _degree,
                    onChanged: (v) => setState(() => _degree = v),
                    items: const [
                      'High School',
                      'Diploma',
                      'Bachelor\'s',
                      'Master\'s',
                      'PhD',
                      'Other',
                    ].map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ProfileSetupTextField(
                    controller: _disciplineController,
                    label: 'Discipline / Course',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ProfileSetupTextField(
              controller: _professionController,
              label: 'Profession',
              errorText: _errors['profession'],
            ),
            const SizedBox(height: 14),
            ProfileSetupTextField(
              controller: _collegeController,
              label: 'College / Institution',
            ),
            const SizedBox(height: 14),
            ProfileSetupDropdown<String>(
              label: 'Annual income',
              value: _annualIncome,
              onChanged: (value) => setState(() => _annualIncome = value),
              items: _kIncomeOptions
                  .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
            ),
            const SizedBox(height: 14),
            ProfileSetupTextField(
              controller: _heightController,
              label: 'Height',
              hint: 'Example: 5.7',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              errorText: _errors['height'],
            ),
            const SizedBox(height: 14),
            ProfileSetupDropdown<String>(
              label: 'Marital status',
              value: _maritalStatus,
              errorText: _errors['maritalStatus'],
              onChanged: (value) => setState(() => _maritalStatus = value),
              items: _kMaritalStatusOptions
                  .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
            ),
          ],
        );
      case 3:
        return Column(
          children: [
            ProfileSetupTextField(controller: _fatherNameController, label: 'Father’s name'),
            const SizedBox(height: 14),
            ProfileSetupTextField(controller: _fatherOccupationController, label: 'Father’s occupation / status'),
            const SizedBox(height: 14),
            ProfileSetupTextField(controller: _motherNameController, label: 'Mother’s name'),
            const SizedBox(height: 14),
            ProfileSetupTextField(controller: _motherOccupationController, label: 'Mother’s occupation / status'),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ProfileSetupDropdown<int>(
                    label: 'No. of sisters',
                    value: _sistersCount,
                    onChanged: (v) => setState(() => _sistersCount = v),
                    items: List.generate(100, (i) => i + 1)
                        .map((n) => DropdownMenuItem(value: n, child: Text(n.toString())))
                        .toList(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ProfileSetupDropdown<int>(
                    label: 'No. of brothers',
                    value: _brothersCount,
                    onChanged: (v) => setState(() => _brothersCount = v),
                    items: List.generate(100, (i) => i + 1)
                        .map((n) => DropdownMenuItem(value: n, child: Text(n.toString())))
                        .toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ProfileSetupDropdown<String>(
              label: 'Family type',
              value: _familyType,
              onChanged: (value) => setState(() => _familyType = value),
              items: _kFamilyTypeOptions
                  .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
            ),
          ],
        );
      case 4:
        return Column(
          children: [
            ProfileSetupTextField(
              controller: _aboutController,
              label: 'About you',
              maxLines: 5,
              errorText: _errors['aboutMe'],
            ),
            const SizedBox(height: 14),
            ProfileSetupChipSelector(
              label: 'What are you looking for?',
              options: _kLookingForOptions,
              selectedValues: _lookingFor,
              multiSelect: true,
              errorText: _errors['lookingFor'],
              onChanged: (values) => setState(() => _lookingFor = values),
            ),
            const SizedBox(height: 14),
            ProfileSetupDropdown<String>(
              label: 'Preferred family type',
              value: _preferredFamilyType,
              onChanged: (value) => setState(() => _preferredFamilyType = value),
              items: _kFamilyTypeOptions
                  .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
            ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PhotoUploadBox(
              photos: _photos,
              helperText: _errors['photos'],
              onTap: _pickPhoto,
            ),
            const SizedBox(height: 18),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Hide photo',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Keep your photo hidden until you are comfortable sharing it.'),
              value: _hidePhoto,
              onChanged: (value) => setState(() => _hidePhoto = value),
            ),
            const SizedBox(height: 14),
            ProfileSetupDropdown<String>(
              label: 'Profile privacy',
              value: _profilePrivacy,
              onChanged: (value) => setState(() => _profilePrivacy = value),
              items: _kPrivacyOptions
                  .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF7F5F2),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final weighted = calculateWeightedProfileCompletion(_profile);
    final stepMeta = const [
      ('Basic Info', 'Let’s start with who you are.'),
      ('Religious Info', 'Help us understand your values.'),
      ('Personal Info', 'This helps us improve match quality.'),
      ('Family Details', 'Optional, but useful for family-involved matching.'),
      ('About & Preferences', 'Tell future matches what matters to you.'),
      ('Photos & Privacy', 'Control how your profile appears.'),
    ][_currentStep];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F2),
      appBar: AppBar(
        title: const Text('Profile Setup'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFFF7F5F2),
        foregroundColor: const Color(0xFF171717),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileSetupProgressHeader(
                currentStep: _currentStep + 1,
                totalSteps: 6,
                title: stepMeta.$1,
                description: stepMeta.$2,
                percent: weighted.percent,
                trailing: _currentStep == 3
                    ? GestureDetector(
                        onTap: _saving ? null : _skipFamily,
                        child: Text(
                          'Skip for now',
                          style: TextStyle(
                            color: _saving ? const Color(0xFF9CA3AF) : const Color(0xFF0F5C2E),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 18),
              ProfileSetupCard(child: _buildStepBody()),
              const SizedBox(height: 16),
              if (weighted.hasStrongProfile)
                const ProfileSetupCard(
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Color(0xFFD4A84F)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Strong Profile: you are above 90% and ready for stronger visibility.',
                          style: TextStyle(
                            color: Color(0xFF171717),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              if (_currentStep > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => setState(() => _currentStep -= 1),
                    child: const Text('Back'),
                  ),
                ),
              if (_currentStep > 0) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _saving ? null : _goNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F5C2E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    _saving
                        ? 'Saving...'
                        : _currentStep == 5
                            ? 'Complete Profile'
                            : 'Next',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
