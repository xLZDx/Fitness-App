# C25 part 3: data inventory rows

## What changed
- `core/DATA_INVENTORY_2026-08-11.csv`: 15 rows (gate `C25`) for the seven new per-user Firestore paths,
  the two EXEMPT paths (`nutrition_cache`, `body_scan_purge_state`), the private bucket, per-uid prefs
  and the device `scans/` and `meals/` directories.
- `core/DATA_INVENTORY_2026-08-11.md`: section "Body scan and nutrition coach additions (C25)" with the
  same table plus the D-67 logging note.

## Why
Design 6.2 / 20.4: the inventory must list every store keyed to a user so deletion and export match.

## Verification state
Not run (the data-lifecycle scripts are not to be run in this sprint).
