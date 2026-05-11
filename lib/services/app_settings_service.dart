import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsService extends ChangeNotifier {
  static const String _themeModeKey = 'app_theme_mode';
  static final AppSettingsService instance = AppSettingsService._();
  static Future<AppSettingsService>? _initializationFuture;

  ThemeMode _themeMode = ThemeMode.system;

  AppSettingsService._();

  ThemeMode get themeMode => _themeMode;

  static Future<AppSettingsService> ensureInitialized() {
    return _initializationFuture ??= instance._init().then((_) => instance);
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final rawMode = prefs.getString(_themeModeKey);
    _themeMode = _parseThemeMode(rawMode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
  }

  String themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

  ThemeMode _parseThemeMode(String? rawMode) {
    switch (rawMode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
}
