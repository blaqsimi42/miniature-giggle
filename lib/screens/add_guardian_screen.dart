import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/guardian_service.dart';

class AddGuardianScreen extends StatefulWidget {
  const AddGuardianScreen({super.key});

  @override
  State<AddGuardianScreen> createState() => _AddGuardianScreenState();
}

class _AddGuardianScreenState extends State<AddGuardianScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _guardianNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final GuardianService _guardianService = GuardianService();
  String? _selectedRelationship;
  bool _isSending = false;

  static const List<String> _relationships = <String>[
    'Father',
    'Mother',
    'Brother',
    'Sister',
    'Uncle',
    'Aunt',
    'Other',
  ];

  @override
  void dispose() {
    _guardianNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String label,
    required String hint,
    Widget? prefixIcon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest,
      prefixIcon: prefixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  String _currentUserInitial() {
    final currentUser = AuthService().getCurrentUser();
    final displayName = currentUser?.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName.characters.first.toUpperCase();
    }
    final email = currentUser?.email?.trim();
    if (email != null && email.isNotEmpty) {
      return email.characters.first.toUpperCase();
    }
    final uid = currentUser?.uid.trim();
    if (uid != null && uid.isNotEmpty) {
      return uid.characters.first.toUpperCase();
    }
    return 'U';
  }

  Widget _buildPhonePrefix(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 12, right: 8, top: 8, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '🇳🇬',
            style: TextStyle(fontSize: 18),
          ),
          const SizedBox(width: 8),
          Text(
            '+234',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 24,
            child: VerticalDivider(
              width: 1,
              thickness: 1,
              color: colorScheme.outlineVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendInvitation() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      await _guardianService.sendInvitation(
        guardianName: _guardianNameController.text.trim(),
        relationship: _selectedRelationship!,
        phone: _phoneController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacementNamed('/guardian/sent');
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send invitation right now.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Guardian'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    _currentUserInitial(),
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  width: 32,
                  height: 2,
                  color: colorScheme.primary,
                ),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor:
                            colorScheme.primary.withValues(alpha: 0.12),
                      ),
                      Icon(
                        Icons.shield,
                        color: colorScheme.primary,
                        size: 22,
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 2,
                  color: colorScheme.primary,
                ),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                  child: Icon(
                    Icons.person,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Add your Guardian',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Involve your guardian to build trust and start meaningful conversations.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _guardianNameController,
                      decoration: _inputDecoration(
                        context,
                        label: 'Guardian Name',
                        hint: 'Enter guardian name',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Guardian name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedRelationship,
                      items: _relationships
                          .map(
                            (relationship) => DropdownMenuItem<String>(
                              value: relationship,
                              child: Text(relationship),
                            ),
                          )
                          .toList(),
                      decoration: _inputDecoration(
                        context,
                        label: 'Relationship',
                        hint: 'Select relationship',
                      ),
                      onChanged: (value) {
                        setState(() {
                          _selectedRelationship = value;
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Relationship is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: _inputDecoration(
                        context,
                        label: 'Mobile Number',
                        hint: 'Enter mobile number',
                        prefixIcon: _buildPhonePrefix(context),
                      ).copyWith(
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 0,
                          minHeight: 0,
                        ),
                      ),
                      validator: (value) {
                        final digits = (value ?? '').replaceAll(
                          RegExp(r'[^0-9]'),
                          '',
                        );
                        if (digits.isEmpty) {
                          return 'Mobile number is required';
                        }
                        if (digits.length < 10) {
                          return 'Enter a valid mobile number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _isSending ? null : _sendInvitation,
                      child: _isSending
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  colorScheme.onPrimary,
                                ),
                              ),
                            )
                          : const Text('Send Invitation'),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Guardian will receive an SMS invitation to join the app.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
