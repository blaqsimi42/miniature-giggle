import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../core/utils/currency_formatter.dart';

import '../core/config/service_locator.dart';
import '../services/auth_service.dart';
import '../services/mock_payment_service.dart';
import '../services/stripe_service.dart';

const Color _kUpgradeGreen = Color(0xFF0A5C36);
const Color _kUpgradeSoftGreen = Color(0xFFE8F4EB);
const Color _kUpgradeCream = Color(0xFFFFFBF6);
const Color _kUpgradeBorder = Color(0xFFE9E0D3);
const Color _kUpgradeMuted = Color(0xFF736E67);

enum _UpgradeStep { locked, payment, review, success }

Future<bool> showUpgradeFlow(
  BuildContext context, {
  int amount = 499,
  String plan = 'premium',
  bool skipIntro = false,
}) async {
  final auth = AuthService();
  final user = auth.getCurrentUser();
  if (user == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sign in to upgrade')));
    }
    return false;
  }

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _UpgradeFlowSheet(
      amount: amount,
      plan: plan,
      userId: user.uid,
      skipIntro: skipIntro,
    ),
  );

  return result ?? false;
}

class _UpgradeFlowSheet extends StatefulWidget {
  final int amount;
  final String plan;
  final String userId;
  final bool skipIntro;

  const _UpgradeFlowSheet({
    required this.amount,
    required this.plan,
    required this.userId,
    required this.skipIntro,
  });

  @override
  State<_UpgradeFlowSheet> createState() => _UpgradeFlowSheetState();
}

class _UpgradeFlowSheetState extends State<_UpgradeFlowSheet> {
  late final Future<StripeConfig> _stripeConfigFuture;
  _UpgradeStep _step = _UpgradeStep.locked;
  int _selectedMethod = 0;
  bool _processing = false;
  CardFieldInputDetails? _card;

