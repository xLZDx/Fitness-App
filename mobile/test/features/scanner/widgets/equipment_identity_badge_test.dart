import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/scanner/widgets/equipment_identity_badge.dart';
import 'package:fitness_app/features/visual_equipment/data/equipment_identity.dart';

EquipmentIdentity _identity(Map<String, dynamic> overrides) {
  final base = <String, dynamic>{
    'scanId': 'scan-1',
    'recognitionSessionId': 'session-1',
    'identityContractVersion': 'v1',
    'authority': {
      'catalogVersion': 'cv-test',
      'ocrVersion': 'p2g1-mlkit-latin-structured-v1',
      'textPolicyVersion': 'text-policy-v1',
      'fusionPolicyVersion': 'fusion-policy-v1',
      'identityPolicyVersion': 'identity-policy-v1',
    },
    'evidenceLane': 'TEXT_ONLY',
    'decision': 'NEED_MORE_VIEW',
    'verifierInvoked': false,
  }..addAll(overrides);
  return EquipmentIdentity.fromJson(base);
}

Widget _harness(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('EquipmentIdentityBadge -- OP-01 silence', () {
    testWidgets('renders nothing for a null identity', (tester) async {
      await tester.pumpWidget(_harness(const EquipmentIdentityBadge(identity: null)));
      expect(find.byKey(const Key('equipment-identity-badge')), findsNothing);
    });

    testWidgets('renders nothing for ABSTAIN', (tester) async {
      final identity = _identity({
        'decision': 'ABSTAIN',
        'abstainReason': 'LOW_CONFIDENCE',
      });
      await tester.pumpWidget(_harness(EquipmentIdentityBadge(identity: identity)));
      expect(find.byKey(const Key('equipment-identity-badge')), findsNothing);
    });

    testWidgets('renders nothing for an UNAVAILABLE_* decision', (tester) async {
      final identity = _identity({
        'decision': 'UNAVAILABLE_TIMEOUT',
        'failureCode': 'TIMEOUT',
      });
      await tester.pumpWidget(_harness(EquipmentIdentityBadge(identity: identity)));
      expect(find.byKey(const Key('equipment-identity-badge')), findsNothing);
    });

    testWidgets('renders nothing for CANCELLED_STALE', (tester) async {
      final identity = _identity({'decision': 'CANCELLED_STALE'});
      await tester.pumpWidget(_harness(EquipmentIdentityBadge(identity: identity)));
      expect(find.byKey(const Key('equipment-identity-badge')), findsNothing);
    });

    testWidgets('renders nothing for NEED_MORE_VIEW (separate prompt widget instead)',
        (tester) async {
      final identity = _identity({'decision': 'NEED_MORE_VIEW'});
      await tester.pumpWidget(_harness(EquipmentIdentityBadge(identity: identity)));
      expect(find.byKey(const Key('equipment-identity-badge')), findsNothing);
    });
  });

  group('EquipmentIdentityBadge -- OP-02 collapsed by default, tap to expand', () {
    testWidgets('MATCH renders collapsed, expands on tap to show model+level',
        (tester) async {
      final identity = _identity({
        'decision': 'MATCH',
        'identityLevel': 'EXACT_MODEL',
        'model': {
          'modelId': 'life-fitness-9nph-9-15',
          'catalogVersion': 'cv-2026-09-01',
          'textSupportStatus': 'VERIFIED',
        },
      });
      await tester.pumpWidget(_harness(EquipmentIdentityBadge(identity: identity)));

      expect(find.byKey(const Key('equipment-identity-badge')), findsOneWidget);
      expect(find.textContaining('life-fitness-9nph-9-15'), findsNothing);

      await tester.tap(find.byKey(const Key('equipment-identity-badge')));
      await tester.pumpAndSettle();

      expect(find.textContaining('life-fitness-9nph-9-15'), findsOneWidget);
      expect(find.textContaining('EXACT_MODEL'), findsOneWidget);
    });

    for (final level in const ['TYPE_ONLY', 'BRAND_AND_TYPE', 'PRODUCT_LINE']) {
      testWidgets('MATCH expands to show identityLevel $level opaquely', (tester) async {
        final identity = _identity({
          'decision': 'MATCH',
          'identityLevel': level,
          'model': {
            'modelId': 'm-1',
            'catalogVersion': 'cv-1',
            'textSupportStatus': 'VERIFIED',
          },
        });
        await tester.pumpWidget(_harness(EquipmentIdentityBadge(identity: identity)));
        await tester.tap(find.byKey(const Key('equipment-identity-badge')));
        await tester.pumpAndSettle();

        expect(find.textContaining(level), findsOneWidget);
      });
    }

    testWidgets('NOT_SUPPORTED with shadowCandidate expands to an experimental caption',
        (tester) async {
      final identity = _identity({
        'decision': 'NOT_SUPPORTED',
        'shadowCandidate': {
          'modelId': 'precor-amt-885',
          'catalogVersion': 'cv-2026-09-01',
          'textSupportStatus': 'EXPERIMENTAL',
        },
      });
      await tester.pumpWidget(_harness(EquipmentIdentityBadge(identity: identity)));

      expect(find.byKey(const Key('equipment-identity-badge')), findsOneWidget);

      await tester.tap(find.byKey(const Key('equipment-identity-badge')));
      await tester.pumpAndSettle();

      expect(find.textContaining('precor-amt-885'), findsOneWidget);
      // Never presented as a confirmed match -- see the widget's own doc
      // comment on ShadowCandidateSchema parity.
      expect(find.textContaining('not a confirmed match'), findsOneWidget);
    });

    testWidgets(
        'NOT_SUPPORTED with no shadowCandidate renders nothing (OP-01, GPT-PM '
        'pre-commit finding: this is the server\'s genuine zero-evidence answer)',
        (tester) async {
      final identity = _identity({'decision': 'NOT_SUPPORTED'});
      await tester.pumpWidget(_harness(EquipmentIdentityBadge(identity: identity)));
      // A plain NOT_SUPPORTED with no shadowCandidate is the server's own
      // no-candidate-resolved answer (exact_resolution_policy.ts's
      // NOT_ELIGIBLE -> orchestrator's NOT_SUPPORTED). OP-01 requires an
      // ordinary zero-evidence scan to render identically to enrichment
      // being off entirely -- a visible "Server check" pill here would be
      // exactly the visible difference OP-01 forbids.
      expect(find.byKey(const Key('equipment-identity-badge')), findsNothing);
    });
  });

  group('EquipmentIdentityBadge -- accessibility semantics (this gate)', () {
    testWidgets('header announces button role and collapsed/expanded state',
        (tester) async {
      final handle = tester.ensureSemantics();
      final identity = _identity({
        'decision': 'MATCH',
        'identityLevel': 'EXACT_MODEL',
        'model': {
          'modelId': 'life-fitness-9nph-9-15',
          'catalogVersion': 'cv-2026-09-01',
          'textSupportStatus': 'VERIFIED',
        },
      });
      await tester.pumpWidget(_harness(EquipmentIdentityBadge(identity: identity)));

      final headerFinder =
          find.byKey(const Key('equipment-identity-badge-header-semantics'));
      expect(
        tester.getSemantics(headerFinder),
        matchesSemantics(
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          hasExpandedState: true,
          isExpanded: false,
          label: 'Server check',
        ),
      );

      await tester.tap(find.byKey(const Key('equipment-identity-badge')));
      await tester.pumpAndSettle();

      // The header is the only semantics boundary anywhere in the pill, so
      // the (sibling, not descendant) expanded detail lines merge into this
      // same node rather than being excluded -- a screen reader gets one
      // focus stop that reads the label, role, expanded state AND the
      // detail content together, not a separate/hidden announcement.
      expect(
        tester.getSemantics(headerFinder),
        matchesSemantics(
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          hasExpandedState: true,
          isExpanded: true,
          label: 'Server check\n'
              'Server-confirmed model: life-fitness-9nph-9-15 (cv-2026-09-01)\n'
              'Identity level: EXACT_MODEL',
        ),
      );

      handle.dispose();
    });
  });

  group('EquipmentIdentityNeedMoreViewPrompt', () {
    testWidgets('renders only for NEED_MORE_VIEW', (tester) async {
      final needMoreView = _identity({'decision': 'NEED_MORE_VIEW'});
      await tester.pumpWidget(
        _harness(EquipmentIdentityNeedMoreViewPrompt(identity: needMoreView)),
      );
      expect(find.byKey(const Key('equipment-identity-need-more-view')), findsOneWidget);
    });

    testWidgets('renders nothing for null or any other decision', (tester) async {
      await tester.pumpWidget(
        _harness(const EquipmentIdentityNeedMoreViewPrompt(identity: null)),
      );
      expect(find.byKey(const Key('equipment-identity-need-more-view')), findsNothing);

      final match = _identity({
        'decision': 'MATCH',
        'model': {
          'modelId': 'x',
          'catalogVersion': 'cv',
          'textSupportStatus': 'VERIFIED',
        },
      });
      await tester.pumpWidget(_harness(EquipmentIdentityNeedMoreViewPrompt(identity: match)));
      expect(find.byKey(const Key('equipment-identity-need-more-view')), findsNothing);
    });
  });
}
