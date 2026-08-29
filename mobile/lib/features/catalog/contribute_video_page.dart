import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../shared/widgets/glass.dart';
import '../../shared/widgets/hud/hud_surface.dart';
import '../auth/state/auth_providers.dart';
import 'state/catalog_providers.dart';
import '../../shared/widgets/app_buttons.dart';

/// Page where any user can submit a video URL for an exercise. The
/// moderation queue (`/admin/catalog`) approves or rejects it.
class ContributeVideoPage extends ConsumerStatefulWidget {
  const ContributeVideoPage({super.key});

  @override
  ConsumerState<ContributeVideoPage> createState() =>
      _ContributeVideoPageState();
}

class _ContributeVideoPageState extends ConsumerState<ContributeVideoPage> {
  final _exerciseCtl = TextEditingController();
  final _urlCtl = TextEditingController();
  final _notesCtl = TextEditingController();
  bool _submitting = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _exerciseCtl.dispose();
    _urlCtl.dispose();
    _notesCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final user = ref.read(authUserProvider).valueOrNull;
    if (user == null) {
      setState(() => _error = l10n.catalogSignInToContributeAVideo);
      return;
    }
    final url = _urlCtl.text.trim();
    final ex = _exerciseCtl.text.trim();
    if (url.isEmpty || ex.isEmpty) {
      setState(() => _error = l10n.catalogExerciseIdAndUrlAreRequired);
      return;
    }
    if (!url.startsWith('https://')) {
      setState(() => _error = l10n.catalogUrlMustUseHttps);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _success = null;
    });
    try {
      await ref
          .read(communityVideoRepositoryProvider)
          .submit(
            exerciseId: ex,
            url: url,
            contributorUid: user.uid,
            contributorDisplay: user.displayName,
            notes: _notesCtl.text.trim().isEmpty
                ? null
                : _notesCtl.text.trim(),
          );
      setState(() {
        _submitting = false;
        _success = l10n.catalogSubmittedModeratorsUsuallyApprove;
        _exerciseCtl.clear();
        _urlCtl.clear();
        _notesCtl.clear();
      });
    } catch (e) {
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return FrostedScaffold(
      appBar: GlassAppBar(title: AppLocalizations.of(context).catalogContributeAVideo),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          HudPanel(
            child: Text(
              AppLocalizations.of(context).catalogHelpUsGrowTheCatalogPaste,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          HudPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _exerciseCtl,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context).catalogExerciseIdEGSquatDeadlift,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _urlCtl,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context).catalogVideoUrlHttps,
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesCtl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context).catalogNotesForModeratorOptional,
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            // INTENTIONAL_LEGACY_EXCEPTION: needs `tint`, which HudPanel has
            // no equivalent for. See core/plans/HUD_MIGRATION_CENSUS_2026-08-29.md
            // (status-tint consolidation candidate).
            GlassCard(
              tint: theme.colorScheme.error,
              child: Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          ],
          if (_success != null) ...[
            const SizedBox(height: 12),
            HudPanel(
              child: Text(_success!),
            ),
          ],
          const SizedBox(height: 16),
          AppPrimaryButton(
            // Was a bare spinner, i.e. `colorScheme.primary` on a background
            // painted `colorScheme.primary` - invisible while submitting.
            loading: _submitting,
            onPressed: _submit,
            icon: Icons.upload_outlined,
            label: _submitting ? l10n.catalogSubmitting : l10n.catalogSubmitForReview,
          ),
        ],
      ),
    );
  }
}
