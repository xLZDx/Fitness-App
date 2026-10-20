/// What the user sees instead of a scan screen when [ScanAccess] is not
/// `allowed`, plus the one-time consent step shared with the entry card.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/state/auth_providers.dart';
import '../../state/progress_photos_providers.dart';
import '../../widgets/photo_consent_sheet.dart';
import '../scan_access.dart';
import '../scan_reminder.dart';
import '../scan_repository.dart';

/// Neutral message for a state in which the scan cannot be opened.
String scanAccessMessage(AppLocalizations l10n, ScanAccess access) =>
    switch (access) {
      ScanAccess.allowed => '',
      ScanAccess.signedOut => l10n.scanEntrySignedOut,
      ScanAccess.underage => l10n.scanEntryUnderage,
      ScanAccess.ageUnknown => l10n.scanEntryAgeUnknown,
      ScanAccess.needsSupporter => l10n.scanEntrySupporter,
      ScanAccess.needsConsent => l10n.scanEntryConsent,
    };

/// Shows the EXISTING photo consent sheet when it has not been accepted yet and
/// records the answer. Returns true when consent is in place afterwards.
Future<bool> runScanConsent(BuildContext context, WidgetRef ref) async {
  try {
    final store = await ref.read(photoConsentStoreProvider.future);
    if (await store.isAccepted()) {
      ref.invalidate(scanConsentAcceptedProvider);
      return true;
    }
    if (!context.mounted) return false;
    if (!await PhotoConsentSheet.show(context)) return false;
    // An answer given while another account became active belongs to nobody.
    if (ref.read(authUserProvider).valueOrNull?.uid != store.uid) return false;
    await store.accept();
    ref.invalidate(scanConsentAcceptedProvider);
    return true;
  } catch (e) {
    debugPrint('scan consent failed: ${e.runtimeType}: $e');
    return false;
  }
}

/// Confirms, then deletes every saved scan of the signed-in account: each
/// scan's photos first (existing progress-photo path), then its sidecar. Stops
/// at the first failure so a retry can finish. Deletion never depends on the
/// scan gate, so it is offered here while the gate refuses.
Future<void> confirmAndDeleteAllScans(
    BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('scan.delete.dialog'),
      title: Text(l10n.scanDeleteTitle),
      content: Text(l10n.scanDeleteBody),
      actions: [
        TextButton(
          key: const Key('scan.delete.cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.scanDeleteCancel),
        ),
        FilledButton(
          key: const Key('scan.delete.confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.scanDeleteConfirm),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final photos = container.read(progressPhotosControllerProvider.notifier);
  final scans = container.read(scanRepositoryProvider);
  final reminder = container.read(scanReminderEnabledProvider.notifier);
  try {
    for (final scan in await scans.list()) {
      for (final shot in scan.shots.values) {
        await photos.delete(shot.photoId);
        final st = container.read(progressPhotosControllerProvider);
        if (st.hasError) throw st.error!;
      }
      await scans.delete(scan.id);
    }
    container.invalidate(scanHistoryProvider);
    await reminder.sync();
    messenger.showSnackBar(SnackBar(content: Text(l10n.scanDeleted)));
  } catch (e) {
    debugPrint('scan: delete all failed: ${e.runtimeType}');
    container.invalidate(scanHistoryProvider);
    messenger.showSnackBar(SnackBar(content: Text(l10n.scanDeleteFailed)));
  }
}

class ScanGateView extends ConsumerWidget {
  const ScanGateView({super.key, required this.access});

  final ScanAccess access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final (actionLabel, action) = switch (access) {
      ScanAccess.ageUnknown => (
          l10n.scanEntryAgeUnknownAction,
          () => GoRouter.of(context).push('/profile'),
        ),
      ScanAccess.needsSupporter => (
          l10n.progressphotosTrendPhotosAreASupporterBenefit,
          () => GoRouter.of(context).push('/subscription'),
        ),
      ScanAccess.needsConsent => (
          l10n.scanEntryConsentAction,
          () => runScanConsent(context, ref),
        ),
      _ => (null, null),
    };
    final hasScans =
        (ref.watch(scanHistoryProvider).valueOrNull ?? const []).isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              access == ScanAccess.underage
                  ? Icons.info_outline
                  : Icons.lock_outline,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              scanAccessMessage(l10n, access),
              key: Key('scan.gate.${access.name}'),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && action != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('scan.gate.action'),
                onPressed: () => action(),
                child: Text(actionLabel),
              ),
            ],
            if (hasScans) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('scan.gate.deleteAll'),
                onPressed: () => confirmAndDeleteAllScans(context, ref),
                child: Text(l10n.scanDeleteAll),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
