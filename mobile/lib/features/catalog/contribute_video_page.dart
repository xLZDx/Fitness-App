import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../shared/widgets/glass.dart';
import '../auth/state/auth_providers.dart';
import 'state/catalog_providers.dart';

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
    setState(() {
      _submitting = true;
      _error = null;
      _success = null;
    });
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      if (user == null) {
        throw StateError('Sign in to contribute a video.');
      }
      final url = _urlCtl.text.trim();
      final ex = _exerciseCtl.text.trim();
      if (url.isEmpty || ex.isEmpty) {
        throw ArgumentError('Exercise id and URL are required.');
      }
      if (!url.startsWith('https://')) {
        throw ArgumentError('URL must use https://.');
      }
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
        _success =
            'Submitted. Moderators usually approve within 48 hours.';
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
    return FrostedScaffold(
      appBar: GlassAppBar(title: AppLocalizations.of(context).catalogContributeAVideo),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          GlassCard(
            child: Text(
              AppLocalizations.of(context).catalogHelpUsGrowTheCatalogPaste,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(
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
            GlassCard(
              tint: theme.colorScheme.error,
              child: Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          ],
          if (_success != null) ...[
            const SizedBox(height: 12),
            GlassCard(
              child: Text(_success!),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_outlined),
            label: Text(_submitting ? 'Submitting…' : 'Submit for review'),
          ),
        ],
      ),
    );
  }
}
