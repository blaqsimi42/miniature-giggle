import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RoutePersistence {
  static const _routeKey = 'last_route';
  static const _argsKey = 'last_route_args';
  static const Set<String> _restorableRoutes = {
    '/home',
    '/login',
    '/onboarding',
    '/personal',
    '/password',
    '/forgot-password',
    '/phone-login',
    '/profile',
    '/edit-profile',
    '/privacy-safety',
    '/notifications',
  };

  static Future<void> save(String route, [dynamic args]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_restorableRoutes.contains(route)) {
        await prefs.remove(_routeKey);
        await prefs.remove(_argsKey);
        return;
      }
      await prefs.setString(_routeKey, route);
      final encodedArgs = _encodeArgs(args);
      if (encodedArgs == null) {
        await prefs.remove(_argsKey);
      } else {
        await prefs.setString(_argsKey, encodedArgs);
      }
    } catch (_) {}
  }

  /// Returns a map with keys `route` and `args` (args may be null) or null if no saved route.
  static Future<Map<String, dynamic>?> getSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final route = prefs.getString(_routeKey);
      if (route == null) return null;
      return {
        'route': route,
        'args': _decodeArgs(prefs.getString(_argsKey)),
      };
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_routeKey);
      await prefs.remove(_argsKey);
    } catch (_) {}
  }

  static String? _encodeArgs(dynamic args) {
    if (args == null) return null;
    if (args is String || args is num || args is bool) {
      return jsonEncode(args);
    }
    if (args is Map || args is List) {
      try {
        return jsonEncode(args);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static dynamic _decodeArgs(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
}

class RoutePersistenceObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _saveRoute(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) {
      _saveRoute(newRoute);
    }
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) {
      _saveRoute(previousRoute);
    }
    super.didPop(route, previousRoute);
  }

  void _saveRoute(Route<dynamic> route) {
    final settings = route.settings;
    final routeName = settings.name;
    if (routeName == null) return;
    RoutePersistence.save(routeName, settings.arguments);
  }
}
