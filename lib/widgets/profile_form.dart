import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/data/india_cities.dart';


class ProfileForm extends StatelessWidget {
  final TextEditingController fullNameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController genderController;
  final TextEditingController religionController;
  final TextEditingController casteController;
  final TextEditingController educationController;
  final TextEditingController occupationController;
  final TextEditingController heightController;
  final TextEditingController hobbyInputController;
  final TextEditingController cityController;
  final TextEditingController countryController;
  final TextEditingController aboutMeController;
  final DateTime? selectedDateOfBirth;
  final VoidCallback onPickDateOfBirth;
  final String dobLabel;
  final int? age;
  final String selectedHeightUnit;
  final ValueChanged<String> onHeightUnitChanged;
  final List<String> hobbies;
  final ValueChanged<String> onAddHobby;
  final ValueChanged<String> onRemoveHobby;
  final VoidCallback onSave;
  final bool savingProfile;

  const ProfileForm({
    super.key,
    required this.fullNameController,
    required this.emailController,
    required this.phoneController,
    required this.genderController,
    required this.religionController,
    required this.casteController,
    required this.educationController,
    required this.occupationController,
    required this.heightController,
    required this.hobbyInputController,
    required this.cityController,
    required this.countryController,
    required this.aboutMeController,
    required this.selectedDateOfBirth,
    required this.onPickDateOfBirth,
    required this.dobLabel,
    required this.age,
    required this.selectedHeightUnit,
    required this.onHeightUnitChanged,
    required this.hobbies,
    required this.onAddHobby,
    required this.onRemoveHobby,
    required this.onSave,
    required this.savingProfile,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Review and update the information visible on your profile.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            TextFormField(controller: fullNameController, decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person))),
            const SizedBox(height: 12),
            TextFormField(controller: emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.email))),
            const SizedBox(height: 12),
            TextFormField(controller: phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number', prefixIcon: Icon(Icons.phone))),
            const SizedBox(height: 12),
            TextFormField(controller: genderController, decoration: const InputDecoration(labelText: 'Gender', prefixIcon: Icon(Icons.wc))),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: onPickDateOfBirth, icon: const Icon(Icons.cake_outlined), label: Text(age == null ? dobLabel : '$dobLabel - Age $age')),
            const SizedBox(height: 12),
            TextFormField(controller: religionController, decoration: const InputDecoration(labelText: 'Religion', prefixIcon: Icon(Icons.mosque))),
            const SizedBox(height: 12),
            TextFormField(controller: casteController, decoration: const InputDecoration(labelText: 'Caste', prefixIcon: Icon(Icons.groups_2))),
            const SizedBox(height: 12),
            TextFormField(controller: educationController, decoration: const InputDecoration(labelText: 'Education', prefixIcon: Icon(Icons.school))),
            const SizedBox(height: 12),
            TextFormField(controller: occupationController, decoration: const InputDecoration(labelText: 'Occupation', prefixIcon: Icon(Icons.work))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: heightController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Height', prefixIcon: Icon(Icons.height)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selectedHeightUnit,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Unit', prefixIcon: Icon(Icons.straighten)),
                  items: const [
                    DropdownMenuItem(value: 'ft', child: Text('ft')),
                    DropdownMenuItem(value: 'in', child: Text('in')),
                    DropdownMenuItem(value: 'cm', child: Text('cm')),
                  ],
                  onChanged: (v) {
                    if (v != null) onHeightUnitChanged(v);
                  },
                ),
              )
            ]),
            const SizedBox(height: 12),
            // Hobby editor is declared earlier in file; if missing fall back to simple input
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: TextFormField(controller: hobbyInputController, decoration: const InputDecoration(labelText: 'Hobbies'))), const SizedBox(width: 8), IconButton(icon: const Icon(Icons.add), onPressed: () { final v = hobbyInputController.text.trim(); if (v.isNotEmpty) onAddHobby(v); })]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: hobbies.map((h) => InputChip(label: Text(h), onDeleted: () => onRemoveHobby(h))).toList())
            ]),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                final picked = await showModalBottomSheet<String?>(
                  context: context,
                  isScrollControlled: true,
                  builder: (ctx) {
                    String query = '';
                    return StatefulBuilder(builder: (ctx, setState) {
                      final q = query.trim().toLowerCase();
                      List<String> filtered;
                      if (q.isEmpty) {
                        filtered = List.from(kIndiaCities);
                      } else {
                        final scored = <Map<String, dynamic>>[];
                        for (final c in kIndiaCities) {
                          final lc = c.toLowerCase();
                          int score;
                          if (lc.startsWith(q)) {
                            score = 0;
                          } else if (lc.contains(q)) {
                            score = 1;
                          } else {
                            int idx = -1;
                            var matched = true;
                            for (var ch in q.split('')) {
                              idx = lc.indexOf(ch, idx + 1);
                              if (idx == -1) {
                                matched = false;
                                break;
                              }
                            }
                            score = matched ? 2 : 3;
                          }
                          if (score < 3) scored.add({'city': c, 'score': score});
                        }
                        scored.sort((a, b) {
                          final s = (a['score'] as int).compareTo(b['score'] as int);
                          if (s != 0) return s;
                          return (a['city'] as String).compareTo(b['city'] as String);
                        });
                        filtered = scored.map((e) => e['city'] as String).toList();
                      }
                      return Padding(
                        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: TextField(
                                autofocus: true,
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.search),
                                  hintText: 'Search city',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (v) => setState(() => query = v),
                              ),
                            ),
                            SizedBox(
                              height: 360,
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: filtered.length,
                                itemBuilder: (context, idx) {
                                  final city = filtered[idx];
                                  return ListTile(
                                    title: Text(city),
                                    onTap: () => Navigator.of(context).pop(city),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    });
                  },
                );
                if (picked != null) {
                  cityController.text = picked;
                }
              },
              child: AbsorbPointer(
                child: TextFormField(controller: cityController, decoration: const InputDecoration(labelText: 'City', prefixIcon: Icon(Icons.location_city))),
              ),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Country', prefixIcon: Icon(Icons.public)),
              child: Row(
                children: [
                  SvgPicture.asset('assets/flags/india.svg', width: 28, height: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(countryController.text)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: aboutMeController, maxLines: 4, decoration: const InputDecoration(labelText: 'About me', prefixIcon: Icon(Icons.edit_note))),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: savingProfile ? null : onSave, icon: savingProfile ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save), label: Text(savingProfile ? 'Saving...' : 'Save changes')))
          ],
        ),
      ),
    );
  }
}
