// Throwaway renderer. Builds candidate screens with the REAL theme, the REAL
// GlassCard and REAL bundled posters, and writes them to PNG for review.
// Nothing here is wired into the app. Delete after the design is settled.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/core/theme/app_palette.dart';
import 'package:fitness_app/shared/widgets/glass.dart';

const out =
    'D:/Temp/claude/d--test-2-AI-trading-assistance/d4ad5558-3b52-4d0d-9496-17bb9c2f224e/scratchpad';

// ---------------------------------------------------------------- shared bits

/// Section progress: numbered, named, and showing how much is left.
class _Progress extends StatelessWidget {
  const _Progress({required this.index, required this.total, required this.label});
  final int index, total;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('0$index  ',
                style: t.textTheme.labelSmall?.copyWith(
                    color: AppPalette.auroraViolet,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2)),
            Text(label.toUpperCase(),
                style: t.textTheme.labelSmall?.copyWith(
                    color: t.colorScheme.onSurface.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 1; i <= total; i++) ...[
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: i <= index
                        ? const LinearGradient(colors: [
                            AppPalette.auroraViolet,
                            AppPalette.auroraBlue
                          ])
                        : null,
                    color: i <= index
                        ? null
                        : t.colorScheme.onSurface.withValues(alpha: 0.12),
                  ),
                ),
              ),
              if (i != total) const SizedBox(width: 5),
            ],
          ],
        ),
      ],
    );
  }
}

/// The line that says why a question is being asked.
class _Why extends StatelessWidget {
  const _Why(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded,
            size: 15, color: t.colorScheme.onSurface.withValues(alpha: 0.45)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(text,
              style: t.textTheme.bodySmall?.copyWith(
                  height: 1.35,
                  color: t.colorScheme.onSurface.withValues(alpha: 0.55))),
        ),
      ],
    );
  }
}

class _Primary extends StatelessWidget {
  const _Primary(this.label, {this.enabled = true});
  final String label;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 17),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: enabled
            ? const LinearGradient(
                colors: [AppPalette.auroraViolet, AppPalette.auroraBlue])
            : null,
        color: enabled ? null : t.colorScheme.onSurface.withValues(alpha: 0.10),
        boxShadow: enabled
            ? [
                BoxShadow(
                    color: AppPalette.auroraViolet.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8))
              ]
            : null,
      ),
      child: Center(
        child: Text(label,
            style: t.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: enabled
                    ? Colors.white
                    : t.colorScheme.onSurface.withValues(alpha: 0.35))),
      ),
    );
  }
}

// ------------------------------------------------------------------- screen 1
// Onboarding: one question, an answer you can see, and why we ask.

class MockGoal extends StatelessWidget {
  const MockGoal({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final options = [
      ('Набрать мышцы', Icons.fitness_center_rounded, true),
      ('Сбросить вес', Icons.local_fire_department_rounded, false),
      ('Стать выносливее', Icons.bolt_rounded, false),
      ('Просто держать форму', Icons.favorite_rounded, false),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 54, 22, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Progress(index: 1, total: 3, label: 'Цель'),
          const SizedBox(height: 30),
          Text('Чего вы хотите\nдобиться?',
              style: t.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w900, height: 1.12)),
          const SizedBox(height: 12),
          const _Why('От этого зависит подбор упражнений и порядок, '
              'в котором мы их предлагаем.'),
          const SizedBox(height: 24),
          for (final (label, icon, selected) in options) ...[
            GlassCard(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              gradient: selected
                  ? LinearGradient(colors: [
                      AppPalette.auroraViolet.withValues(alpha: 0.30),
                      AppPalette.auroraBlue.withValues(alpha: 0.18),
                    ])
                  : null,
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: selected
                            ? const [
                                AppPalette.auroraViolet,
                                AppPalette.auroraBlue
                              ]
                            : [
                                t.colorScheme.onSurface.withValues(alpha: 0.10),
                                t.colorScheme.onSurface.withValues(alpha: 0.06),
                              ],
                      ),
                    ),
                    child: Icon(icon,
                        color: selected
                            ? Colors.white
                            : t.colorScheme.onSurface.withValues(alpha: 0.55),
                        size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(label,
                        style: t.textTheme.titleMedium?.copyWith(
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w600)),
                  ),
                  if (selected)
                    const Icon(Icons.check_circle_rounded,
                        color: AppPalette.auroraTeal, size: 24),
                ],
              ),
            ),
            const SizedBox(height: 11),
          ],
          const Spacer(),
          const _Primary('Дальше'),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- screen 2
// Height and weight on one screen, with the number that comes out of them.

