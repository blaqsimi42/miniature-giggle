import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/device_safe_area.dart';
import '../screens/profile_view_screen.dart';
import '../services/match_service.dart';
import '../services/user_service.dart';
import '../widgets/app_notice.dart';

class MatchesScreen extends StatefulWidget {
  final bool embedOnly;

  const MatchesScreen({super.key, this.embedOnly = false});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  final MatchService _svc = MatchService();
  final UserService _userService = UserService();
  final TextEditingController _occupationController = TextEditingController();

  final Map<String, dynamic> _filters = {};
  List<dynamic> _items = [];
  String? _nextPageToken;
  bool _loading = false;
  bool _openingProfile = false;
  bool _showAllMatches = false;
  _MatchesFilterCatalog? _filterCatalog;

  bool get _hasActiveFilters => _filters.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _initFiltersAndLoad();
  }

  Future<void> _initFiltersAndLoad() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedFilters = prefs.getString('matches_filters');
      if (savedFilters != null) {
        final saved = jsonDecode(savedFilters) as Map<String, dynamic>;
        _filters
          ..clear()
          ..addAll(saved);
        _occupationController.text = saved['occupation'] ?? '';
      }
    } catch (_) {}

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      FirebaseAuth.instance.authStateChanges().first.then((u) {
        if (u != null && mounted) {
          _loadFirstPage();
        } else if (mounted) {
          setState(() => _loading = false);
        }
      });
      return;
    }

    await _loadFirstPage();
  }

  Future<_MatchesFilterCatalog> _loadFilterCatalog() async {
    if (_filterCatalog != null) {
      return _filterCatalog!;
    }

    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await FirebaseFirestore.instance.collection('users').get();
    } catch (_) {
      const emptyCatalog = _MatchesFilterCatalog(
        occupations: <String>[],
        religions: <String>[],
        locations: <String>[],
        ages: <int>[],
        heights: <double>[],
      );
      _filterCatalog = emptyCatalog;
      return emptyCatalog;
    }

    final occupations = <String>{};
    final religions = <String>{};
    final locations = <String>{};
    final ages = <int>{};
    final heights = <double>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();

      final occupation = (data['occupation'] as String?)?.trim() ?? '';
      if (occupation.isNotEmpty) occupations.add(occupation);

      final religion = (data['religion'] as String?)?.trim() ?? '';
      if (religion.isNotEmpty) religions.add(religion);

      final location = _locationLabelFromMap(data['location']);
      if (location.isNotEmpty) locations.add(location);

      final dob = data['dateOfBirth'];
      if (dob is Timestamp) {
        ages.add(_calculateAge(dob.toDate()));
      }

      final height = data['height'];
      if (height is num) {
        heights.add(height.toDouble());
      }
    }

    _filterCatalog = _MatchesFilterCatalog(
      occupations: occupations.toList()..sort(),
      religions: religions.toList()..sort(),
      locations: locations.toList()..sort(),
      ages: ages.toList()..sort(),
      heights: heights.toList()..sort(),
    );
    return _filterCatalog!;
  }

  Future<void> _loadFirstPage() async {
    setState(() => _loading = true);
    try {
      final resp = await _svc.getMatches(filters: _filters);
      if (!mounted) return;
      setState(() {
        _items = resp['items'] ?? [];
        _nextPageToken = resp['nextPageToken'];
        _showAllMatches = false;
      });
    } catch (e) {
      if (!mounted) return;
      AppNotice.showError(
        context,
        e,
        fallbackMessage: 'Could not load matches right now.',
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_nextPageToken == null) return;

    setState(() => _loading = true);
    try {
      final resp = await _svc.getMatches(
        filters: _filters,
        pageToken: _nextPageToken,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(resp['items'] ?? []);
        _nextPageToken = resp['nextPageToken'];
      });
    } catch (e) {
      if (!mounted) return;
      AppNotice.showError(
        context,
        e,
        fallbackMessage: 'Could not load more matches.',
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openProfileDetails(String uid) async {
    if (_openingProfile || uid.isEmpty) return;

    setState(() => _openingProfile = true);
    try {
      final user = await _userService.getUser(uid);
      if (!mounted) return;

      if (user == null) {
        AppNotice.showError(context, 'Profile not found.');
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileViewScreen(
            userId: user.uid,
            initialProfile: user,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppNotice.showError(
        context,
        e,
        fallbackMessage: 'Could not open this profile right now.',
      );
    } finally {
      if (mounted) {
        setState(() => _openingProfile = false);
      }
    }
  }

  Future<void> _openFilterSheet() async {
    final catalog = await _loadFilterCatalog();
    if (!mounted) return;

    final res = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _MatchesDatabaseFilterSheet(
        initialFilters: Map<String, dynamic>.from(_filters),
        catalog: catalog,
      ),
    );

    if (res != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'matches_filters',
        jsonEncode(res),
      );
      if (!mounted) return;
      setState(() {
        _filters
          ..clear()
          ..addAll(res);
        _occupationController.text = res['occupation'] ?? '';
        _showAllMatches = false;
      });
      _loadFirstPage();
    }
  }

  List<dynamic> _applyClientSideFilters(List<dynamic> items) {
    if (_filters.isEmpty) {
      return items;
    }

    return items.where((item) {
      final map = item is Map<String, dynamic>
          ? item
          : Map<String, dynamic>.from(item as Map);
      final profile = map['profile'] is Map<String, dynamic>
          ? map['profile'] as Map<String, dynamic>
          : const <String, dynamic>{};

      final minAge = _filters['minAge'] is int
          ? _filters['minAge'] as int
          : int.tryParse('${_filters['minAge'] ?? ''}');
      final maxAge = _filters['maxAge'] is int
          ? _filters['maxAge'] as int
          : int.tryParse('${_filters['maxAge'] ?? ''}');
      final age = profile['age'] is int
          ? profile['age'] as int
          : int.tryParse('${profile['age'] ?? ''}');
      if (minAge != null && (age == null || age < minAge)) return false;
      if (maxAge != null && (age == null || age > maxAge)) return false;

      final minHeight = _filters['minHeight'] is num
          ? (_filters['minHeight'] as num).toDouble()
          : double.tryParse('${_filters['minHeight'] ?? ''}');
      final maxHeight = _filters['maxHeight'] is num
          ? (_filters['maxHeight'] as num).toDouble()
          : double.tryParse('${_filters['maxHeight'] ?? ''}');
      final height = profile['height'] is num
          ? (profile['height'] as num).toDouble()
          : double.tryParse('${profile['height'] ?? ''}');
      if (minHeight != null && (height == null || height < minHeight)) {
        return false;
      }
      if (maxHeight != null && (height == null || height > maxHeight)) {
        return false;
      }

      final occupationFilter =
          (_filters['occupation'] as String?)?.trim().toLowerCase() ?? '';
      final occupation = (profile['occupation'] as String?)?.trim().toLowerCase() ?? '';
      if (occupationFilter.isNotEmpty && !occupation.contains(occupationFilter)) {
        return false;
      }

      final religionFilter =
          (_filters['religion'] as String?)?.trim().toLowerCase() ?? '';
      final religion = (profile['religion'] as String?)?.trim().toLowerCase() ?? '';
      if (religionFilter.isNotEmpty && !religion.contains(religionFilter)) {
        return false;
      }

      final locationFilter =
          (_filters['locationLabel'] as String?)?.trim().toLowerCase() ?? '';
      final location = ((profile['locationLabel'] ?? '') as String)
          .trim()
          .toLowerCase();
      if (locationFilter.isNotEmpty && !location.contains(locationFilter)) {
        return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final emptyMessage = _hasActiveFilters
        ? 'Sorry, we couldn\'t get a match.'
        : 'No profiles are available right now. Please check back shortly.';
    final bottomActionInset = bottomContentPadding(
      context,
      base: widget.embedOnly ? 112.0 : 24.0,
    );
    final filteredItems = _applyClientSideFilters(_items);
    final visibleItems = _showAllMatches || filteredItems.length <= 5
        ? filteredItems
        : filteredItems.take(5).toList();

    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              Expanded(
                child: _hasActiveFilters
                    ? Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in _filters.entries)
                            Chip(label: Text('${entry.key}: ${entry.value}')),
                        ],
                      )
                    : const Text(
                        'Search',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _openFilterSheet,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Filters'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading && filteredItems.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : filteredItems.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _hasActiveFilters
                                  ? Icons.search_off_rounded
                                  : Icons.people_outline_rounded,
                              size: 56,
                              color: Colors.black26,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              emptyMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        4,
                        16,
                        bottomActionInset,
                      ),
                      children: [
                        for (final it in visibleItems) ...[
                          _MatchProfileCard(
                            profile: it['profile'] as Map<String, dynamic>? ?? const {},
                            score: it['score'],
                            onTap: () =>
                                _openProfileDetails((it['uid'] ?? '').toString()),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (filteredItems.length > 5 && !_showAllMatches)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Center(
                              child: InkWell(
                                onTap: () => setState(() => _showAllMatches = true),
                                borderRadius: BorderRadius.circular(999),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(999),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x14000000),
                                        blurRadius: 18,
                                        offset: Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'See all matches',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F3D2E),
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: Color(0xFF16A34A),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (filteredItems.length > 5 && _showAllMatches)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Center(
                              child: TextButton.icon(
                                onPressed: () =>
                                    setState(() => _showAllMatches = false),
                                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                                label: const Text('Show less'),
                              ),
                            ),
                          ),
                      ],
                    ),
        ),
        if (_nextPageToken != null)
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                widget.embedOnly ? 20 : 8,
              ),
              child: ElevatedButton(
                onPressed: _loading ? null : _loadMore,
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Load more'),
              ),
            ),
          ),
      ],
    );

    if (widget.embedOnly) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: body,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: body,
    );
  }

  @override
  void dispose() {
    _occupationController.dispose();
    super.dispose();
  }
}

