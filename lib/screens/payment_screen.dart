import 'package:flutter/material.dart';

import '../widgets/upgrade_flow.dart';

class PaymentScreen extends StatefulWidget {
  final int amount;
  final String initialPlanId;
  final bool includeBoostPlan;

  const PaymentScreen({
    super.key,
    this.amount = 239900,
    this.initialPlanId = 'premium',
    this.includeBoostPlan = false,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  static const Color _kGreen = Color(0xFF0F5C2E);
  static const Color _kCream = Color(0xFFF7F5F2);
  static const Color _kMuted = Color(0xFF6B7280);
  static const Color _kBorder = Color(0xFFE9E2D8);

  late final List<_PlanOption> _plans;
  bool _startingCheckout = false;
  int _selectedPlanIndex = 0;

  @override
  void initState() {
    super.initState();
    _plans = [
      if (widget.includeBoostPlan)
        const _PlanOption(
          id: 'boost',
          title: 'Boost Pass',
          subtitle: 'Extra visibility for 24 hours',
          amount: 199,
          billingLabel: '/ 24 hours',
          badgeLabel: 'Fast Track',
          accent: Color(0xFF0F5C2E),
          softAccent: Color(0xFFE9F6EE),
          icon: Icons.auto_awesome_rounded,
          features: [
            'Priority discovery placement',
            'More profile impressions',
            'Stronger short-term visibility',
            'Perfect for active search days',
          ],
        ),
      const _PlanOption(
        id: 'basic',
        title: 'Basic Plan',
        subtitle: 'Great for getting started',
        amount: 199900,
        billingLabel: '/ 3 months',
        badgeLabel: '20% OFF',
        accent: Color(0xFF0F5C2E),
        softAccent: Color(0xFFE9F6EE),
        icon: Icons.person_outline_rounded,
        features: [
          'Verified profiles',
          'Limited chat',
          'Basic search filters',
          'Profile visibility',
        ],
      ),
      _PlanOption(
        id: 'premium',
        title: 'Premium Plan',
        subtitle: 'More features, better matches',
        amount: widget.amount,
        billingLabel: '/ 3 months',
        badgeLabel: 'Most Popular',
        savingsLabel: '40% OFF',
        accent: const Color(0xFFB7791F),
        softAccent: const Color(0xFFFFF4DF),
        icon: Icons.workspace_premium_outlined,
        features: const [
          'Unlimited chat',
          'Advanced filters',
          'See who viewed you',
          'Read receipts',
          'Priority support',
          'Profile boost',
        ],
        highlighted: true,
      ),
      const _PlanOption(
        id: 'relationship_manager',
        title: 'Relationship Manager',
        subtitle: 'Personal guidance and curated support',
        amount: 999900,
        billingLabel: '/ 3 months',
        badgeLabel: '50% OFF',
        accent: Color(0xFF6B21A8),
        softAccent: Color(0xFFF4EBFF),
        icon: Icons.support_agent_rounded,
        features: [
          'All premium features',
          'Dedicated relationship manager',
          'Handpicked matches',
          'Priority shortlisting',
          'Family consultation support',
          'Personalized match advice',
        ],
      ),
      const _PlanOption(
        id: 'lifetime',
        title: 'Lifetime Plan',
        subtitle: 'One payment, lifetime access',
        amount: 1999900,
        billingLabel: 'one-time',
        badgeLabel: '50% OFF',
        accent: Color(0xFFD18A00),
        softAccent: Color(0xFFFFF4D6),
        icon: Icons.emoji_events_outlined,
        features: [
          'Lifetime premium access',
          'Verified badge',
          'Direct contact unlock',
          'Profile boost',
          'Full privacy control',
          'No recurring charges',
        ],
      ),
    ];

    final initialIndex = _plans.indexWhere(
      (plan) => plan.id == widget.initialPlanId,
    );
    _selectedPlanIndex = initialIndex >= 0 ? initialIndex : 0;
  }

  _PlanOption get _selectedPlan => _plans[_selectedPlanIndex];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kCream,
      appBar: AppBar(
        backgroundColor: _kCream,
        surfaceTintColor: _kCream,
        elevation: 0,
        centerTitle: true,
        title: const Text('Choose Your Plan'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                const Text(
                  'Unlock better matches and premium features with a plan that feels consistent with the rest of your profile journey.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _kMuted,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F7F3),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFD7EBDD)),
                  ),
                  child: const Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _TrustPill(
                        icon: Icons.verified_user_outlined,
                        label: 'Safe',
                      ),
                      _TrustPill(
                        icon: Icons.lock_outline_rounded,
                        label: 'Secure',
                      ),
                      _TrustPill(
                        icon: Icons.favorite_outline,
                        label: 'Family Values',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ...List.generate(_plans.length, (index) {
                  final plan = _plans[index];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == _plans.length - 1 ? 0 : 16,
                    ),
                    child: _PlanCard(
                      plan: plan,
                      selected: index == _selectedPlanIndex,
                      onTap: () => setState(() => _selectedPlanIndex = index),
                    ),
                  );
                }),
                const SizedBox(height: 18),
                _BenefitsFooter(plan: _selectedPlan),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: Color(0xFFF7F5F2),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 16,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Column(
                      children: [
                        _SummaryRow(
                          label: 'Selected plan',
                          value: _selectedPlan.title,
                        ),
                        const SizedBox(height: 10),
                        _SummaryRow(
                          label: 'Billing',
                          value: _selectedPlan.billingLabel,
                        ),
                        const SizedBox(height: 10),
                        _SummaryRow(
                          label: 'Total',
                          value: _formatAmount(_selectedPlan.amount),
                          emphasize: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _startingCheckout ? null : _continueToCheckout,
                      style: FilledButton.styleFrom(
                        backgroundColor: _selectedPlan.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _startingCheckout
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Continue to Payment',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline, size: 14, color: _kGreen),
                      SizedBox(width: 6),
                      Text(
                        '100% Secure Payments',
                        style: TextStyle(fontSize: 12, color: _kMuted),
                      ),
                      SizedBox(width: 12),
                      Icon(
                        Icons.verified_user_outlined,
                        size: 14,
                        color: _kGreen,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Trusted & encrypted',
                        style: TextStyle(fontSize: 12, color: _kMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _continueToCheckout() async {
    setState(() => _startingCheckout = true);
    try {
      final ok = await showUpgradeFlow(
        context,
        amount: _selectedPlan.amount,
        plan: _selectedPlan.id,
        skipIntro: true,
      );
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(_selectedPlan.id);
      }
    } finally {
      if (mounted) {
        setState(() => _startingCheckout = false);
      }
    }
  }

  static String _formatAmount(int amount) {
    final formatted = amount.toString();
    final chars = formatted.split('').reversed.toList();
    final buffer = StringBuffer();
    for (var i = 0; i < chars.length; i++) {
      if (i > 0 && i % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(chars[i]);
    }
    return '\$${buffer.toString().split('').reversed.join()}';
  }
}

class _PlanOption {
  final String id;
  final String title;
  final String subtitle;
  final int amount;
  final String billingLabel;
  final String badgeLabel;
  final IconData icon;
  final Color accent;
  final Color softAccent;
  final List<String> features;
  final bool highlighted;
  final String? savingsLabel;

  const _PlanOption({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.billingLabel,
    required this.badgeLabel,
    required this.icon,
    required this.accent,
    required this.softAccent,
    required this.features,
    this.highlighted = false,
    this.savingsLabel,
  });
}

class _PlanCard extends StatelessWidget {
  final _PlanOption plan;
  final bool selected;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? plan.accent : _PaymentScreenState._kBorder;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: borderColor,
            width: selected ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? plan.accent.withAlpha((0.12 * 255).round())
                  : const Color(0x0A000000),
              blurRadius: selected ? 22 : 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: plan.softAccent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(plan.icon, color: plan.accent, size: 32),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            plan.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (plan.highlighted)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: plan.softAccent,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: plan.accent.withAlpha((0.35 * 255).round()),
                                ),
                              ),
                              child: Text(
                                plan.badgeLabel,
                                style: TextStyle(
                                  color: plan.accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: _PaymentScreenState._formatAmount(plan.amount),
                              style: TextStyle(
                                color: plan.accent,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            TextSpan(
                              text: ' ${plan.billingLabel}',
                              style: const TextStyle(
                                color: Color(0xFF374151),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        plan.subtitle,
                        style: const TextStyle(
                          color: _PaymentScreenState._kMuted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: plan.softAccent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    plan.savingsLabel ?? plan.badgeLabel,
                    style: TextStyle(
                      color: plan.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      for (final feature in plan.features
                          .take((plan.features.length / 2).ceil()))
                        _FeatureItem(
                          label: feature,
                          color: plan.accent,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    children: [
                      for (final feature in plan.features
                          .skip((plan.features.length / 2).ceil()))
                        _FeatureItem(
                          label: feature,
                          color: plan.accent,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: plan.accent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                selected ? 'Selected Plan' : 'Tap to Select',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final String label;
  final Color color;

  const _FeatureItem({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF1F2937),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitsFooter extends StatelessWidget {
  final _PlanOption plan;

  const _BenefitsFooter({required this.plan});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FooterTile(
            icon: Icons.verified_outlined,
            title: 'Verified Profiles',
            subtitle: 'Real people, serious intentions',
            accent: plan.accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _FooterTile(
            icon: Icons.lock_outline_rounded,
            title: 'Privacy Focused',
            subtitle: 'Your privacy is a top priority',
            accent: plan.accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _FooterTile(
            icon: Icons.groups_2_outlined,
            title: 'Family Involved',
            subtitle: 'Built with family values',
            accent: plan.accent,
          ),
        ),
      ],
    );
  }
}

class _FooterTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;

  const _FooterTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _PaymentScreenState._kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withAlpha((0.10 * 255).round()),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: _PaymentScreenState._kMuted,
              height: 1.4,
            ),
          ),
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
              color: emphasize ? Colors.black87 : _PaymentScreenState._kMuted,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasize ? 18 : 15,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
            color: emphasize
                ? _PaymentScreenState._kGreen
                : Colors.black87,
          ),
        ),
      ],
    );
  }
}

class _TrustPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrustPill({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: _PaymentScreenState._kGreen),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: _PaymentScreenState._kGreen,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
