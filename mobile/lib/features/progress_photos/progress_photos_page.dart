import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/demo_data_banner.dart';
import '../../shared/widgets/glass.dart' show FrostedScaffold, GlassAppBar;
import '../../shared/widgets/hud/hud_surface.dart';
import '../auth/state/auth_providers.dart';
import '../subscription/data/subscription_models.dart';
import '../subscription/state/subscription_providers.dart';
import 'data/photo_consent.dart';
import 'data/photo_timeline.dart';
import 'data/progress_photo.dart';
import 'state/progress_photos_providers.dart';
import 'widgets/photo_bitmap.dart';
import 'widgets/photo_capture_sheet.dart';
import 'widgets/photo_consent_sheet.dart';
import 'widgets/photo_delete_sheet.dart';
import 'widgets/photo_details_sheet.dart';
import 'widgets/photo_review_screen.dart';

/// Progress photos: a month-grouped timeline plus a before/after card.
///
/// The encryption claim on [_PrivacyStrip] is real as of R7 —
/// [LocalProgressPhotosRepository] writes AES-GCM envelopes into the app's
/// private documents directory and nothing here has a network path. It stays
/// gated on [progressPhotosAreDemoProvider] anyway, because that provider is
/// now false only once the disk store has resolved; during that window the
/// mock is bound and a capture really would vanish.
///
/// There is no share button and no export. That is the feature working as
/// scoped, not a gap: the design had an `ExportScreen`, and the first thing it
/// would do is hand a decrypted JPEG to the system share sheet.
class ProgressPhotosPage extends ConsumerWidget {
  const ProgressPhotosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tier = ref.watch(effectiveTierProvider);
    final isPaid = tier != SubscriptionTier.free;
    final photosAsync = ref.watch(progressPhotosProvider);
    final isDemo = ref.watch(progressPhotosAreDemoProvider);

    return FrostedScaffold(
      appBar: GlassAppBar(title: l10n.profileProgressPhotos),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          DemoDataBanner(
            isDemo: isDemo,
            message: l10n.progressphotosDemoNotSaved,
          ),
          if (!isDemo) ...[
            const _PrivacyStrip(),
            const SizedBox(height: 16),
          ],
          if (!isPaid && ref.watch(entitlementResolvedProvider)) ...[
            const _UpgradeCard(),
            const SizedBox(height: 16),
          ],
          photosAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => HudPanel(
              tone: HudPanelTone.error,
              child: Text(l10n.progressphotosCouldNotLoadPhotos(e)),
            ),
            // Keyed so the paging cursor survives. `_Body` sits in a list
            // whose shape changes with the demo banner, the upgrade card and
            // the capture button, and an unkeyed child in a shifting list is
            // matched by position: the day both ends of the list change in one
            // rebuild, `_visible` would silently reset and the user would find
            // themselves back at the newest thirty.
            data: (photos) => _Body(
              key: const Key('photos.body'),
              photos: photos,
              locked: !isPaid,
            ),
          ),
          const SizedBox(height: 16),
          if (isPaid)
            AppPrimaryButton(
              key: const Key('photos.capture'),
              onPressed: () => runPhotoCaptureFlow(context, ref),
              icon: Icons.photo_camera_outlined,
              label: l10n.progressphotosTakeANewPhoto,
            ),
        ],
      ),
    );
  }
}