int _calculateAge(DateTime dateOfBirth) {
  final now = DateTime.now();
  var age = now.year - dateOfBirth.year;
  final hadBirthday =
      now.month > dateOfBirth.month ||
      (now.month == dateOfBirth.month && now.day >= dateOfBirth.day);
  if (!hadBirthday) age--;
  return age;
}

String _locationLabelFromMap(Object? rawLocation) {
  if (rawLocation is! Map) return '';
  final city = '${rawLocation['city'] ?? ''}'.trim();
  final state = '${rawLocation['state'] ?? ''}'.trim();
  final country = '${rawLocation['country'] ?? ''}'.trim();
  return [city, state, country]
      .where((part) => part.isNotEmpty)
      .join(', ');
}

String _formatHeightOption(double value) {
  final hasFraction = value % 1 != 0;
  return hasFraction ? value.toStringAsFixed(1) : value.toStringAsFixed(0);
}

class _MatchesFilterCatalog {
  final List<String> occupations;
  final List<String> religions;
  final List<String> locations;
  final List<int> ages;
  final List<double> heights;

  const _MatchesFilterCatalog({
    required this.occupations,
    required this.religions,
    required this.locations,
    required this.ages,
    required this.heights,
  });
}

class _MatchesDatabaseFilterSheet extends StatefulWidget {
  final Map<String, dynamic> initialFilters;
  final _MatchesFilterCatalog catalog;

