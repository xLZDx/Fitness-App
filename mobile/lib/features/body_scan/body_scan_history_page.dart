/// The `/body-scan/history` route: every scan with the baseline marker, trend
/// label, provisional label and compare entry points (C16).
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/scan_history_actions.dart';
import 'widgets/scan_history_list.dart';

class BodyScanHistoryPage extends ConsumerWidget {
  const BodyScanHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final rows = ref.watch(scanHistoryRowsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.bodyScanHistoryTitle)),
      body: SafeArea(child: ScanHistoryList(rows: rows)),
    );
  }
}
