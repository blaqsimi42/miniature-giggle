import 'dart:async';
import 'package:flutter/material.dart';
import '../core/data/countries.dart';
import '../core/utils/validation_service.dart';
import '../services/route_persistence.dart';

const Color _kGreen = Color(0xFF16A34A);

class PersonalDetailsScreen extends StatefulWidget {
  const PersonalDetailsScreen({super.key});

  @override
  State<PersonalDetailsScreen> createState() => _PersonalDetailsScreenState();
}

class _PersonalDetailsScreenState extends State<PersonalDetailsScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  String _countryCode = '+91';
  bool _step1Complete = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_updateStep1Complete);
    _phoneController.addListener(_updateStep1Complete);
    _updateStep1Complete();
  }

  

  @override
  void dispose() {
    _nameController.removeListener(_updateStep1Complete);
    _phoneController.removeListener(_updateStep1Complete);
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _updateStep1Complete() {
    final complete = _nameController.text.trim().isNotEmpty && _phoneController.text.trim().isNotEmpty;
    if (complete != _step1Complete) setState(() => _step1Complete = complete);
  }

  String? _buildNormalizedPhone() {
    final localPhone = _phoneController.text.trim();
    if (localPhone.isEmpty) return null;

    final digitsOnly = localPhone.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.isEmpty) return null;

    final countryDigits = _countryCode.replaceAll('+', '');
    final combined = '+$countryDigits$digitsOnly';
    return ValidationService.normalizePhoneNumber(combined);
  }

  String _flagForDial(String dial) {
    final item = kCountries.firstWhere((c) => c['dial'] == dial, orElse: () => kCountries.first);
    return item['flag'] ?? '🏳️';
  }

  void _openCountryPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, controller) {
            return Column(
              children: [
                const SizedBox(height: 12),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 8),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Align(alignment: Alignment.centerLeft, child: Text('Select your country', style: TextStyle(fontWeight: FontWeight.w700)))),
                Expanded(
                  child: ListView.builder(
                    controller: controller,
                    itemCount: kCountries.length,
                    itemBuilder: (context, i) {
                      final c = kCountries[i];
                      return ListTile(
                        leading: Text(c['flag'] ?? '', style: const TextStyle(fontSize: 20)),
                        title: Text(c['name'] ?? ''),
                        subtitle: Text(c['dial'] ?? ''),
                        onTap: () {
                          setState(() => _countryCode = c['dial'] ?? _countryCode);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final profileCreatedFor = (args?['profileCreatedFor'] as String?)?.trim() ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFFBFAF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'STEP 2 OF 3',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Container(
                height: 8,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0,2))]),
                child: Row(
                  children: [
                    Expanded(child: Container(decoration: const BoxDecoration(color: _kGreen, borderRadius: BorderRadius.horizontal(left: Radius.circular(8))))),
                    Expanded(child: Container(color: _step1Complete ? _kGreen : Colors.white)),
                    const Expanded(child: SizedBox()),
                  ],
                ),
              ),
            ),
            const Text('Create Account', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Tell us your name and phone number', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF6B7280))),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 6))]),
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (profileCreatedFor.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3FAF5),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _kGreen.withValues(alpha: 0.18)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.badge_outlined, color: _kGreen, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Profile created for $profileCreatedFor',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: 'Full name',
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Phone row with flag picker
                  Container(
                    decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _openCountryPicker,
                          child: Row(
                            children: [
                              Text(_flagForDial(_countryCode), style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 8),
                              Text(_countryCode, style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(width: 12),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(hintText: 'Phone number', border: InputBorder.none),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      final normalizedPhone = _buildNormalizedPhone();
                      if (normalizedPhone == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enter a valid phone number.')),
                        );
                        return;
                      }
                      final args = {
                        'profileCreatedFor': profileCreatedFor,
                        'name': _nameController.text.trim(),
                        'phone': normalizedPhone,
                      };
                      unawaited(RoutePersistence.save('/password', args));
                      Navigator.pushNamed(context, '/password', arguments: args);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    child: const Text('Continue →', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),

                  const SizedBox(height: 14),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(),
                  ),
                  TextButton(
                    onPressed: () {
                      unawaited(RoutePersistence.save('/login'));
                      Navigator.pushReplacementNamed(context, '/login');
                    },
                    child: const Text('Have an account?'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Text('You can change these later in your profile settings.', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
