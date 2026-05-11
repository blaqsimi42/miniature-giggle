import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../services/otp_service.dart';
import '../core/utils/validation_service.dart';
import '../widgets/app_notice.dart';
import '../bloc/edit_profile_bloc.dart';
import '../services/user_service.dart';
import '../services/storage_service.dart';
import '../services/auth_service.dart';
import '../utils/profile_completion.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/profile_header_card.dart';
import '../widgets/primary_button.dart';
import '../widgets/settings_section_card.dart';
import '../widgets/settings_tile.dart';

class EditProfileScreen extends StatefulWidget {
  final String userId;

  const EditProfileScreen({super.key, required this.userId});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late EditProfileBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = EditProfileBloc(
      userService: UserService(),
      storageService: StorageService(),
      authService: AuthService(),
    );
    _bloc.add(LoadProfileForEditing(widget.userId));
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F2),
      appBar: AppBar(
        title: const Text('Edit Profile'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFFF7F5F2),
        foregroundColor: const Color(0xFF171717),
      ),
      body: BlocProvider.value(
        value: _bloc,
        child: BlocListener<EditProfileBloc, EditProfileState>(
          listenWhen: (previous, current) {
            if (current is EditProfileLoaded) {
              final previousVersion = previous is EditProfileLoaded ? previous.noticeVersion : -1;
              return current.noticeMessage != null && current.noticeVersion != previousVersion;
            }
            return true;
          },
          listener: (context, state) {
            final messenger = ScaffoldMessenger.maybeOf(context);
            if (messenger == null) return;
            if (state is EditProfileSaved) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Profile updated successfully!')),
              );
            } else if (state is EditProfileLoaded && state.noticeMessage != null) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text(state.noticeMessage!),
                  backgroundColor: state.isErrorNotice ? Colors.red[600] : Colors.green[600],
                ),
              );
            } else if (state is EditProfileError) {
              messenger.showSnackBar(
                SnackBar(content: Text('Error: ${state.message}')),
              );
            }
          },
          child: BlocBuilder<EditProfileBloc, EditProfileState>(
                builder: (context, state) {
              if (state is EditProfileLoading) {
                return Center(
                  child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                );
              }

              if (state is EditProfileLoaded) {
                final profile = state.profile;
                final completion = calculateProfileCompletion(profile);
                final subtitle = profile.phone?.trim().isNotEmpty == true
                    ? profile.phone!
                    : profile.email?.trim().isNotEmpty == true
                        ? profile.email!
                        : 'Complete your profile to improve your matches';
                final photoCount = <String>{
                  if (profile.profilePictureUrl?.trim().isNotEmpty == true)
                    profile.profilePictureUrl!.trim(),
                  ...?profile.profileImages
                      ?.map((image) => image.trim())
                      .where((image) => image.isNotEmpty),
                }.length;

                return Stack(
                  children: [
                    AbsorbPointer(
                      absorbing: state.isSaving || state.uploadingImages.isNotEmpty,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ProfileHeaderCard(
                              imageUrl: profile.profilePictureUrl,
                              displayName: profile.fullName,
                              subtitle: subtitle,
                              completionPercent: completion.percent,
                              editIcon: Icons.photo_camera_outlined,
                              onTapAvatar: profile.profilePictureUrl?.trim().isNotEmpty == true
                                  ? () => _showProfileImagePreview(profile.profilePictureUrl!.trim())
                                  : null,
                              onEdit: () => _showPhotoActions(state),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x08000000),
                                    blurRadius: 12,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Profile tune-up',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF171717),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    completion.nextStep,
                                    style: const TextStyle(
                                      color: Color(0xFF6B7280),
                                      height: 1.45,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      _EditStatChip(
                                        icon: Icons.check_circle_outline,
                                        label: '${completion.completedFields}/${completion.totalFields} completed',
                                      ),
                                      _EditStatChip(
                                        icon: Icons.photo_library_outlined,
                                        label: '$photoCount photos added',
                                      ),
                                      _EditStatChip(
                                        icon: Icons.auto_awesome_outlined,
                                        label: state.hasChanges ? 'Unsaved changes' : 'All changes saved',
                                        highlighted: state.hasChanges,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            SettingsSectionCard(
                              title: 'Account & Settings',
                              children: [
                                SettingsTile(
                                  icon: Icons.person,
                                  title: 'Personal Information',
                                  subtitle: profile.fullName,
                                  onTap: () => _showPersonalInformationModal(state),
                                ),
                                const Divider(height: 1),
                                SettingsTile(
                                  icon: Icons.mosque,
                                  title: 'Religious Information',
                                  subtitle: profile.religion?.trim().isNotEmpty == true
                                      ? profile.religion!
                                      : 'Add your religion and cultural details',
                                  onTap: () => _showReligiousInformationModal(state),
                                ),
                                const Divider(height: 1),
                                SettingsTile(
                                  icon: Icons.family_restroom,
                                  title: 'Family Information',
                                  subtitle: profile.familyDetails?.trim().isNotEmpty == true
                                      ? profile.familyDetails!
                                      : 'View and edit family details',
                                  onTap: () => _showFamilyInformationModal(state),
                                ),
                                const Divider(height: 1),
                                SettingsTile(
                                  icon: Icons.school,
                                  title: 'Education & Career',
                                  subtitle: profile.education?.trim().isNotEmpty == true
                                      ? profile.education!
                                      : 'Add your education and work',
                                  onTap: () => _showEducationCareerModal(state),
                                ),
                                const Divider(height: 1),
                                SettingsTile(
                                  icon: Icons.nature_people,
                                  title: 'Lifestyle',
                                  subtitle: (profile.hobbies ?? []).isNotEmpty
                                      ? (profile.hobbies ?? []).join(', ')
                                      : 'Add hobbies and lifestyle',
                                  onTap: () => _showLifestyleModal(state),
                                ),
                                const Divider(height: 1),
                                SettingsTile(
                                  icon: Icons.edit_note,
                                  title: 'About Me',
                                  subtitle: profile.aboutMe?.trim().isNotEmpty == true
                                      ? profile.aboutMe!
                                      : 'Tell people about yourself',
                                  onTap: () => _showAboutMeModal(state),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            SettingsSectionCard(
                              title: 'Media',
                              children: [
                                SettingsTile(
                                  icon: Icons.photo_library,
                                  title: 'Photos',
                                  subtitle: '$photoCount photo${photoCount == 1 ? '' : 's'} added',
                                  onTap: _showManagePhotosModal,
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF7F7),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFF2C7C6)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Danger Zone',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF9F1239),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Need a reset? You can remove your account from here. This action should stay intentional.',
                                    style: TextStyle(
                                      color: Color(0xFF6B7280),
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFB91C1C),
                                      side: const BorderSide(color: Color(0xFFF0A7A4)),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    onPressed: () {},
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Delete Account'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: SafeArea(
                        top: false,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 18,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: const Color(0xFFE5E7EB),
                                  disabledForegroundColor: const Color(0xFF6B7280),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                onPressed: state.hasChanges
                                    ? () => _bloc.add(const SaveProfile())
                                    : null,
                                child: Text(
                                  state.hasChanges ? 'Save Changes' : 'Everything is up to date',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (state.uploadingImages.isNotEmpty)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black26,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(strokeWidth: 3),
                                  ),
                                  SizedBox(height: 14),
                                  Text(
                                    'Photo uploading',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (state.isSaving)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black26,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(strokeWidth: 3),
                                  ),
                                  SizedBox(height: 14),
                                  Text(
                                    'Updating profile',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              }

              if (state is EditProfileError) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                        const SizedBox(height: 16),
                        const Text(
                          'Failed to load profile.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'There was an error retrieving your profile. You can retry or view details below.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                        ),
                        const SizedBox(height: 16),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220, maxWidth: 520),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              state.message,
                              textAlign: TextAlign.left,
                              style: const TextStyle(fontSize: 12, color: Colors.black87),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        PrimaryButton(
                          label: 'Retry',
                          onPressed: () => _bloc.add(LoadProfileForEditing(widget.userId)),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return const SizedBox();
            },
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadProfileImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null || !mounted) return;
    final bytes = await image.readAsBytes();

    _bloc.add(
      UploadProfileImage(
        image.path,
        imageBytes: bytes,
        setAsProfilePicture: true,
      ),
    );
  }

  Future<void> _pickAndUploadAdditionalPhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null || !mounted) return;
    final bytes = await image.readAsBytes();

    _bloc.add(
      UploadProfileImage(
        image.path,
        imageBytes: bytes,
        setAsProfilePicture: false,
      ),
    );
  }

  void _showPhotoActions(EditProfileLoaded state) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_a_photo_outlined),
              title: const Text('New Profile Picture'),
              onTap: () {
                Navigator.of(context).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _pickAndUploadProfileImage();
                  }
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete Photo'),
              enabled: state.profile.profilePictureUrl?.trim().isNotEmpty == true,
              textColor: state.profile.profilePictureUrl?.trim().isNotEmpty == true ? Colors.red : null,
              iconColor: state.profile.profilePictureUrl?.trim().isNotEmpty == true ? Colors.red : null,
              onTap: state.profile.profilePictureUrl?.trim().isNotEmpty == true
                  ? () {
                      Navigator.of(context).pop();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          _bloc.add(RemoveProfileImage(state.profile.profilePictureUrl!.trim()));
                        }
                      });
                    }
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Add Photos'),
              onTap: () {
                Navigator.of(context).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _pickAndUploadAdditionalPhoto();
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showManagePhotosModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => BlocProvider.value(
        value: _bloc,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: BlocBuilder<EditProfileBloc, EditProfileState>(
              builder: (context, state) {
                if (state is! EditProfileLoaded) {
                  return const SizedBox(
                    height: 240,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final profilePictureUrl = state.profile.profilePictureUrl?.trim();
                final images = <String>[
                  if (profilePictureUrl != null && profilePictureUrl.isNotEmpty) profilePictureUrl,
                  ...?state.profile.profileImages?.where((img) => img.trim().isNotEmpty && img.trim() != profilePictureUrl),
                ];

                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Manage Photos',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _pickAndUploadAdditionalPhoto,
                            icon: const Icon(Icons.add_photo_alternate_outlined),
                            label: const Text('Add'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${images.length}/6 photos',
                        style: const TextStyle(color: Color(0xFF6B6B6B)),
                      ),
                      if (state.uploadingImages.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: const [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 12),
                              Expanded(child: Text('Uploading photo...')),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (images.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F7F4),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.photo_library_outlined, size: 36, color: Colors.black45),
                              SizedBox(height: 10),
                              Text('No photos yet'),
                              SizedBox(height: 4),
                              Text(
                                'Add a few photos to complete your profile.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Color(0xFF6B6B6B)),
                              ),
                            ],
                          ),
                        )
                      else
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: images.length,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.84,
                          ),
                          itemBuilder: (context, index) {
                            final imageUrl = images[index];
                            final isMain = imageUrl == profilePictureUrl;
                            return Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                color: const Color(0xFFF3F4F6),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: GestureDetector(
                                            onTap: () => _showProfileImagePreview(imageUrl),
                                            child: ClipRRect(
                                              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                                              child: Image.network(
                                                imageUrl,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: 10,
                                          left: 10,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: isMain ? Theme.of(context).colorScheme.primary : Colors.black54,
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              isMain ? 'Main Photo' : 'Photo',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        if (!isMain)
                                          OutlinedButton.icon(
                                            onPressed: () => _bloc.add(SetProfilePicture(imageUrl)),
                                            icon: const Icon(Icons.star_border_outlined, size: 18),
                                            label: const Text('Set as Main'),
                                          ),
                                        if (!isMain) const SizedBox(height: 8),
                                        FilledButton.tonalIcon(
                                          style: FilledButton.styleFrom(
                                            foregroundColor: Colors.red[700],
                                          ),
                                          onPressed: () => _confirmDeletePhoto(imageUrl),
                                          icon: const Icon(Icons.delete_outline, size: 18),
                                          label: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeletePhoto(String imageUrl) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete photo?'),
        content: const Text('This photo will be removed from your profile.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      _bloc.add(RemoveProfileImage(imageUrl));
    }
  }

  Future<void> _showPersonalInformationModal(EditProfileLoaded state) async {
    final fullNameController = TextEditingController(text: state.profile.fullName);
    final emailController = TextEditingController(text: state.profile.email ?? '');
    final phoneController = TextEditingController(text: state.profile.phone ?? '');
    final profileCreatedForController = TextEditingController(text: state.profile.profileCreatedFor ?? '');
    final genderController = TextEditingController(text: state.profile.gender ?? '');
    final heightController = TextEditingController(
      text: state.profile.height == null
          ? ''
          : state.profile.height!.toStringAsFixed(state.profile.height! % 1 == 0 ? 0 : 1),
    );
    final heightUnitController = TextEditingController(text: state.profile.heightUnit ?? 'ft');
    final cityController = TextEditingController(text: state.profile.location?['city'] ?? '');
    final countryController = TextEditingController(text: state.profile.location?['country'] ?? '');
    final aboutMeController = TextEditingController(text: state.profile.aboutMe ?? '');
    DateTime? selectedDateOfBirth = state.profile.dateOfBirth;
    bool shouldSave = false;
    String? savedFullName;
    String? savedEmail;
    String? savedPhone;
    String? savedProfileCreatedFor;
    String? savedGender;
    DateTime? savedDateOfBirth;
    double? savedHeight;
    String? savedHeightUnit;
    Map<String, String>? savedLocation;
    String? savedAboutMe;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: (MediaQuery.of(context).viewInsets.bottom < 0 ? 0.0 : MediaQuery.of(context).viewInsets.bottom) + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Edit Personal Information',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    controller: fullNameController,
                    labelText: 'Full Name',
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 12),
                  CustomTextField(
                    controller: emailController,
                    labelText: 'Email',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  CustomTextField(
                    controller: phoneController,
                    labelText: 'Phone',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    onChanged: (v) => setModalState(() {}),
                  ),
                  const SizedBox(height: 8),
                  // Show Verify button when entered phone differs from saved phone
                  Builder(builder: (_) {
                    final entered = phoneController.text.trim();
                    final normalized = ValidationService.normalizePhoneNumber(entered.startsWith('+') ? entered : entered) ?? '';
                    final existing = state.profile.phone?.trim() ?? '';
                    final showVerify = normalized.isNotEmpty && normalized != existing;
                    if (!showVerify) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final targetUid = state.profile.uid;
                          final phoneToVerify = normalized;
                          if (phoneToVerify.isEmpty) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              AppNotice.showError(context, 'Invalid phone');
                            });
                            return;
                          }

                          try {
                            final resp = await OtpService.sendOtp(uid: targetUid, phone: phoneToVerify);
                            if (resp['ok'] == true) {
                              if (!mounted) return;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                AppNotice.showSuccess(context, 'Verification code sent.');
                                Navigator.of(context).pushNamed('/verify-phone-link', arguments: {
                                  'phone': phoneToVerify,
                                  'uid': targetUid,
                                  'sentAt': DateTime.now().toIso8601String(),
                                  'returnTo': '/edit-profile',
                                  'returnArgs': {'userId': widget.userId},
                                });
                              });
                            } else {
                              if (!mounted) return;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                AppNotice.showError(context, resp['error'] ?? resp['body'] ?? 'Failed to send verification code.');
                              });
                            }
                          } catch (e) {
                            if (!mounted) return;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              AppNotice.showError(context, e, fallbackMessage: 'Failed to send verification code.');
                            });
                          }
                        },
                        child: const Text('Verify number'),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  CustomTextField(
                    controller: profileCreatedForController,
                    labelText: 'Profile Created For',
                    icon: Icons.groups_2_outlined,
                  ),
                  const SizedBox(height: 12),
                  CustomTextField(
                    controller: genderController,
                    labelText: 'Gender',
                    icon: Icons.wc_outlined,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cake_outlined),
                      title: const Text('Date of Birth'),
                    subtitle: Text(
                      selectedDateOfBirth == null
                          ? 'Select date of birth'
                          : _formatDate(selectedDateOfBirth!),
                    ),
                    trailing: const Icon(Icons.calendar_today_outlined, size: 18),
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDateOfBirth ?? DateTime(now.year - 25),
                        firstDate: DateTime(1950),
                        lastDate: now,
                      );
                      if (picked != null) {
                        setModalState(() => selectedDateOfBirth = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: CustomTextField(
                          controller: heightController,
                          labelText: 'Height',
                          icon: Icons.height_outlined,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CustomTextField(
                          controller: heightUnitController,
                          labelText: 'Height Unit',
                          icon: Icons.straighten_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CustomTextField(
                    controller: cityController,
                    labelText: 'City',
                    icon: Icons.location_city_outlined,
                  ),
                  const SizedBox(height: 12),
                  CustomTextField(
                    controller: countryController,
                    labelText: 'Country',
                    icon: Icons.public_outlined,
                  ),
                  const SizedBox(height: 12),
                  CustomTextField(
                    controller: aboutMeController,
                    labelText: 'About Me',
                    icon: Icons.edit_note_outlined,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final location = <String, String>{};
                            if (cityController.text.trim().isNotEmpty) {
                              location['city'] = cityController.text.trim();
                            }
                            if (countryController.text.trim().isNotEmpty) {
                              location['country'] = countryController.text.trim();
                            }

                            shouldSave = true;
                            savedFullName = fullNameController.text.trim();
                            savedEmail = emailController.text.trim();
                            savedPhone = phoneController.text.trim();
                            savedProfileCreatedFor =
                                profileCreatedForController.text.trim();
                            savedGender = genderController.text.trim();
                            savedDateOfBirth = selectedDateOfBirth;
                            savedHeight = heightController.text.trim().isEmpty
                                ? null
                                : double.tryParse(heightController.text.trim());
                            savedHeightUnit =
                                heightUnitController.text.trim().isEmpty
                                    ? null
                                    : heightUnitController.text.trim();
                            savedLocation =
                                location.isEmpty ? null : location;
                            savedAboutMe = aboutMeController.text.trim().isEmpty
                                ? null
                                : aboutMeController.text.trim();
                            Navigator.of(context).pop();
                          },
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (shouldSave && mounted) {
      _bloc.add(UpdateProfileField('fullName', savedFullName ?? ''));
      _bloc.add(UpdateProfileField('email', savedEmail ?? ''));
      _bloc.add(UpdateProfileField('phone', savedPhone ?? ''));
      _bloc.add(
        UpdateProfileField(
          'profileCreatedFor',
          savedProfileCreatedFor ?? '',
        ),
      );
      _bloc.add(UpdateProfileField('gender', savedGender ?? ''));
      _bloc.add(UpdateProfileField('dateOfBirth', savedDateOfBirth));
      _bloc.add(UpdateProfileField('height', savedHeight));
      _bloc.add(UpdateProfileField('heightUnit', savedHeightUnit));
      _bloc.add(UpdateProfileField('location', savedLocation));
      _bloc.add(UpdateProfileField('aboutMe', savedAboutMe));
      _bloc.add(const SaveProfile());
    }

    fullNameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    profileCreatedForController.dispose();
    genderController.dispose();
    heightController.dispose();
    heightUnitController.dispose();
    cityController.dispose();
    countryController.dispose();
    aboutMeController.dispose();
  }

  Future<void> _showReligiousInformationModal(EditProfileLoaded state) async {
    final religionController = TextEditingController(text: state.profile.religion ?? '');
    final casteController = TextEditingController(text: state.profile.caste ?? '');

    await _showFormModal(
      title: 'Edit Religious Information',
      child: Column(
        children: [
          CustomTextField(
            controller: religionController,
            labelText: 'Religion',
            icon: Icons.mosque_outlined,
          ),
          const SizedBox(height: 12),
          CustomTextField(
            controller: casteController,
            labelText: 'Caste',
            icon: Icons.groups_2_outlined,
          ),
        ],
      ),
      onSave: () {
        _bloc.add(UpdateProfileField(
          'religion',
          religionController.text.trim().isEmpty ? null : religionController.text.trim(),
        ));
        _bloc.add(UpdateProfileField(
          'caste',
          casteController.text.trim().isEmpty ? null : casteController.text.trim(),
        ));
        _bloc.add(const SaveProfile());
      },
    );

    religionController.dispose();
    casteController.dispose();
  }

  Future<void> _showFamilyInformationModal(EditProfileLoaded state) async {
    final familyDetailsController = TextEditingController(text: state.profile.familyDetails ?? '');

    await _showFormModal(
      title: 'Edit Family Information',
      child: CustomTextField(
        controller: familyDetailsController,
        labelText: 'Family Details',
        icon: Icons.family_restroom_outlined,
        maxLines: 5,
      ),
      onSave: () {
        _bloc.add(UpdateProfileField(
          'familyDetails',
          familyDetailsController.text.trim().isEmpty ? null : familyDetailsController.text.trim(),
        ));
        _bloc.add(const SaveProfile());
      },
    );

    familyDetailsController.dispose();
  }

  Future<void> _showEducationCareerModal(EditProfileLoaded state) async {
    final educationController = TextEditingController(text: state.profile.education ?? '');
    final occupationController = TextEditingController(text: state.profile.occupation ?? '');
    final incomeController = TextEditingController(text: state.profile.income ?? '');

    await _showFormModal(
      title: 'Edit Education & Career',
      child: Column(
        children: [
          CustomTextField(
            controller: educationController,
            labelText: 'Education',
            icon: Icons.school_outlined,
          ),
          const SizedBox(height: 12),
          CustomTextField(
            controller: occupationController,
            labelText: 'Occupation',
            icon: Icons.work_outline,
          ),
          const SizedBox(height: 12),
          CustomTextField(
            controller: incomeController,
            labelText: 'Income',
            icon: Icons.payments_outlined,
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      onSave: () {
        _bloc.add(UpdateProfileField(
          'education',
          educationController.text.trim().isEmpty ? null : educationController.text.trim(),
        ));
        _bloc.add(UpdateProfileField(
          'occupation',
          occupationController.text.trim().isEmpty ? null : occupationController.text.trim(),
        ));
        _bloc.add(UpdateProfileField(
          'income',
          incomeController.text.trim().isEmpty ? null : incomeController.text.trim(),
        ));
        _bloc.add(const SaveProfile());
      },
    );

    educationController.dispose();
    occupationController.dispose();
    incomeController.dispose();
  }

  Future<void> _showLifestyleModal(EditProfileLoaded state) async {
    final hobbiesController = TextEditingController(text: (state.profile.hobbies ?? []).join(', '));
    final lifestyle = Map<String, bool>.from(
      state.profile.lifestyle ??
          const {
            'prayerRegularity': false,
            'halalLifestyle': false,
            'nonSmoking': false,
            'nonDrinking': false,
          },
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: (MediaQuery.of(context).viewInsets.bottom < 0 ? 0.0 : MediaQuery.of(context).viewInsets.bottom) + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Edit Lifestyle',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    controller: hobbiesController,
                    labelText: 'Hobbies',
                    hintText: 'Reading, Travel, Cooking',
                    icon: Icons.interests_outlined,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Regular Prayer'),
                    value: lifestyle['prayerRegularity'] ?? false,
                    onChanged: (value) => setModalState(() => lifestyle['prayerRegularity'] = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Halal Lifestyle'),
                    value: lifestyle['halalLifestyle'] ?? false,
                    onChanged: (value) => setModalState(() => lifestyle['halalLifestyle'] = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Non-Smoking'),
                    value: lifestyle['nonSmoking'] ?? false,
                    onChanged: (value) => setModalState(() => lifestyle['nonSmoking'] = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Non-Drinking'),
                    value: lifestyle['nonDrinking'] ?? false,
                    onChanged: (value) => setModalState(() => lifestyle['nonDrinking'] = value),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final hobbies = hobbiesController.text
                                .split(',')
                                .map((item) => item.trim())
                                .where((item) => item.isNotEmpty)
                                .toList();
                            _bloc.add(UpdateProfileField('hobbies', hobbies.isEmpty ? null : hobbies));
                            _bloc.add(UpdateProfileField('lifestyle', lifestyle));
                            _bloc.add(const SaveProfile());
                            Navigator.of(context).pop();
                          },
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    hobbiesController.dispose();
  }

  Future<void> _showAboutMeModal(EditProfileLoaded state) async {
    final aboutMeController = TextEditingController(text: state.profile.aboutMe ?? '');

    await _showFormModal(
      title: 'Edit About Me',
      child: CustomTextField(
        controller: aboutMeController,
        labelText: 'About Me',
        icon: Icons.edit_note_outlined,
        maxLines: 6,
      ),
      onSave: () {
        _bloc.add(UpdateProfileField(
          'aboutMe',
          aboutMeController.text.trim().isEmpty ? null : aboutMeController.text.trim(),
        ));
        _bloc.add(const SaveProfile());
      },
    );

    aboutMeController.dispose();
  }

  Future<void> _showFormModal({
    required String title,
    required Widget child,
    required VoidCallback onSave,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: (MediaQuery.of(context).viewInsets.bottom < 0 ? 0.0 : MediaQuery.of(context).viewInsets.bottom) + 16,
            ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                child,
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            onSave();
                            Navigator.of(context).pop();
                          },
                          child: const Text('Save'),
                        ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showProfileImagePreview(String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

}

class _EditStatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlighted;

  const _EditStatChip({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlighted
            ? primary.withAlpha((0.12 * 255).round())
            : const Color(0xFFF7F5F2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: highlighted ? primary : const Color(0xFF6B7280),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: highlighted ? primary : const Color(0xFF374151),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
