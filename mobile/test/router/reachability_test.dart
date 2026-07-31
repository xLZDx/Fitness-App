import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Can the user actually get there.
///
/// A route that is declared, a page that is finished and translated, and no
/// button anywhere that opens it — that is a feature which exists only in the
/// source. Nothing fails, no test goes red, and the work is simply invisible.
///
/// The 2026-08-01 audit found three: `/contribute` (a submission form nobody
/// could open), `/moderate` (a queue the only moderator could not reach), and
/// `/team/:teamId`. The first two are linked now. The third is left alone on
/// purpose and named below, because giving it an entry point means building a
/// screen that lists teams, and that is a feature, not a link.
void main() {
  final router =
      File('lib/core/router/app_router.dart').readAsStringSync();
  final sources = <String, String>{
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart')) f.path: f.readAsStringSync(),
  }..remove('lib${Platform.pathSeparator}core${Platform.pathSeparator}'
      'router${Platform.pathSeparator}app_router.dart');

  test('every route has something that navigates to it', () {
    // Reached by the shell, by a redirect, or by being where the app starts.
    const entryPoints = {'/splash', '/login', '/home'};

    // Declared, finished, and deliberately not linked. Each needs a reason,
    // because "we meant to" is how the other three got here.
    const knownUnreachable = {
      // A per-trainer feed that takes a team id. Nothing in the app produces
      // one: `/community` opens the social feed, and no screen lists teams.
      // Linking it means designing that screen first.
      '/team/:teamId',
    };

    final paths = RegExp(r"path:\s*'([^']+)'")
        .allMatches(router)
        .map((m) => m.group(1)!)
        .toSet();
    expect(paths.length, greaterThan(15), reason: 'router parse looks wrong');

    final unreachable = <String>[];
    for (final path in paths) {
      if (entryPoints.contains(path) || knownUnreachable.contains(path)) {
        continue;
      }
      // A parameterised route is navigated to by its stem: `/workout/$id`.
      final stem = path.split('/:').first;
      final linked = RegExp("['\"]${RegExp.escape(stem)}(/|['\"])");
      if (!sources.values.any(linked.hasMatch)) unreachable.add(path);
    }
    unreachable.sort();

    expect(unreachable, isEmpty,
        reason: 'routes nothing in the app opens: $unreachable');
  });

  test('the known-unreachable list has not gone stale', () {
    // If someone links the team feed, this fails and the exemption above gets
    // deleted rather than quietly outliving its reason.
    final stillUnlinked = <String>[];
    for (final path in ['/team/:teamId']) {
      final stem = path.split('/:').first;
      final linked = RegExp("['\"]${RegExp.escape(stem)}(/|['\"])");
      if (!sources.values.any(linked.hasMatch)) stillUnlinked.add(path);
    }
    expect(stillUnlinked, ['/team/:teamId'],
        reason: 'the team feed is reachable now — remove it from the '
            'knownUnreachable list in the test above');
  });
}
