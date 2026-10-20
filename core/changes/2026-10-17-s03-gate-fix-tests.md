# S03 gate fix regression tests

Date: 2026-10-17. Kind: tests and documentation.

## What changed
- 12 tests for the foreign-session Record guard (rail compact and extended, dock, shortcut, return after the session ends, focus) in dock_strip_test.dart and app_shortcuts_test.dart.
- 9 tests for ordered mode writes (out-of-order completion, failed and thrown writes, account switch, deleted uid, rollback) in mode_state_test.dart.
- Findings files and the final summary updated.

## Why
Direct regression coverage for the two GPT-PM MAJOR findings.

## Affected contracts and paths
None in production.

## Verification state
Run by the test agents: 243 passed on 85f88bb2 (shell), 94 passed and 2 skipped on 20b39611 (modes).
