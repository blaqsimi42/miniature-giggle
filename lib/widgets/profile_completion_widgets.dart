import 'package:flutter/material.dart';

class ProfileStrengthBar extends StatelessWidget {
  final int percent;
  final double height;

  const ProfileStrengthBar({
    super.key,
    required this.percent,
    this.height = 10,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = percent.clamp(0, 100);
    final fillColor = clamped >= 90
        ? const Color(0xFFD4A84F)
        : const Color(0xFF0F5C2E);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: clamped / 100,
        minHeight: height,
        backgroundColor: const Color(0xFFEAE4D9),
        valueColor: AlwaysStoppedAnimation<Color>(fillColor),
      ),
    );
  }
}

class ProfileSetupProgressHeader extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final String title;
  final String description;
  final int percent;
  final Widget? trailing;

  const ProfileSetupProgressHeader({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.title,
    required this.description,
    required this.percent,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step $currentStep of $totalSteps',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F5C2E),
          ),
        ),
        const SizedBox(height: 10),
        ProfileStrengthBar(percent: percent),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF171717),
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          description,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF6B7280),
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class ProfileSetupCard extends StatelessWidget {
  final Widget child;

  const ProfileSetupCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF0E8DB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class ProfileSetupTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? errorText;
  final bool readOnly;
  final VoidCallback? onTap;

  const ProfileSetupTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.errorText,
    this.readOnly = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Color(0xFF171717),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          readOnly: readOnly,
          onTap: onTap,
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            filled: true,
            fillColor: const Color(0xFFF7F5F2),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

class ProfileSetupDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? errorText;

  const ProfileSetupDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedValue = items.any((item) => item.value == value) ? value : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Color(0xFF171717),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<T>(
          initialValue: normalizedValue,
          isExpanded: true,
          items: items,
          onChanged: onChanged,
          decoration: InputDecoration(
            errorText: errorText,
            filled: true,
            fillColor: const Color(0xFFF7F5F2),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

class ProfileSetupChipSelector extends StatelessWidget {
  final String label;
  final List<String> options;
  final List<String> selectedValues;
  final bool multiSelect;
  final ValueChanged<List<String>> onChanged;
  final String? errorText;

  const ProfileSetupChipSelector({
    super.key,
    required this.label,
    required this.options,
    required this.selectedValues,
    required this.onChanged,
    this.multiSelect = false,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Color(0xFF171717),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: options.map((option) {
            final selected = selectedValues.contains(option);
            return ChoiceChip(
              label: Text(option),
              selected: selected,
              selectedColor: const Color(0xFF0F5C2E),
              labelStyle: TextStyle(
                color: selected ? Colors.white : const Color(0xFF171717),
                fontWeight: FontWeight.w600,
              ),
              onSelected: (enabled) {
                if (multiSelect) {
                  final next = [...selectedValues];
                  if (enabled) {
                    if (!next.contains(option)) next.add(option);
                  } else {
                    next.remove(option);
                  }
                  onChanged(next);
                } else {
                  onChanged(enabled ? [option] : <String>[]);
                }
              },
            );
          }).toList(),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFB42318),
            ),
          ),
        ],
      ],
    );
  }
}

class ProfileCompletionGateCard extends StatelessWidget {
  final int percent;
  final String nextStep;
  final VoidCallback onContinue;
  final VoidCallback onLater;

  const ProfileCompletionGateCard({
    super.key,
    required this.percent,
    required this.nextStep,
    required this.onContinue,
    required this.onLater,
  });

  @override
  Widget build(BuildContext context) {
    return ProfileSetupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Complete Your Qubool Profile',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF171717),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Help us recommend compatible halal matches for you.',
            style: TextStyle(
              color: Color(0xFF6B7280),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '$percent% complete',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F5C2E),
            ),
          ),
          const SizedBox(height: 10),
          ProfileStrengthBar(percent: percent, height: 12),
          const SizedBox(height: 12),
          const Text(
            'Complete at least 70% of your profile to start discovering compatible profiles.',
            style: TextStyle(
              color: Color(0xFF6B7280),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            nextStep,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFFD4A84F),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F5C2E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Text('Continue Setup'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onLater,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF171717),
                side: const BorderSide(color: Color(0xFFE7DED2)),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Text('Maybe Later'),
            ),
          ),
        ],
      ),
    );
  }
}

class PhotoUploadBox extends StatelessWidget {
  final List<String> photos;
  final VoidCallback onTap;
  final String? helperText;

  const PhotoUploadBox({
    super.key,
    required this.photos,
    required this.onTap,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F5F2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE7DED2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.add_a_photo_outlined, color: Color(0xFF0F5C2E)),
                const SizedBox(width: 10),
                Text(
                  photos.isEmpty ? 'Add Photos' : 'Manage Photos',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF171717),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (photos.isEmpty)
              Text(
                helperText ?? 'Add at least one photo so your profile can reach discovery level.',
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  height: 1.45,
                ),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: photos.take(4).map((photo) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      photo,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}
