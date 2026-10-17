# S03 lane L10: shortcuts, Back control, scroll helpers

Date: 2026-10-17. Kind: production code (UI input), story S03-17.

## What changed
- mobile/lib/shared/widgets/app_shortcuts.dart (new): `AppShortcuts`, mode switcher opener provider.
- mobile/lib/shared/widgets/shell_back_button.dart (new): `ShellBackButton` (macOS only unless forced).
- mobile/lib/shared/widgets/shell_scroll.dart (new): `ShellScrollbar`, `shouldShowScrollbar`, `scrollToTop`.

## Why
Story S03-17 (design 2.6, contract 10.8, 10.9): keyboard and pointer use on Apple desktop and tablets without changing touch behaviour.

## Affected contracts and paths
Nothing uses these files yet; main.dart gets the AppShortcuts splice in the next commit.

## Verification state
Nothing was run. Tests (DT-17-x) are written and run by the test agents; until then NOT_RUN.