/// Ask first, then shoot, look, describe, file.
///
/// The order is the design's (`ProgressPhotoModule:3909`) and each step earns
/// its place: the angle is what makes two photos comparable, the review is the
/// only chance to notice a bad frame while it can still be retaken, and the
/// details are what put a weight on the compare card. Before R11f the button
/// did all four at once — it called `capture()` bare, so every shot was filed
/// as `front`, unseen, with no weight.
///
/// **Retake loops, it does not exit.** Answering "retake" reopens the camera
/// rather than dropping the user back on the timeline to press the button
/// again; the first draft returned, which turned one bad frame into three taps
/// to fix.
///
/// Top-level rather than a method on the page: nothing here reads the widget,
/// and a free function is directly callable from a test without pumping a
/// timeline first.
Future<void> runPhotoCaptureFlow(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  // Captured BEFORE the first await. Every step below is an async gap, and
  // reaching for the messenger after one of them is the classic
  // use-BuildContext-across-an-async-gap fault.
  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(progressPhotosControllerProvider.notifier);

  // The consent gate, and it has to be here rather than one step further in.
  // `PhotoCaptureSheet` starts a real camera session and asks the OS for the
  // camera permission in its own `initState`, so a gate placed inside it would
  // be asking after the thing it is asking about had already happened.
  if (!await _ensurePhotoConsent(context, ref)) return;
  if (!context.mounted) return;

  try {
    while (true) {
      // At the TOP of the loop, not before `continue`. A retake comes back
      // here through several async gaps, and checking on the way out of the
      // previous pass says nothing about the state of this one.
      if (!context.mounted) return;
      // The shot is taken INSIDE the sheet, while its camera is demonstrably
      // open — see the note on PhotoCaptureSheet for why that placement is
      // load-bearing rather than tidy.
      final shot = await PhotoCaptureSheet.show(context);
      if (shot == null) return; // backed out of the camera
      if (!context.mounted) return;

      final choice = await PhotoReviewScreen.show(
        context,
        bytes: shot.bytes,
        angle: shot.angle,
      );
      // Dismissed the review outright: the shot is discarded, and nothing was
      // written, so there is nothing to undo.
      if (choice == null) return;
      if (choice == PhotoReviewChoice.retake) continue;
      if (!context.mounted) return;

      final details = await PhotoDetailsSheet.show(context);
      if (details == null) return; // changed their mind before it was filed

      await controller.save(
        shot.bytes,
        angle: shot.angle,
        weightKg: details.weightKg,
        note: details.note,
      );
      return;
    }
  } catch (e) {
    // The write failing used to be recorded in a provider nothing rendered, so
    // a photo the user posed for could vanish without a word.
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.photosSaveFailed(e))),
    );
  }
}