  const _MatchesDatabaseFilterSheet({
    required this.initialFilters,
    required this.catalog,
  });

  @override
  State<_MatchesDatabaseFilterSheet> createState() =>
      _MatchesDatabaseFilterSheetState();
}

class _MatchesDatabaseFilterSheetState
    extends State<_MatchesDatabaseFilterSheet> {
  late final TextEditingController _occupationController;
  late final TextEditingController _religionController;
  late final TextEditingController _locationController;

  int? _minAge;
  int? _maxAge;
  double? _minHeight;
  double? _maxHeight;

  @override
  void initState() {
    super.initState();
    _occupationController = TextEditingController(
      text: widget.initialFilters['occupation']?.toString() ?? '',
    );
    _religionController = TextEditingController(
      text: widget.initialFilters['religion']?.toString() ?? '',
    );
    _locationController = TextEditingController(
      text: widget.initialFilters['locationLabel']?.toString() ?? '',
    );
    _minAge = widget.initialFilters['minAge'] is int
        ? widget.initialFilters['minAge'] as int
        : int.tryParse('${widget.initialFilters['minAge'] ?? ''}');
    _maxAge = widget.initialFilters['maxAge'] is int
        ? widget.initialFilters['maxAge'] as int
        : int.tryParse('${widget.initialFilters['maxAge'] ?? ''}');
    _minHeight = widget.initialFilters['minHeight'] is num
        ? (widget.initialFilters['minHeight'] as num).toDouble()
        : double.tryParse('${widget.initialFilters['minHeight'] ?? ''}');
    _maxHeight = widget.initialFilters['maxHeight'] is num
        ? (widget.initialFilters['maxHeight'] as num).toDouble()
        : double.tryParse('${widget.initialFilters['maxHeight'] ?? ''}');
  }

  @override
  void dispose() {
    _occupationController.dispose();
    _religionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _occupationController.clear();
      _religionController.clear();
      _locationController.clear();
      _minAge = null;
      _maxAge = null;
      _minHeight = null;
      _maxHeight = null;
    });
  }

  void _apply() {
    final out = <String, dynamic>{};
    final occupation = _occupationController.text.trim();
    final religion = _religionController.text.trim();
    final locationLabel = _locationController.text.trim();

    if (occupation.isNotEmpty) out['occupation'] = occupation;
    if (religion.isNotEmpty) out['religion'] = religion;
    if (locationLabel.isNotEmpty) out['locationLabel'] = locationLabel;
    if (_minAge != null) out['minAge'] = _minAge;
    if (_maxAge != null) out['maxAge'] = _maxAge;
    if (_minHeight != null) out['minHeight'] = _minHeight;
    if (_maxHeight != null) out['maxHeight'] = _maxHeight;

    Navigator.of(context).pop(out);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final viewPaddingBottom = MediaQuery.of(context).viewPadding.bottom;
    final bottomInset = viewInsets.bottom > viewPaddingBottom
        ? viewInsets.bottom
        : viewPaddingBottom;

    final ageOptions = widget.catalog.ages;
    final heightOptions = widget.catalog.heights;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 18, 14, bottomInset + 14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFCF7),
            borderRadius: BorderRadius.circular(32),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 30,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Match filters',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Search existing data for occupation, religion, location, age, and height, then apply refined results.',
                  style: TextStyle(
                    color: Color(0xFF667085),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                _MatchesSuggestionField(
                  controller: _occupationController,
                  label: 'Occupation',
                  hintText: 'Search occupations from profiles',
                  icon: Icons.work_outline_rounded,
                  suggestions: widget.catalog.occupations,
                ),
                const SizedBox(height: 18),
                _MatchesSuggestionField(
                  controller: _religionController,
                  label: 'Religion',
                  hintText: 'Search religions from profiles',
                  icon: Icons.mosque_outlined,
                  suggestions: widget.catalog.religions,
                ),
                const SizedBox(height: 18),
                _MatchesSuggestionField(
                  controller: _locationController,
                  label: 'Location',
                  hintText: 'Search profile locations',
                  icon: Icons.location_on_outlined,
                  suggestions: widget.catalog.locations,
                ),
                const SizedBox(height: 22),
                const Text(
                  'Age range',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F3D2E),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _MatchesDropdownField<int>(
                        label: 'Minimum age',
                        icon: Icons.cake_outlined,
                        value: _minAge,
                        options: ageOptions,
                        displayText: (value) => '$value years',
                        onChanged: (value) => setState(() => _minAge = value),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _MatchesDropdownField<int>(
                        label: 'Maximum age',
                        icon: Icons.cake_rounded,
                        value: _maxAge,
                        options: ageOptions,
                        displayText: (value) => '$value years',
                        onChanged: (value) => setState(() => _maxAge = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const Text(
                  'Height range',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F3D2E),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _MatchesDropdownField<double>(
                        label: 'Minimum height',
                        icon: Icons.height_rounded,
                        value: _minHeight,
                        options: heightOptions,
                        displayText: (value) => _formatHeightOption(value),
                        onChanged: (value) => setState(() => _minHeight = value),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _MatchesDropdownField<double>(
                        label: 'Maximum height',
                        icon: Icons.height_rounded,
                        value: _maxHeight,
                        options: heightOptions,
                        displayText: (value) => _formatHeightOption(value),
                        onChanged: (value) => setState(() => _maxHeight = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _reset,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: Color(0xFFD6E2D9)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text('Clear'),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: FilledButton(
                        onPressed: _apply,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text(
                          'Apply filters',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
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
}

class _MatchesSuggestionField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hintText;
  final IconData icon;
  final List<String> suggestions;

  const _MatchesSuggestionField({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.icon,
    required this.suggestions,
  });

  @override
  State<_MatchesSuggestionField> createState() => _MatchesSuggestionFieldState();
}

class _MatchesSuggestionFieldState extends State<_MatchesSuggestionField> {
  Future<void> _openPicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _MatchesOptionPickerSheet(
        title: widget.label,
        hintText: widget.hintText,
        options: widget.suggestions,
        initialQuery: widget.controller.text,
      ),
    );

    if (!mounted || selected == null) return;
    setState(() {
      widget.controller.value = TextEditingValue(
        text: selected,
        selection: TextSelection.collapsed(offset: selected.length),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      readOnly: true,
      onTap: _openPicker,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        prefixIcon: Icon(widget.icon, color: const Color(0xFF16A34A)),
        suffixIcon: widget.controller.text.trim().isEmpty
            ? const Icon(Icons.keyboard_arrow_down_rounded)
            : IconButton(
                onPressed: () {
                  setState(() {
                    widget.controller.clear();
                  });
                },
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFD6E2D9)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFD6E2D9)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: Color(0xFF16A34A),
            width: 1.4,
          ),
        ),
      ),
    );
  }
}

class _MatchesOptionPickerSheet extends StatefulWidget {
  final String title;
  final String hintText;
  final List<String> options;
  final String initialQuery;

  const _MatchesOptionPickerSheet({
    required this.title,
    required this.hintText,
    required this.options,
    required this.initialQuery,
  });

  @override
  State<_MatchesOptionPickerSheet> createState() =>
      _MatchesOptionPickerSheetState();
}

class _MatchesOptionPickerSheetState extends State<_MatchesOptionPickerSheet> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery);
    _searchController.addListener(_handleChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = (query.isEmpty
            ? widget.options
            : widget.options
                .where((option) => option.toLowerCase().contains(query))
                .toList())
        .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          18,
          14,
          MediaQuery.of(context).viewInsets.bottom + 14,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFCF7),
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 30,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF16A34A),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFFD6E2D9)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFFD6E2D9)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(
                        color: Color(0xFF16A34A),
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: filtered.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                'No matching options found.',
                                style: TextStyle(color: Color(0xFF667085)),
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final option = filtered[index];
                              return ListTile(
                                dense: true,
                                title: Text(option),
                                onTap: () => Navigator.of(context).pop(option),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MatchesDropdownField<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final T? value;
  final List<T> options;
  final String Function(T value) displayText;
  final ValueChanged<T?> onChanged;

  const _MatchesDropdownField({
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.displayText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T?>(
      initialValue: options.contains(value) ? value : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF16A34A)),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFD6E2D9)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFD6E2D9)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: Color(0xFF16A34A),
            width: 1.4,
          ),
        ),
      ),
      items: [
        DropdownMenuItem<T?>(
          value: null,
          child: Text('Any'),
        ),
        ...options.map(
          (option) => DropdownMenuItem<T?>(
            value: option,
            child: Text(displayText(option)),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _MatchProfileCard extends StatelessWidget {
  final Map<String, dynamic> profile;
  final dynamic score;
  final VoidCallback onTap;

  const _MatchProfileCard({
    required this.profile,
    required this.score,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fullName = (profile['fullName'] ?? 'Match').toString();
    final age = (profile['age'] ?? '-').toString();
    final occupation = ((profile['occupation'] ?? '') as String).trim();
    final location = ((profile['locationLabel'] ?? '') as String).trim();
    final imageUrl = ((profile['profilePictureUrl'] ?? '') as String).trim();
    final scoreLabel = score == null ? null : '${score.toString()}% match';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 132,
                height: 192,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: const Color(0xFFEFE8DD),
                  image: imageUrl.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(imageUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: imageUrl.isEmpty
                    ? const Center(
                        child: Icon(
                          Icons.person_rounded,
                          size: 56,
                          color: Colors.white70,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        fullName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F3D2E),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _MetaPill(
                        label: 'Age $age',
                        icon: Icons.cake_outlined,
                      ),
                      if (occupation.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _MetaPill(
                          label: occupation,
                          icon: Icons.work_outline_rounded,
                        ),
                      ],
                      if (location.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _MetaPill(
                          label: location,
                          icon: Icons.location_on_outlined,
                        ),
                      ],
                      if (scoreLabel != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F4EB),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            scoreLabel,
                            style: const TextStyle(
                              color: Color(0xFF16A34A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
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

class _MetaPill extends StatelessWidget {
  final String label;
  final IconData icon;

  const _MetaPill({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F5F3),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF16A34A)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
