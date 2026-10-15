/// The `/body-scan/privacy` route: retention, consent and deletion controls
/// (C16).
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'widgets/retention_settings_view.dart';

class BodyScanPrivacyPage extends StatelessWidget {
  const BodyScanPrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.bodyScanPrivacyTitle)),
      body: const SafeArea(child: RetentionSettingsView()),
    );
  }
}
