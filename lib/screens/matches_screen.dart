import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  int? _minAge;
  int? _maxAge;
  bool _loading = false;
  bool _openingProfile = false;
  bool _showAllMatches = false;

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
        _minAge = saved['minAge'] is int
            ? saved['minAge'] as int
            : int.tryParse('${saved['minAge'] ?? ''}');
        _maxAge = saved['maxAge'] is int
            ? saved['maxAge'] as int
            : int.tryParse('${saved['maxAge'] ?? ''}');
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
    final res = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final occCtrl = TextEditingController(
          text: _occupationController.text,
        );
        final minCtrl = TextEditingController(text: _minAge?.toString() ?? '');
        final maxCtrl = TextEditingController(text: _maxAge?.toString() ?? '');
        final minH = TextEditingController(
          text: _filters['minHeight']?.toString() ?? '',
        );
        final maxH = TextEditingController(
          text: _filters['maxHeight']?.toString() ?? '',
        );
        final religionCtrl = TextEditingController(
          text: _filters['religion'] ?? '',
        );
        final locLat = TextEditingController(
          text: _filters['location'] != null
              ? (_filters['location']['lat']?.toString() ?? '')
              : '',
        );
        final locLng = TextEditingController(
          text: _filters['location'] != null
              ? (_filters['location']['lng']?.toString() ?? '')
              : '',
        );
        final locRad = TextEditingController(
          text: _filters['location'] != null
              ? (_filters['location']['radiusKm']?.toString() ?? '')
              : '',
        );

        return Padding(
            padding: MediaQuery.of(context).viewInsets.isNonNegative
              ? MediaQuery.of(context).viewInsets
              : EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: occCtrl,
                    decoration: const InputDecoration(labelText: 'Occupation'),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: minCtrl,
                          decoration: const InputDecoration(labelText: 'Min age'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: maxCtrl,
                          decoration: const InputDecoration(labelText: 'Max age'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: minH,
                          decoration: const InputDecoration(
                            labelText: 'Min height (ft)',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: maxH,
                          decoration: const InputDecoration(
                            labelText: 'Max height (ft)',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: religionCtrl,
                    decoration: const InputDecoration(labelText: 'Religion'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: locLat,
                          decoration: const InputDecoration(
                            labelText: 'Location lat',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: locLng,
                          decoration: const InputDecoration(
                            labelText: 'Location lng',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: locRad,
                          decoration: const InputDecoration(
                            labelText: 'Radius km',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(<String, dynamic>{}),
                        child: const Text('Clear'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          final out = <String, dynamic>{};
                          final occ = occCtrl.text.trim();
                          if (occ.isNotEmpty) out['occupation'] = occ;
                          final min = int.tryParse(minCtrl.text.trim());
                          final max = int.tryParse(maxCtrl.text.trim());
                          if (min != null) out['minAge'] = min;
                          if (max != null) out['maxAge'] = max;
                          final minHeight = int.tryParse(minH.text.trim());
                          final maxHeight = int.tryParse(maxH.text.trim());
                          if (minHeight != null) out['minHeight'] = minHeight;
                          if (maxHeight != null) out['maxHeight'] = maxHeight;
                          final rel = religionCtrl.text.trim();
                          if (rel.isNotEmpty) out['religion'] = rel;
                          final lat = double.tryParse(locLat.text.trim());
                          final lng = double.tryParse(locLng.text.trim());
                          final radius = double.tryParse(locRad.text.trim());
                          if (lat != null && lng != null && radius != null) {
                            out['location'] = {
                              'lat': lat,
                              'lng': lng,
                              'radiusKm': radius,
                            };
                          }

                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString(
                            'matches_filters',
                            jsonEncode(out),
                          );
                          if (!context.mounted) return;
                          Navigator.of(context).pop(out);
                        },
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (res != null) {
      setState(() {
        _filters
          ..clear()
          ..addAll(res);
        _occupationController.text = res['occupation'] ?? '';
        _minAge = res['minAge'] as int?;
        _maxAge = res['maxAge'] as int?;
        _showAllMatches = false;
      });
      _loadFirstPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final emptyMessage = _hasActiveFilters
        ? 'Sorry, we couldn\'t get a match.'
        : 'No profiles are available right now. Please check back shortly.';
    final bottomActionInset = widget.embedOnly ? 112.0 : 24.0;
    final visibleItems = _showAllMatches || _items.length <= 5
        ? _items
        : _items.take(5).toList();

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
                        'Matches',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              FilledButton.icon(
                onPressed: _openFilterSheet,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Filters'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading && _items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
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
                        if (_items.length > 5 && !_showAllMatches)
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
                        if (_items.length > 5 && _showAllMatches)
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
      appBar: AppBar(title: const Text('Matches')),
      body: body,
    );
  }

  @override
  void dispose() {
    _occupationController.dispose();
    super.dispose();
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