  final _paymentMethods = const [
    (
      icon: Icons.account_balance_wallet_outlined,
      title: 'UPI',
      subtitle: 'Pay using any UPI app',
    ),
    (
      icon: Icons.credit_card_outlined,
      title: 'Card',
      subtitle: 'Debit / Credit Card',
    ),
    (
      icon: Icons.account_balance_outlined,
      title: 'Net Banking',
      subtitle: 'All major banks',
    ),
    (
      icon: Icons.wallet_outlined,
      title: 'Wallets',
      subtitle: 'PhonePe, Paytm, Amazon Pay',
    ),
    (
      icon: Icons.more_horiz_rounded,
      title: 'More Options',
      subtitle: 'Other payment methods',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _stripeConfigFuture = getIt<StripeService>().fetchConfig();
    _step = widget.skipIntro ? _UpgradeStep.payment : _UpgradeStep.locked;
  }

  bool get _isBoostPlan => widget.plan == 'boost';
  bool get _isLifetimePlan => widget.plan == 'lifetime';
  bool get _isRelationshipManagerPlan => widget.plan == 'relationship_manager';
  bool get _isBasicPlan => widget.plan == 'basic';

  String get _entryTitle => _isBoostPlan ? 'Boost Your Profile' : 'Unlock Your Plan';
  String get _entryDescription => _isBoostPlan
      ? 'Get extra visibility for 24 hours and appear higher in discovery.'
      : 'Choose your plan and continue to secure payment.';
  String get _entryButtonLabel => _isBoostPlan ? 'Get Boost' : 'Continue';
  String get _successTitle {
    if (_isBoostPlan) return 'Boost Activated!';
    if (_isLifetimePlan) return 'Lifetime Unlocked!';
    if (_isRelationshipManagerPlan) return 'Relationship Manager Activated!';
    if (_isBasicPlan) return 'Basic Plan Activated!';
    return 'Payment Successful!';
  }
  String get _successDescription => _isBoostPlan
      ? 'Your profile is now being shown to more people.\nEnjoy the extra visibility.'
      : _isLifetimePlan
          ? 'You now have lifetime access.\nEnjoy premium features without recurring charges.'
          : _isRelationshipManagerPlan
              ? 'Your dedicated support plan is now active.\nEnjoy a more guided matchmaking journey.'
              : _isBasicPlan
                  ? 'Your basic plan is now active.\nStart exploring verified connections.'
                  : 'You are now Premium.\nEnjoy unlimited conversations.';
  String get _successButtonLabel =>
      _isBoostPlan ? 'Keep Exploring' : 'Start Chatting';
  String get _planCardTitle {
    if (_isBoostPlan) return 'Profile Boost (24 Hours)';
    if (_isLifetimePlan) return 'Lifetime Plan';
    if (_isRelationshipManagerPlan) return 'Relationship Manager';
    if (_isBasicPlan) return 'Basic Plan';
    return 'Premium Plan';
  }

  String get _planCardDescription {
    if (_isBoostPlan) {
      return 'Priority visibility, more profile views,\nand stronger discovery reach';
    }
    if (_isLifetimePlan) {
      return 'One payment, lifetime premium access,\nfull privacy and direct contact unlock';
    }
    if (_isRelationshipManagerPlan) {
      return 'Dedicated support, curated matches,\nand guided family-friendly matchmaking';
    }
    if (_isBasicPlan) {
      return 'Verified profiles, limited chat,\nand essential discovery features';
    }
    return 'Unlimited chats, See who liked you,\nAdvanced filters';
  }

  String get _planBillingLabel {
    if (_isBoostPlan) return '/24 hours';
    if (_isLifetimePlan) return 'one-time';
    if (_isBasicPlan || _isRelationshipManagerPlan) return '/3 months';
    return '/3 months';
  }

  @override
  Widget build(BuildContext context) {
    final raw = MediaQuery.of(context).viewInsets.bottom;
    final bottomInset = raw < 0 ? 0.0 : raw;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, bottomInset > 0 ? bottomInset : 12),
        child: Material(
          color: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
              color: _kUpgradeCream,
              borderRadius: BorderRadius.circular(32),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 28,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: FutureBuilder<StripeConfig>(
              future: _stripeConfigFuture,
              builder: (context, snapshot) {
                final cfg = snapshot.data;
                final canUseStripe =
                    !kIsWeb &&
                    cfg != null &&
                    cfg.stripeEnabled &&
                    cfg.publishableKey != null;

                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _buildStep(context, canUseStripe),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context, bool canUseStripe) {
    switch (_step) {
      case _UpgradeStep.locked:
        return _buildLockedStep();
      case _UpgradeStep.payment:
        return _buildPaymentStep(canUseStripe);
      case _UpgradeStep.review:
        return _buildReviewStep(canUseStripe);
      case _UpgradeStep.success:
        return _buildSuccessStep();
    }
  }

  Widget _buildLockedStep() {
    return Padding(
      key: const ValueKey('locked'),
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHandle(),
          const SizedBox(height: 22),
          Container(
            width: 86,
            height: 86,
            decoration: const BoxDecoration(
              color: _kUpgradeSoftGreen,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isBoostPlan
                  ? Icons.auto_awesome_rounded
                  : Icons.lock_outline_rounded,
              color: _kUpgradeGreen,
              size: 38,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _entryTitle,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            _entryDescription,
            textAlign: TextAlign.center,
            style: TextStyle(color: _kUpgradeMuted, height: 1.45),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => setState(() => _step = _UpgradeStep.payment),
              style: FilledButton.styleFrom(
                backgroundColor: _kUpgradeGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                _entryButtonLabel,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 14, color: _kUpgradeGreen),
              SizedBox(width: 6),
              Text(
                'Secure payment',
                style: TextStyle(fontSize: 12, color: _kUpgradeMuted),
              ),
              SizedBox(width: 12),
              Text('|', style: TextStyle(fontSize: 12, color: _kUpgradeMuted)),
              SizedBox(width: 12),
              Text(
                'Cancel anytime',
                style: TextStyle(fontSize: 12, color: _kUpgradeMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentStep(bool canUseStripe) {
    return SizedBox(
      key: const ValueKey('payment'),
      height: 680,
      child: Column(
        children: [
          _SheetHeader(
            title: 'Payment',
            onBack: () => setState(() => _step = _UpgradeStep.locked),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
              children: [
                const Text(
                  'SELECT PAYMENT METHOD',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _kUpgradeMuted,
                    letterSpacing: 0.45,
                  ),
                ),
                const SizedBox(height: 12),
                _buildMethodCard(),
                if (canUseStripe && _selectedMethod == 1) ...[
                  const SizedBox(height: 16),
                  _buildCardDetails(),
                ],
              ],
            ),
          ),
          _SheetFooter(
            primaryLabel: 'Continue',
            onPrimary: _processing ? null : () => setState(() => _step = _UpgradeStep.review),
            loading: _processing,
            info: const [
              (Icons.lock_outline, '100% Secure Payments'),
              (Icons.verified_user_outlined, 'SSL Encrypted'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReviewStep(bool canUseStripe) {
    return SizedBox(
      key: const ValueKey('review'),
      height: 680,
      child: Column(
        children: [
          _SheetHeader(
            title: 'Review Order',
            onBack: () => setState(() => _step = _UpgradeStep.payment),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
              children: [
                _PlanCard(
                  amount: widget.amount,
                  title: _planCardTitle,
                  description: _planCardDescription,
                  billingLabel: _planBillingLabel,
                ),
                const SizedBox(height: 18),
                _ReviewTotals(amount: widget.amount),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _kUpgradeBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _kUpgradeSoftGreen,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _paymentMethods[_selectedMethod].icon,
                          color: _kUpgradeGreen,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _paymentMethods[_selectedMethod].title,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              canUseStripe && _selectedMethod == 1
                                  ? 'Card details captured securely'
                                  : _paymentMethods[_selectedMethod].subtitle,
                              style: const TextStyle(
                                color: _kUpgradeMuted,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _SheetFooter(
            primaryLabel: 'Proceed to Pay',
            onPrimary: _processing ? null : () => _completeUpgrade(canUseStripe),
            loading: _processing,
            info: const [
              (Icons.lock_outline, 'Secure payment'),
              (Icons.circle, 'Cancel anytime'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessStep() {
    return Padding(
      key: const ValueKey('success'),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: const BoxDecoration(
              color: _kUpgradeSoftGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: _kUpgradeGreen,
              size: 52,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _successTitle,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            _successDescription,
            textAlign: TextAlign.center,
            style: TextStyle(color: _kUpgradeMuted, height: 1.5),
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: _kUpgradeGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                _successButtonLabel,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _kUpgradeBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: List.generate(_paymentMethods.length, (index) {
          final method = _paymentMethods[index];
          final selected = index == _selectedMethod;
          return Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: selected ? _kUpgradeSoftGreen : const Color(0xFFF8F3EB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(method.icon, color: _kUpgradeGreen),
                ),
                title: Text(method.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  method.subtitle,
                  style: const TextStyle(fontSize: 12.5, color: _kUpgradeMuted),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFBAB2A7)),
                onTap: () => setState(() => _selectedMethod = index),
              ),
              if (index != _paymentMethods.length - 1)
                const Divider(height: 1, indent: 14, endIndent: 14),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildCardDetails() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kUpgradeBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CARD DETAILS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _kUpgradeMuted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 12),
          CardField(
            onCardChanged: (value) => setState(() => _card = value),
          ),
        ],
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      width: 44,
      height: 5,
      decoration: BoxDecoration(
        color: const Color(0xFFE7DED1),
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }

  Future<void> _completeUpgrade(bool canUseStripe) async {
    if (_processing) {
      return;
    }

    if (canUseStripe && _selectedMethod == 1) {
      if (_card == null || _card!.complete != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter valid card details')),
        );
        return;
      }
    }

    setState(() => _processing = true);
    try {
      final ok = await _performUpgradePayment(
        context: context,
        userId: widget.userId,
        amount: widget.amount,
        plan: widget.plan,
        canUseStripe: canUseStripe && _selectedMethod == 1,
      );
      if (!mounted) {
        return;
      }
      if (ok) {
        setState(() => _step = _UpgradeStep.success);
      } else {
        Navigator.of(context).pop(false);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upgrade failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }
}

class _SheetHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _SheetHeader({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _SheetFooter extends StatelessWidget {
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool loading;
  final List<(IconData, String)> info;

  const _SheetFooter({
    required this.primaryLabel,
    required this.onPrimary,
    required this.loading,
    required this.info,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onPrimary,
                style: FilledButton.styleFrom(
                  backgroundColor: _kUpgradeGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        primaryLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: List.generate(info.length, (index) {
                final item = info[index];
                final isDot = item.$1 == Icons.circle;
                if (isDot) {
                  return const Text('|', style: TextStyle(color: _kUpgradeMuted));
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(item.$1, size: 14, color: _kUpgradeGreen),
                    const SizedBox(width: 6),
                    Text(
                      item.$2,
                      style: const TextStyle(fontSize: 12, color: _kUpgradeMuted),
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final int amount;
  final String title;
  final String description;
  final String billingLabel;

  const _PlanCard({
    required this.amount,
    required this.title,
    required this.description,
    required this.billingLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kUpgradeBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  description,
                  style: const TextStyle(color: _kUpgradeMuted, height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                CurrencyFormatter.format(amount),
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              Text(
                billingLabel,
                style: const TextStyle(color: _kUpgradeMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewTotals extends StatelessWidget {
  final int amount;

  const _ReviewTotals({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kUpgradeBorder),
      ),
      child: Column(
        children: [
          _SummaryRow(label: 'Amount', value: CurrencyFormatter.format(amount)),
          const SizedBox(height: 12),
          _SummaryRow(label: 'Taxes', value: CurrencyFormatter.format(0)),
          const SizedBox(height: 14),
          _SummaryRow(label: 'Total', value: CurrencyFormatter.format(amount), emphasize: true),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
              color: emphasize ? Colors.black87 : _kUpgradeMuted,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasize ? 22 : 15,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

Future<bool> _performUpgradePayment({
  required BuildContext context,
  required String userId,
  required int amount,
  required String plan,
  required bool canUseStripe,
}) async {
  try {
    if (canUseStripe) {
      final stripe = getIt<StripeService>();
      final cfg = await stripe.fetchConfig();
      if (cfg.publishableKey == null) {
        throw Exception('Stripe is not configured');
      }

      Stripe.publishableKey = cfg.publishableKey!;
      await Stripe.instance.applySettings();

      final pi = await stripe.createPaymentIntent(
        amount: amount,
        metadata: {'userId': userId, 'plan': plan},
      );
      final clientSecret = pi['clientSecret'] as String?;
      if (clientSecret == null) {
        throw Exception('Missing clientSecret');
      }

      await Stripe.instance.confirmPayment(
        paymentIntentClientSecret: clientSecret,
        data: PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(),
        ),
      );
    }

    await getIt<MockPaymentService>().mockPaymentSuccess(
      userId: userId,
      amount: amount,
      plan: plan,
    );

    try {
      final docStream = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots();
      final snap = await docStream.firstWhere((s) {
        final data = s.data();
        if (data == null) return false;
        if (plan == 'boost') {
          final boost = data['boostExpiresAt'];
          if (boost is Timestamp) {
            return boost.toDate().isAfter(DateTime.now());
          }
          return false;
        }
        return data['isPremium'] == true;
      }).timeout(const Duration(seconds: 10));
      if (snap.exists) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                plan == 'boost'
                    ? 'Boost activated successfully'
                    : 'Premium unlocked successfully',
              ),
            ),
          );
        }
        return true;
      }
    } on TimeoutException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Upgrade processed. Premium will activate once the server confirms.',
            ),
          ),
        );
      }
      return false;
    } catch (_) {
      return false;
    }

    return false;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upgrade failed: $e')));
    }
    rethrow;
  }
}