/// True when the camera may be opened, asking if nobody has been asked yet.
///
/// Returns immediately for an account that has already agreed. The gate is a
/// one-time consent, not a disclosure to re-read on every visit — what the
/// user re-reads on every visit is `_PrivacyStrip` at the top of this page,
/// which this gate deliberately does not replace. Replacing it was the reason
/// R11f declined to build the prototype's version at all.
Future<bool> _ensurePhotoConsent(BuildContext context, WidgetRef ref) async {
  // The store is resolved BEFORE the sheet opens, and the answer is written
  // through the object rather than through `ref`. Same reason `controller` is
  // captured at the top of the flow above: this `ref` belongs to the page, and
  // reading a provider through it after the sheet has been on screen is a read
  // across an async gap that throws if the page went away underneath.
  //
  // The account the store belongs to is compared against the account signed in
  // after the sheet closes, and that comparison is the point of this paragraph.
  //
  // An earlier version of this comment argued the window was safe to leave
  // open: if the account changes while the sheet is up — a background
  // sign-out, since a modal cannot be signed out of from inside — the answer
  // would be filed against whoever was signed in when the question appeared,
  // and the new account, having no flag, would simply be asked themselves.
  // That reasoning covered the half where nobody INHERITS an answer, and
  // missed the half where somebody is GIVEN one: B taps "I agree" and A's key
  // is what gets written, so A now carries an answer A was never shown. The
  // gate exists to make that sentence impossible, and "the direction is safe"
  // does not survive it.
  //
  // Worse, the caller would then walk on into the camera holding a controller
  // resolved for A while B is signed in. Aborting here closes both: the flag
  // is not written and `runPhotoCaptureFlow` returns without opening anything.
  // B loses one tap and is asked again on their own account, which is the
  // cost this trade was always supposed to be paying.
  PhotoConsentStore? store;
  var already = false;
  try {
    final resolved = await ref.read(photoConsentStoreProvider.future);
    store = resolved;
    already = await resolved.isAccepted();
  } catch (e) {
    // Preferences that cannot be read must not open the camera on their own.
    // Asking again costs one tap; the other direction costs a capture nobody
    // agreed to, which no apology afterwards undoes.
    //
    // Caught wide, on purpose, and NOT narrowed to `on Exception`: the review
    // suggested that and the suite proved it wrong. A store whose read throws
    // `StateError` is an `Error`, not an `Exception`, and letting it past here
    // would abort the whole flow — no camera AND no question, which is worse
    // for the user than being asked twice. `photo_consent_test.dart`'s
    // `_BrokenConsentStore` pins exactly that case.
    //
    // The runtime type is logged so a genuine defect is still distinguishable
    // from unreadable preferences, which was the half of that review point
    // that did hold.
    debugPrint('progress photos: consent unreadable — ${e.runtimeType}: $e');
  }
  // Compared BEFORE trusting `already`, not after — Codex caught the gap the
  // post-sheet check above does not close. `store` was resolved across TWO
  // awaits (`photoConsentStoreProvider.future`, then `isAccepted()`), and the
  // account can change during either one. If it has, the answer — yes or no —
  // belongs to whoever was signed in when the awaits started, not to whoever
  // is signed in now, and returning `true` here would let B into the camera
  // on A's consent while `controller` still points at A's repository.
  //
  // No sheet has been shown yet in this path, so there is nothing to discard
  // but the stale resolution itself: abort, and a fresh call — the next time
  // this function runs — resolves a store for whoever is actually signed in.
  if (context.mounted &&
      store != null &&
      ref.read(authUserProvider).valueOrNull?.uid != store.uid) {
    debugPrint(
      'progress photos: account changed while consent was being resolved — '
      'asking again',
    );
    return false;
  }
  if (already) return true;
  if (!context.mounted) return false;

  if (!await PhotoConsentSheet.show(context)) return false;
  if (!context.mounted) return false;
  // Read AFTER the `context.mounted` guard, so this is a live ref, and read
  // synchronously off the already-resolved `AsyncValue` rather than awaited —
  // awaiting the stream here would reopen the very gap being closed. It cannot
  // be loading at this point: `store` above only exists because
  // `photoConsentStoreProvider` already awaited this same provider, and a
  // resolved `StreamProvider` keeps its last value rather than returning to
  // loading.
  //
  // Compared against `store.uid` and NOT against a second auth read taken
  // before the sheet — see `PhotoConsentStore.uid` for why that ordering
  // matters. `store` being null means the provider itself failed, in which
  // case there is no answer to misfile and nothing to compare; that path keeps
  // its old behaviour of letting the person who just agreed through.
  final uidNow = ref.read(authUserProvider).valueOrNull?.uid;
  if (store != null && uidNow != store.uid) {
    debugPrint(
      'progress photos: account changed while the consent sheet was open — '
      'answer discarded',
    );
    return false;
  }
  try {
    await store?.accept();
  } catch (e) {
    // The store marks itself accepted in memory before it writes, so this
    // session proceeds regardless; a lost write costs one more tap next
    // launch. Logged, because "the gate asked me twice" is otherwise an
    // unexplainable symptom.
    debugPrint('progress photos: consent not persisted — ${e.runtimeType}: $e');
  }
  return true;
}

/// Long-press a tile, confirm, gone. The only way to remove a photo — see
/// `PhotoConsentSheet`'s doc comment for why the consent copy can promise
/// this again as of H6.
///
/// Top-level for the same reason as [runPhotoCaptureFlow]: directly callable
/// from a test without pumping a whole grid, and nothing here reads the
/// widget it was called from.
Future<void> runPhotoDeleteFlow(
  BuildContext context,
  WidgetRef ref,
  ProgressPhoto photo,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);

  if (!await PhotoDeleteSheet.show(context)) return;
  if (!context.mounted) return;

  await ref.read(progressPhotosControllerProvider.notifier).delete(photo.id);
  final state = ref.read(progressPhotosControllerProvider);
  if (state.hasError) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.progressphotosDeleteFailed(state.error!))),
    );
  }
}

/// How many photos the timeline shows before the user asks for more.
///
/// Ten rows of three. Enough that the first screen and a scroll or two are
/// already there, small enough that opening the page is a bounded amount of
/// decryption no matter how long the history is.
const int kPhotoPageSize = 30;

class _Body extends ConsumerStatefulWidget {
  const _Body({super.key, required this.photos, required this.locked});

