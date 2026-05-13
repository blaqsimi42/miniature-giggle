import 'package:flutter/widgets.dart';

double bottomSystemInset(BuildContext context) {
  return MediaQuery.of(context).viewPadding.bottom;
}

double bottomNavOuterGap(
  BuildContext context, {
  double fallback = 12,
  double insetAwareGap = 10,
}) {
  return bottomSystemInset(context) > 0 ? insetAwareGap : fallback;
}

double bottomContentPadding(
  BuildContext context, {
  required double base,
}) {
  return base + bottomSystemInset(context);
}

double usableHeightAboveSystemControls(
  BuildContext context, {
  required double totalHeight,
  required double reservedHeight,
}) {
  final result = totalHeight - reservedHeight - bottomSystemInset(context);
  return result > 0 ? result : 0;
}
