import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final _noDecimals = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final _withDecimals = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  /// Formats a numeric-ish value as Indian Rupees.
  /// Accepts `int`, `double`, or numeric `String`. Falls back to the original
  /// `toString()` when parsing fails.
  static String format(dynamic value) {
    if (value == null) return '';

    if (value is num) {
      if (value % 1 == 0) return _noDecimals.format(value.toInt());
      return _withDecimals.format(value);
    }

    if (value is String) {
      final cleaned = value.replaceAll(RegExp(r"[^0-9.]"), '');
      if (cleaned.isEmpty) return value;
      final asDouble = double.tryParse(cleaned);
      if (asDouble == null) return value;
      if (asDouble % 1 == 0) return _noDecimals.format(asDouble.toInt());
      return _withDecimals.format(asDouble);
    }

    return value.toString();
  }
}
