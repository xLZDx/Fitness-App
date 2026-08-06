import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// G2.1b-iii: `scan-recognise-gallery` is a plain `OutlinedButton` whose
/// child is a bare `Icon` -- the same "icon control, no accessible name"
/// defect class as the twelve `IconButton`s fixed in G2.1b-i, just caught
/// late because the search there only looked at `IconButton`. Not built as
/// a full `ScannerPage` test: that page owns a live camera session and
/// several recognition providers, and mocking a camera pipeline to check one
/// tooltip string would cost far more than the fix it is proving. This
/// isolates the exact shape the real fix applies -- `Tooltip` wrapping a
/// bare-icon button, the same mechanism `IconButton.tooltip` uses
/// internally -- against the real localized string.
void main() {
  testWidgets(
      'an icon-only OutlinedButton gets its name from a wrapping '
      'Tooltip, and the tap still reaches the button underneath', (t) async {
    var tapped = false;
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(builder: (context) {
          return Tooltip(
            message: AppLocalizations.of(context).scannerPickFromGallery,
            child: OutlinedButton(
              onPressed: () => tapped = true,
              child: const Icon(Icons.photo_library_outlined),
            ),
          );
        }),
      ),
    ));

    final l10n = AppLocalizations.of(t.element(find.byType(OutlinedButton)));
    expect(l10n.scannerPickFromGallery, isNotEmpty);
    expect(find.byTooltip(l10n.scannerPickFromGallery), findsOneWidget);

    await t.tap(find.byType(OutlinedButton));
    expect(tapped, isTrue,
        reason: 'the Tooltip wrapper must not intercept the tap');
  });
}