class MockBody extends StatelessWidget {
  const MockBody({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 54, 22, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Progress(index: 2, total: 3, label: 'Ваше тело'),
          const SizedBox(height: 30),
          Text('Рост и вес',
              style: t.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          const _Why('Нужны, чтобы подогнать силуэт тренера под вас и '
              'считать нагрузку. Больше нигде не используются.'),
          const SizedBox(height: 26),
          GlassCard(
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('Рост',
                        style: t.textTheme.bodyMedium?.copyWith(
                            color: t.colorScheme.onSurface
                                .withValues(alpha: 0.6))),
                    const Spacer(),
                    Text('183',
                        style: t.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w900, height: 1)),
                    const SizedBox(width: 4),
                    Text('см', style: t.textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: 10),
                const _Ruler(value: 0.62),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('Вес',
                        style: t.textTheme.bodyMedium?.copyWith(
                            color: t.colorScheme.onSurface
                                .withValues(alpha: 0.6))),
                    const Spacer(),
                    Text('84',
                        style: t.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w900, height: 1)),
                    const SizedBox(width: 4),
                    Text('кг', style: t.textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: 10),
                const _Ruler(value: 0.45),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GlassCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Text('ИМТ',
                    style: t.textTheme.bodyMedium?.copyWith(
                        color:
                            t.colorScheme.onSurface.withValues(alpha: 0.6))),
                const SizedBox(width: 10),
                Text('25.1',
                    style: t.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _BmiBar(position: 0.46),
                      const SizedBox(height: 5),
                      Text('чуть выше нормы',
                          style: t.textTheme.labelSmall?.copyWith(
                              color: t.colorScheme.onSurface
                                  .withValues(alpha: 0.55))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          const _Primary('Дальше'),
        ],
      ),
    );
  }
}

