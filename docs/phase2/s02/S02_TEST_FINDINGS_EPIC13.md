# S02 test findings, epic 13 (remediation G)

## Epic 13a (G1 to G5)

Head under test: fc63ec62 plus the test commits of this epic. Oracles: `S02_REMEDIATION_F_TEST_NOTES.md` heading G,
design section 17 item 23, the promise "nothing of account A reaches account B".

### Defects and shortcomings

| # | What | Layer that missed it | Layer that caught it |
|---|------|----------------------|----------------------|
| 1 | Remediation G production code compiled unchanged (no compile error in aa8f24ec, 4a58317b, 39feb2a1) | n/a | first compiled run |
| 2 | Four older tests expected `bindUid(U)` to succeed after `wipeForUid(U)` of an unbound U (G4 now refuses until `bindUid(null)`) | G authors: the stale-test list named fakes but not these assertions | first whole-directory run `+1260 -4: Some tests failed.` |
| 3 | `_ThrowingSyncRepo` did not implement `onJournalBindingChanged` (a Fake would throw, swallowed by the wiring) | G authors (listed in notes, fixed) | review of notes |
