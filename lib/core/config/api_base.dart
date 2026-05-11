import 'package:flutter/foundation.dart';

const String _kProductionApiBaseUrl =
    'https://miniature-giggle-8q60.onrender.com';
const String _kDevelopmentApiBaseUrl = 'http://localhost:3000';

String get kApiBaseUrl {
  const override = String.fromEnvironment('API_BASE_URL', defaultValue: '');
  if (override.isNotEmpty) return override;
  return kReleaseMode ? _kProductionApiBaseUrl : _kDevelopmentApiBaseUrl;
}