class _Ruler extends StatelessWidget {
  const _Ruler({required this.value});
  final double value;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SizedBox(
      height: 44,
      child: LayoutBuilder(
        builder: (_, c) => Stack(
          alignment: Alignment.bottomLeft,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 41; i++)
                  Container(
                    width: 1.6,
                    height: i % 5 == 0 ? 22 : 12,
                    color: t.colorScheme.onSurface
                        .withValues(alpha: i % 5 == 0 ? 0.28 : 0.14),
                  ),
              ],
            ),
            Positioned(
              left: (c.maxWidth - 3) * value,
              bottom: 0,
              child: Column(
                children: [
                  Container(
                    width: 3,
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppPalette.auroraViolet,
                          AppPalette.auroraBlue
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BmiBar extends StatelessWidget {
  const _BmiBar({required this.position});
  final double position;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 10,
      child: LayoutBuilder(
        builder: (_, c) => Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 7,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: const LinearGradient(colors: [
                  AppPalette.auroraBlue,
                  AppPalette.auroraTeal,
                  AppPalette.auroraLime,
                  AppPalette.auroraPeach,
                  AppPalette.auroraPink,
                ]),
              ),
            ),
            Positioned(
              left: c.maxWidth * position - 5,
              top: -1,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: Colors.black26, width: 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- screen 3
// The catalog, with the pictures we already ship.

class MockCatalog extends StatelessWidget {
  const MockCatalog({super.key});

  static const _rows = [
    ('Приседания со штангой', 'Квадрицепс · Ягодицы', '8 мин',
        'assets/posters/men/barbell_squat.jpg'),
    ('Жим лёжа наклонный', 'Грудь · Трицепс', '10 мин',
        'assets/posters/men/barbell_incline_bench_press_medium_grip.jpg'),
    ('Подъём на бицепс', 'Бицепс', '6 мин',
        'assets/posters/men/barbell_curl.jpg'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 54, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Тренировка',
              style: t.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          // Body-part tiles instead of a row of identical grey chips.
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              children: const [
                _AreaTile(label: 'Грудь', gradient: 0, selected: true),
                _AreaTile(label: 'Спина', gradient: 1),
                _AreaTile(label: 'Ноги', gradient: 2),
                _AreaTile(label: 'Растяжка', gradient: 3),
              ],
            ),
          ),
          const SizedBox(height: 18),
          for (final (title, muscles, mins, poster) in _rows) ...[
            GlassCard(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 96,
                      height: 68,
                      color: Colors.white,
                      child: Image.asset(poster, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(muscles,
                            style: t.textTheme.bodySmall?.copyWith(
                                color: t.colorScheme.onSurface
                                    .withValues(alpha: 0.6))),
                        const SizedBox(height: 7),
                        Row(children: [
                          _Tag(mins),
                          const SizedBox(width: 6),
                          const _Tag('видео', accent: true),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _AreaTile extends StatelessWidget {
  const _AreaTile(
      {required this.label, required this.gradient, this.selected = false});
  final String label;
  final int gradient;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      width: 86,
      margin: const EdgeInsets.only(right: 10),
      child: Column(
        children: [
          Container(
            height: 66,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient:
                  LinearGradient(colors: AppPalette.tileGradients[gradient]),
              border: selected
                  ? Border.all(color: t.colorScheme.onSurface, width: 2.5)
                  : null,
              boxShadow: [
                BoxShadow(
                    color: AppPalette.tileGradients[gradient][0]
                        .withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6))
              ],
            ),
            child: const Icon(Icons.accessibility_new_rounded,
                color: Colors.white, size: 30),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: t.textTheme.labelMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.accent = false});
  final String text;
  final bool accent;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        color: accent
            ? AppPalette.auroraTeal.withValues(alpha: 0.22)
            : t.colorScheme.onSurface.withValues(alpha: 0.08),
      ),
      child: Text(text,
          style: t.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: accent
                  ? AppPalette.auroraTeal
                  : t.colorScheme.onSurface.withValues(alpha: 0.7))),
    );
  }
}

// ------------------------------------------------------------------- screen 4
// Doing a set: what to beat, and a ring that runs.

class MockSet extends StatelessWidget {
  const MockSet({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 50, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('Приседания со штангой',
                  style: t.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
            ),
            const _Tag('подход 2 из 3', accent: true),
          ]),
          const SizedBox(height: 14),
          Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: CircularProgressIndicator(
                      value: 0.68,
                      strokeWidth: 13,
                      strokeCap: StrokeCap.round,
                      backgroundColor:
                          t.colorScheme.onSurface.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation(
                          AppPalette.auroraTeal),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('0:41',
                          style: t.textTheme.displayMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              height: 1,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                      const SizedBox(height: 4),
                      Text('ОТДЫХ',
                          style: t.textTheme.labelSmall?.copyWith(
                              letterSpacing: 2,
                              fontWeight: FontWeight.w900,
                              color: t.colorScheme.onSurface
                                  .withValues(alpha: 0.5))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          GlassCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    _h(t, '#', 26),
                    _h(t, 'БЫЛО', 92),
                    _h(t, 'КГ', 62),
                    _h(t, 'ПОВТ', 56),
                    const SizedBox(width: 30),
                  ],
                ),
                const Divider(height: 14),
                _row(t, '1', '100 кг × 8', '105', '8', true),
                _row(t, '2', '100 кг × 8', '105', '8', true),
                _row(t, '3', '100 кг × 7', '105', '', false),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _Primary('Записать подход'),
        ],
      ),
    );
  }

  Widget _h(ThemeData t, String s, double w) => SizedBox(
        width: w,
        child: Text(s,
            style: t.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: t.colorScheme.onSurface.withValues(alpha: 0.45))),
      );

  Widget _row(ThemeData t, String n, String prev, String kg, String reps,
          bool done) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
                width: 26,
                child: Text(n,
                    style: t.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w800))),
            SizedBox(
                width: 92,
                child: Text(prev,
                    style: t.textTheme.bodySmall?.copyWith(
                        color: t.colorScheme.onSurface
                            .withValues(alpha: 0.45)))),
            _cell(t, kg, 62),
            _cell(t, reps, 56),
            const Spacer(),
            Icon(
                done
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                size: 24,
                color: done
                    ? AppPalette.auroraTeal
                    : t.colorScheme.onSurface.withValues(alpha: 0.25)),
          ],
        ),
      );

  Widget _cell(ThemeData t, String v, double w) => Container(
        width: w - 8,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: t.colorScheme.onSurface.withValues(alpha: 0.07),
        ),
        child: Center(
          child: Text(v,
              style: t.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ),
      );
}

// ------------------------------------------------------------------- screen 5
// Progress: the year at a glance.

