/// The result route `/body-scan/result/:scanId`: loads one scan through the
/// `ScanResultSource` port and renders it with the plan context (D-73, D-74).
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'state/scan_plan_context_provider.dart';
import 'state/scan_result_source.dart';
import 'state/scan_result_view_model.dart';
import 'widgets/result_view.dart';

class BodyScanResultPage extends ConsumerWidget {
  const BodyScanResultPage({super.key, required this.scanId});

  final String scanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final result = ref.watch(scanResultProvider(scanId));
    final plan = ref.watch(scanPlanContextValueProvider);
    final body = result.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(l10n.bodyScanResultLoadError),
        ),
      ),
      data: (data) => data == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.bodyScanResultNotFound),
              ),
            )
          : ResultView(
              model: buildScanResultViewModel(data, plan),
              onSeePlan: () => GoRouter.of(context).push('/nutrition'),
            ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.bodyScanResultTitle)),
      body: SafeArea(child: body),
    );
  }
}