  final List<ProgressPhoto> photos;
  final bool locked;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  int _visible = kPhotoPageSize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final photos = widget.photos;
    if (photos.isEmpty) {
      return HudPanel(
        child: Text(
          l10n.progressphotosNoPhotosYet,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    // The compare pair is chosen from the WHOLE history, not from the visible
    // page. Its whole point is the widest span the user has, and that lives at
    // the oldest end — the end paging hides. It is two photos.
    final pair = defaultComparePair(photos);
    final all = groupByMonth(photos);
    final total = totalPhotos(all);
    final months = newestMonths(all, _visible);
    final remaining = total - _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CompareCard(pair: pair),
        const SizedBox(height: 20),
        for (final m in months) ...[
          _MonthHeading(month: m),
          const SizedBox(height: 8),
          _PhotoGrid(photos: m.photos),
          const SizedBox(height: 18),
        ],
        if (remaining > 0)
          AppSecondaryButton(
            key: const Key('photos.showMore'),
            onPressed: () => setState(() => _visible += kPhotoPageSize),
            label: l10n.progressphotosShowMore(remaining),
          ),
      ],
    );
  }
}

/// Before/after. Shows the widest same-angle span, or says why it can't.
class _CompareCard extends StatelessWidget {
  const _CompareCard({required this.pair});

  final ComparePair? pair;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = pair;
    if (p == null) {
      return HudPanel(
        key: const Key('photos.compare.empty'),
        child: Text(
          l10n.progressphotosNeedTwoSameAngle,
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    return HudPanel(
      key: const Key('photos.compare'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.progressphotosCompare,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                l10n.progressphotosCompareSpan(p.daySpan),
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CompareSide(
                  label: l10n.progressphotosBefore,
                  photo: p.before,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CompareSide(
                  label: l10n.progressphotosAfter,
                  photo: p.after,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompareSide extends StatelessWidget {
  const _CompareSide({required this.label, required this.photo});

  final String label;
  final ProgressPhoto photo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 0.75,
          child: _PhotoImage(photo: photo),
        ),
        const SizedBox(height: 4),
        Text(
          _fullDate(context, photo.takenAt),
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _MonthHeading extends StatelessWidget {
  const _MonthHeading({required this.month});

  final PhotoMonth month;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          DateFormat.yMMMM(l10n.localeName).format(month.month),
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const Spacer(),
        Text(
          l10n.progressphotosMonthCount(month.count),
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({required this.photos});

  final List<ProgressPhoto> photos;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.75,
      ),
      itemCount: photos.length,
      itemBuilder: (context, i) => _PhotoTile(photo: photos[i]),
    );
  }
}

class _PhotoTile extends ConsumerWidget {
  const _PhotoTile({required this.photo});

  final ProgressPhoto photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      key: const Key('photos.tile.longPress'),
      onLongPress: () => runPhotoDeleteFlow(context, ref, photo),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _PhotoImage(photo: photo),
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Text(
                DateFormat.MMMd(l10n.localeName).format(photo.takenAt),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppSemanticColors.onGradientInk,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Decrypts and renders one photo.
///
/// The two failure modes are told apart on purpose. A missing blob is a bug or
/// a half-finished delete; a fingerprint mismatch means the key is gone, which
/// happens after a reinstall and is not recoverable. Collapsing both into one
/// "couldn't load" would leave the user retrying something that can never
/// work.
class _PhotoImage extends ConsumerWidget {
  const _PhotoImage({required this.photo});

  final ProgressPhoto photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bytes = ref.watch(photoBytesProvider(photo));
    return bytes.when(
      loading: () => Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.all(6),
        child: Center(
          child: Text(
            e.toString().contains('no longer has')
                ? l10n.progressphotosKeyMissing
                : l10n.progressphotosBlobMissing,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall,
          ),
        ),
      ),
      data: (Uint8List data) => PhotoBitmap(bytes: data),
    );
  }
}

class _PrivacyStrip extends StatelessWidget {
  const _PrivacyStrip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HudPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLocalizations.of(context).progressphotosStaysOnPhone,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return HudPanel(
      padding: const EdgeInsets.all(18),
      onTap: () => GoRouter.of(context).push('/subscription'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.progressphotosTrendPhotosAreASupporterBenefit,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.progressphotosCompareSideBySideOverWeeks,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

String _fullDate(BuildContext context, DateTime t) =>
    DateFormat.yMMMd(AppLocalizations.of(context).localeName).format(t);
