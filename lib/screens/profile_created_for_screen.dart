import 'dart:async';

import 'package:flutter/material.dart';

import '../services/route_persistence.dart';

const Color _kGreen = Color(0xFF16A34A);

class ProfileCreatedForScreen extends StatefulWidget {
  const ProfileCreatedForScreen({super.key});

  @override
  State<ProfileCreatedForScreen> createState() =>
      _ProfileCreatedForScreenState();
}

class _ProfileCreatedForScreenState extends State<ProfileCreatedForScreen> {
  static const List<String> _relationOptions = <String>[
    'Self',
    'Brother',
    'Sister',
    'Mother',
    'Father',
    'Others',
  ];

  final TextEditingController _otherController = TextEditingController();
  String _selectedRelation = 'Self';

  bool get _canContinue {
    if (_selectedRelation != 'Others') return true;
    return _otherController.text.trim().isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _otherController.addListener(_onOtherChanged);
  }

  @override
  void dispose() {
    _otherController.removeListener(_onOtherChanged);
    _otherController.dispose();
    super.dispose();
  }

  void _onOtherChanged() {
    setState(() {});
  }

  Future<void> _continue() async {
    if (!_canContinue) return;
    final profileCreatedFor = _selectedRelation == 'Others'
        ? _otherController.text.trim()
        : _selectedRelation;
    final args = <String, dynamic>{
      'profileCreatedFor': profileCreatedFor,
    };
    unawaited(RoutePersistence.save('/personal', args));
    if (!mounted) return;
    Navigator.pushNamed(context, '/personal', arguments: args);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFAF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'STEP 1 OF 3',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
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
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: _canContinue ? _kGreen : Colors.white,
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const Expanded(child: SizedBox()),
                    const Expanded(child: SizedBox()),
                  ],
                ),
              ),
            ),
            const Text(
              'Who are you creating this profile for?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose the relationship before we set up the account details.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _relationOptions.map((option) {
                      final selected = _selectedRelation == option;
                      return ChoiceChip(
                        label: Text(option),
                        selected: selected,
                        showCheckmark: false,
                        side: BorderSide(
                          color: selected
                              ? _kGreen
                              : Colors.black.withValues(alpha: 0.08),
                        ),
                        labelStyle: TextStyle(
                          color: selected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                        backgroundColor: const Color(0xFFF5F5F5),
                        selectedColor: _kGreen,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        onSelected: (_) {
                          setState(() {
                            _selectedRelation = option;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  if (_selectedRelation == 'Others') ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _otherController,
                      decoration: InputDecoration(
                        hintText: 'Tell us who this profile is for',
                        filled: true,
                        fillColor: const Color(0xFFF5F5F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 12,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _canContinue ? _continue : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreen,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Continue →',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
