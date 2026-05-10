import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';

/// "About / Mission" page. Explains the nonprofit framing in plain
/// language, lists the principles that bind the org, and offers two
/// CTAs: support recurring (-> /subscription) or learn more (donor wall).
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const _principles = <_Principle>[
    _Principle(
      icon: Icons.shield_outlined,
      title: 'Safety is never paywalled',
      body:
          'Injury-aware exercise filtering, plate calculators, warm-up '
          'ramps, and rest timers stay free for everyone — forever.',
    ),
    _Principle(
      icon: Icons.medical_information_outlined,
      title: 'Open clinical content',
      body:
          'Our exercise library is reviewed against open-source movement-'
          'screening guidelines. A licensed DPT signs off on each entry '
          'before it ships.',
    ),
    _Principle(
      icon: Icons.volunteer_activism_outlined,
      title: 'Celebrities give in kind',
      body:
          'Workouts from professional trainers and athletes are donated '
          'as in-kind tax-deductible contributions, not paid endorsements.',
    ),
    _Principle(
      icon: Icons.lock_open_outlined,
      title: 'No data resale, ever',
      body:
          'We do not sell health data and do not run third-party ad '
          'trackers. Funding comes from donors, grants, and gym partners.',
    ),
  ];

  static const _useOfFunds = <_FundLine>[
    _FundLine(label: 'Hosting + email + tooling', percent: 35),
    _FundLine(label: 'Clinical / physio review', percent: 25),
    _FundLine(label: 'Community video moderation', percent: 20),
    _FundLine(label: 'Operations + compliance', percent: 15),
    _FundLine(label: 'Fiscal sponsor overhead', percent: 5),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FrostedScaffold(
      appBar: const GlassAppBar(title: 'Our mission'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(colors: [
                      AppPalette.auroraTeal,
                      AppPalette.auroraLime,
                    ]),
                  ),
                  child: const Icon(Icons.fitness_center,
                      color: Colors.white, size: 30),
                ),
                const SizedBox(height: 16),
                Text(
                  'Fitness for everyone, safely.',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  "We're a nonprofit fitness org running on a fiscal-"
                  'sponsorship arrangement (501(c)(3) application '
                  'pending). Our goal: make rehab-grade exercise '
                  'guidance available to anyone with a phone, '
                  'regardless of ability to pay.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.75),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Our principles',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          for (final p in _principles) ...[
            _PrincipleCard(p),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 24),
          Text(
            'How donations are used',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                for (final f in _useOfFunds) ...[
                  _FundBar(line: f),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Approximate, year-1 conservative budget. '
                    'Audited financials posted annually after our '
                    '501(c)(3) approval.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () =>
                      GoRouter.of(context).go('/subscription'),
                  icon: const Icon(Icons.favorite_outline),
                  label: const Text('Support the mission'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: () => GoRouter.of(context).go('/donors'),
              icon: const Icon(Icons.people_alt_outlined, size: 18),
              label: const Text('See our donor wall'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Principle {
  const _Principle({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
}

class _PrincipleCard extends StatelessWidget {
  const _PrincipleCard(this.p);
  final _Principle p;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(colors: [
                AppPalette.auroraViolet,
                AppPalette.auroraBlue,
              ]),
            ),
            child: Icon(p.icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  p.body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.70),
                    height: 1.4,
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

class _FundLine {
  const _FundLine({required this.label, required this.percent});
  final String label;
  final int percent;
}

class _FundBar extends StatelessWidget {
  const _FundBar({required this.line});
  final _FundLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                line.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ),
            Text(
              '${line.percent}%',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: line.percent / 100,
            minHeight: 6,
            backgroundColor: scheme.onSurface.withValues(alpha: 0.10),
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppPalette.auroraTeal),
          ),
        ),
      ],
    );
  }
}
