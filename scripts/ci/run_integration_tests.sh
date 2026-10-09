#!/usr/bin/env bash
# Runs every mobile/integration_test/*_test.dart, one `flutter test` process per
# file, and fails only AFTER all of them have run. Run with mobile/ as the CWD.
#
# Lives in a file rather than inline in flutter.yml (VER-04, 2026-10-08):
# reactivecircus/android-emulator-runner executes each line of `script:` as its
# own `sh -c`, so a multi-line `for ... done` loop reached sh as the fragment
# `for f in ...; do` and died with "Syntax error: end of file unexpected
# (expecting "done")" before any test ran. See the comments in flutter.yml for
# why the files run one at a time and why failures are aggregated.
set -u
failed=0
for f in integration_test/*_test.dart; do
  echo "=== $f ==="
  flutter test "$f" --reporter=expanded || failed=1
done
exit $failed
