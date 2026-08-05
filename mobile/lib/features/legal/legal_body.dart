import 'package:flutter/material.dart';

/// Renders the legal documents' markup subset.
///
/// The text itself is generated into the `.arb` files from
/// `scripts/legal/legal_text.py`, which is also the source for
/// `public/privacy.html` and `public/terms.html` — the URLs Google Play
/// requires as store-listing fields. Three hand-maintained copies of a legal
/// document drift, and a legal document that drifts stops being knowable: the
/// version a user agreed to is no longer identifiable. Same reasoning
/// `Injury.toJson` and `kFunctionsRegion` are already single sources here.
///
/// The markup is four constructs, and this renderer is the twin of `_html_of`
/// in `scripts/legal/build_legal.py`. Both must move together:
///
///   `## ` block prefix -> heading
///   `- `  line prefix  -> bullet
///   `**x**` inline     -> bold
///   blank line         -> paragraph break
///
/// A Markdown package would be the obvious alternative and was rejected: it
/// buys nothing over 40 lines here, and it is a dependency that has to stay
/// alive for as long as the two static documents do.
class LegalBody extends StatelessWidget {
  const LegalBody(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Explicit fallbacks rather than `?.copyWith`: a null text theme would
    // otherwise silently render legal text at default styling, and this is the
    // one screen where "it looked slightly wrong" is not the failure mode —
    // unreadable terms are terms nobody agreed to.
    final body = theme.textTheme.bodyMedium ?? const TextStyle();
    final heading = (theme.textTheme.titleSmall ?? const TextStyle()).copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    );

    final children = <Widget>[];
    for (final block in text.trim().split('\n\n')) {
      final trimmed = block.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('## ')) {
        children.add(Padding(
          padding: EdgeInsets.only(top: children.isEmpty ? 0 : 22, bottom: 8),
          child: Text(trimmed.substring(3).trim(), style: heading),
        ));
      } else if (trimmed.startsWith('- ')) {
        for (final line in trimmed.split('\n')) {
          final item = line.trim();
          if (!item.startsWith('- ')) continue;
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: body),
                Expanded(
                  child: Text.rich(_inline(item.substring(2).trim(), body)),
                ),
              ],
            ),
          ));
        }
      } else {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text.rich(_inline(trimmed, body)),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  /// Splits on `**` and bolds every odd segment.
  ///
  /// An unclosed `**` therefore bolds the tail rather than throwing — the
  /// generator would have to emit malformed markup for that to happen, and
  /// rendering the paragraph slightly wrong beats rendering nothing on the
  /// screen a store listing points at.
  static TextSpan _inline(String source, TextStyle base) {
    final parts = source.split('**');
    return TextSpan(
      children: [
        for (var i = 0; i < parts.length; i++)
          if (parts[i].isNotEmpty)
            TextSpan(
              text: parts[i],
              style: i.isOdd
                  ? base.copyWith(fontWeight: FontWeight.w700)
                  : base,
            ),
      ],
    );
  }
}
