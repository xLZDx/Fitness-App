# S03 gate fix batch 20

Date: 2026-10-17. Kind: production fix found by the regression test of batch 19.

## What changed
RailRecordSlot lays out the idle Record control invisibly (ExcludeSemantics, ExcludeFocus, IgnorePointer, Visibility with maintainSize) for a foreign-owner session, so the rail does not shift.

## Why
Compact rail destinations moved 16 dp between the idle and foreign-owner states.

## Affected contracts and paths
mobile/lib/shared/widgets/dock_widgets.dart.

## Verification state
Test agents re-run their sets after this commit.