class MockProgress extends StatelessWidget {
  const MockProgress({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // Deterministic pseudo-pattern; no Random (unavailable here) and none
    // wanted — a fixed picture is easier to compare between rounds.
    bool on(int i) => (i * 7 + i ~/ 3) % 5 < 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 54, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Прогресс',
              style: t.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _stat(t, '12', 'дней подряд', 0)),
            const SizedBox(width: 10),
            Expanded(child: _stat(t, '48', 'тренировок', 1)),
            const SizedBox(width: 10),
            Expanded(child: _stat(t, '19 т', 'поднято', 2)),
          ]),
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Постоянство',
                    style: t.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                Text('40 из 93 дней · 3 раза в неделю',
                    style: t.textTheme.labelSmall?.copyWith(
                        color: t.colorScheme.onSurface
                            .withValues(alpha: 0.55))),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < 91; i++)
                      Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: on(i)
                              ? const LinearGradient(colors: [
                                  AppPalette.auroraTeal,
                                  AppPalette.auroraLime
                                ])
                              : null,
                          color: on(i)
                              ? null
                              : t.colorScheme.onSurface
                                  .withValues(alpha: 0.09),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('Личные рекорды',
                      style: t.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  const _Tag('3 новых', accent: true),
                ]),
                const SizedBox(height: 10),
                _pr(t, 'Присед', '140 кг', '+5'),
                _pr(t, 'Жим лёжа', '95 кг', '+2.5'),
                _pr(t, 'Тяга', '160 кг', '+5'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(ThemeData t, String v, String label, int g) => GlassCard(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShaderMask(
              shaderCallback: (r) =>
                  LinearGradient(colors: AppPalette.tileGradients[g])
                      .createShader(r),
              child: Text(v,
                  style: t.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900, color: Colors.white)),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: t.textTheme.labelSmall?.copyWith(
                    color:
                        t.colorScheme.onSurface.withValues(alpha: 0.55))),
          ],
        ),
      );

  Widget _pr(ThemeData t, String name, String v, String delta) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: AppPalette.auroraLime.withValues(alpha: 0.20),
            ),
            child: const Icon(Icons.emoji_events_rounded,
                size: 17, color: AppPalette.auroraLime),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: t.textTheme.bodyMedium)),
          Text(v,
              style: t.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(width: 8),
          Text(delta,
              style: t.textTheme.labelSmall?.copyWith(
                  color: AppPalette.auroraTeal, fontWeight: FontWeight.w800)),
        ]),
      );
}

// ---------------------------------------------------------------------- render

Future<void> shoot(WidgetTester tester, String name, Widget screen,
    {Brightness brightness = Brightness.dark}) async {
  // physicalSize is in device pixels; logical size = physical / dpr.
  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  final dark = brightness == Brightness.dark;
  // The app's palette, NOT `AppTheme`: that constructor resolves Inter through
  // Google Fonts the moment it is called, and a test has no network. Colours
  // here are the shipped ones; the letterforms in these PNGs are the
  // platform's, so judge the layout and the colour, not the typeface.
  final onSurface =
      dark ? AppPalette.darkOnSurface : AppPalette.lightOnSurface;
  final theme = ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppPalette.auroraViolet,
      brightness: brightness,
    ).copyWith(
      onSurface: onSurface,
      surface: dark ? AppPalette.darkSurface : AppPalette.lightSurface,
    ),
    useMaterial3: true,
    fontFamily: 'MockSans',
    fontFamilyFallback: const ['MockSansBold'],
  );

  final key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    home: RepaintBoundary(
      key: key,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: brightness == Brightness.dark
                ? const [Color(0xFF16072E), Color(0xFF050214), Color(0xFF0B1233)]
                : const [Color(0xFFF6ECFF), Color(0xFFEDE3F8), Color(0xFFE4F0FF)],
          ),
        ),
        child: screen,
      ),
    ),
  ));
  // Real bitmaps need a real event loop; a widget test does not have one
  // unless you ask. Without this the poster ImageProviders never resolve and
  // the catalog screen renders three empty boxes.
  await tester.runAsync(() async {
    for (final e in tester.widgetList<Image>(find.byType(Image))) {
      await precacheImage(e.image, key.currentContext!);
    }
  });
  await tester.pump(const Duration(milliseconds: 300));
  tester.takeException();

  // Same reason: toImage() completes on the real loop, so awaiting it on the
  // fake one hangs forever. The first screen happened to slip through and the
  // second sat there until the ten-minute timeout.
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/mock_$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  // Cyrillic. The engine's fallback face in a test has no Cyrillic glyphs, so
  // every Russian word rendered as a row of tofu boxes and the first sheet was
  // unreadable. Loading a real system face is the only way these images say
  // anything about the design rather than about the test harness.
  setUpAll(() async {
    // Cyrillic, and the icon set. Without the first every Russian word renders
    // as a row of tofu boxes; without the second every Icon does. Either way
    // the review ends up being about the harness instead of the design.
    for (final (family, file) in const [
      ('MockSans', 'C:/Windows/Fonts/segoeui.ttf'),
      (
        'MaterialIcons',
        'D:/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf'
      ),
    ]) {
      final f = File(file);
      if (!f.existsSync()) continue;
      final loader = FontLoader(family)
        ..addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
      await loader.load();
    }
  });

  testWidgets('1 goal', (t) => shoot(t, '1_goal', const MockGoal()));
  testWidgets('2 body', (t) => shoot(t, '2_body', const MockBody()));
  testWidgets('3 catalog', (t) => shoot(t, '3_catalog', const MockCatalog()));
  testWidgets('4 set', (t) => shoot(t, '4_set', const MockSet()));
  testWidgets('5 progress', (t) => shoot(t, '5_progress', const MockProgress()));
  testWidgets('3 catalog light',
      (t) => shoot(t, '3_catalog_light', const MockCatalog(),
          brightness: Brightness.light));
}
