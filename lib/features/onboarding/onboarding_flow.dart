import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.surface, elevation: 0, title: const Text('Get started')),
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _controller,
              onPageChanged: (i) => setState(() => _page = i),
              children: const [
                _PageItem(title: 'Welcome', subtitle: 'Find meaningful matches with trust and privacy.'),
                _PageItem(title: 'Your Profile', subtitle: 'Share a few details to get curated matches.'),
                _PageItem(title: 'Preferences', subtitle: 'Set preferences so we can suggest compatible matches.'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (_page < 2) {
                        _controller.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.ease);
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                    child: Text(_page < 2 ? 'Next' : 'Finish'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PageItem extends StatelessWidget {
  final String title;
  final String subtitle;
  const _PageItem({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Text(title, style: AppTextStyles.heading()),
          const SizedBox(height: 12),
          Text(subtitle, style: AppTextStyles.body(), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
