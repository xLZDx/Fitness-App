# GYM DIGITAL TWIN — Product Scope and Requirements

Date: 2026-10-19. Status: proposed implementation contract, not release approval.

## 1. Problem and outcome

Users know their planned exercise but often do not know which physical piece of equipment to use or where it is. The feature creates an actionable indoor map for an actual venue and allows the existing Fitness App workout to indicate the next compatible physical machine and its location.

North-star outcome: a user can select a real gym map, open a planned or currently visible eligible workout exercise, find a verified equipment instance, and navigate using an honest 2D floor plan — even when camera/AR is unavailable.

### Primary personas

- Gym member: reuses a venue map, finds the next machine without searching manually.
- First-time gym visitor: chooses gym, floor and an unambiguous start point, follows accessible walking corridors.
- Volunteer mapper: builds a personal draft map by import/manual editing and optionally scan-assisted placement.
- Venue administrator/authorized moderator (later phase): owns/publishes/verifies shared map revisions and location metadata.
- Workout user with physical constraints: must never be shown a contraindicated alternative solely because it is closer.

## 2. Product boundaries

**IN for first usable release (GYM-01):**
- Select or create personal draft gym with stable internal location identifier.
- Import a floor plan image and/or draw a basic outline; one floor for the MVP.
- Add/move/rotate physical equipment instances, including duplicates of the same catalog equipment type.
- Draw/confirm walkable connectors, barriers, approach points and entry/start landmarks.
- 2D mobile map, pan/zoom, target highlight, list/search, location/floor labels and confirmed vs tentative status.
- Manual origin ("I am at the entrance" / "I am at machine X"); route displayed only along validated traversable paths.
- Read-only lookup of the equipment required by an existing eligible workout exercise, with a clear no-equipment / unknown-equipment state.
- Offline read/use of downloaded private maps and deterministic navigation; local edits sync when safe.

**IN as additive phases (GYM-02+):**
- Guided still-frame capture, selecting good shots, existing single-machine recognition, match to canonical catalog.
- Multi-object detection after measured PoC (do not overload existing center-frame callable).
- Live/guided voice instructions, through shared existing UI action semantics, not new workout logging.
- AR-assisted placement, spatial observations, repeated landmark localization and offline reconstruction research.
- Venue-verified shared maps with controlled moderation/versioning.
- 3D view/AR overlay only when geometry and localization have been measured reliable.

**OUT of MVP:**
- Automatic accurate 3D digital twin; always-on camera or continuous livestream to the cloud.
- Indoor GPS claim or unverified real-time blue-dot positioning.
- Automatic public map publishing from user camera scans.
- Occupancy estimates from random photographs or predictions of machine release times.
- General-purpose movement instructions crossing unknown obstacles, stairs or restricted areas.
- Automatic reordering/replacing workout exercises outside existing eligibility/injury constraints.
- Dedicated workout-session/runtime/journal/store; duplicate activity tracking; involuntary profile migration.
- Surveillance, face identification, crowd analytics or storing raw bystander footage.
- Guarantee of uniform operation across phones without AR depth/SLAM support.

## 3. Explicit experience modes

### Mode A — Use Map (daily mode; no camera permission)
Select gym and floor, choose known origin or waypoint, select eligible exercise/equipment, display highlighted instance and simple verified route. Enable a readable accessible list as alternative to a visual map. Clearly flag outdated/unverified sections.

### Mode B — Quick Scan (low-friction contributor mode)
User deliberately opens camera, centers ONE machine, captures a selected still, confirms catalog match. The UI suggests placement on a pre-existing map or asks the user to tap a location; it never assigns global coordinates based on a classifier output. No automatic publishing. Optional local blurring/redaction and deletion of source images.

### Mode C — Guided Spatial Scan (R&D; optional)
User follows an instruction to walk slowly, pause at machines and change viewing angle, capture calibrated photos/poses/depth (when available), mark stable points, inspect proposed geometry, and correct uncertain matches. Camera/device capabilities and privacy gate must be checked upfront. Fallback to Mode B or A without loss of existing map.

### Mode D — Import Plan
User or authorized venue staff uploads licensed/authorized image/PDF/plan, calibrates scale with two known points, outlines obstacles and edits equipment inventory. Scanned proposals are layered as non-authoritative candidates. A floor plan alone does not create navigable paths without validation.

## 4. Essential user journeys

J1 — Existing plan, verified map:
1. Open the existing workout in its existing UI.
2. Select the next eligible exercise (or view its existing next step).
3. Tap "Find equipment" or request the corresponding voice navigation help when enabled.
4. Resolve a supported canonical equipment type to 0..N physical instances in the selected gym and floor.
5. Present verified instances and a selected user-confirmed origin.
6. Show only routable destinations; identify target by label, image/description and location.
7. Return to the SAME workout player without saving fake sets or changing session state.

J2 — Private map author:
1. Create a private gym draft with stable internal ID; no collision with free-text gym name.
2. Import image/draw simple boundaries and mark entry.
3. Place machines manually or via Quick Scan with confirmation.
4. Confirm walkway edges and machine approach point(s).
5. Save, reopen and route with camera disabled.

J3 — Map drift or failure:
1. User scans or reopens a map in a different device session.
2. If localization confidence is poor, blue-dot/AR path is removed.
3. Existing 2D map remains readable; user selects a known origin or confirms visual landmark.
4. A proposed update creates a draft revision, never silently mutating published geometry.

J4 — Occupied machine:
1. User marks equipment instance "busy" manually for this moment.
2. App suggests another location of the SAME eligible type, if confirmed and routable.
3. For alternate exercises, call the existing safety/eligibility filter, require user acceptance, preserve planned-program semantics.
4. Do not infer crowds/occupancy from incidental photographs.

## 5. Product requirements (trace IDs)

- PR-01: Single workout source of truth; navigation is an adapter, no writes without existing workout action.
- PR-02: Distinguish canonical equipment type, physical equipment instance, and venue identity.
- PR-03: Every map position has provenance and state: verified, proposed, invalid, stale.
- PR-04: No route from uncertain global device positioning; verified manual origin fallback.
- PR-05: Paths avoid blocked areas and use confirmed approach points; no straight-line shortcuts through obstacles.
- PR-06: Scan uses explicit foreground camera session, clear consent, minimum image retention.
- PR-07: Private drafts remain private; publication requires authorization and moderation.
- PR-08: Offline map viewing and deterministic routes work without cloud AI.
- PR-09: Multiple identical machines receive distinct stable instance IDs.
- PR-10: Existing safety/injury screening stays authoritative for exercise substitutions.
- PR-11: Platform abstraction for Android ARCore and iOS ARKit, graceful capability downgrade.
- PR-12: Site map version and location ID are immutable references in views/routes; edits via new revisions.
- PR-13: Map exports/imports clearly document geometry, scale, units, rights and attribution.
- PR-14: Unavailable and misleading positioning states are explained without fabricated precision.
- PR-15: Mapping is allowed independently of owning an in-progress workout.
- PR-16: Model, dataset and checkpoint licenses are each independently evaluated before shipping.
- PR-17: Scan cost, battery and network use are bounded by user-controlled actions and quota policy.
- PR-18: Localization/recognition suggestions do not bypass human confirmation for publication.

## 6. Success measurements (targets pending baseline)

Define before field study: time to create/edit usable map, percentage of confirmed equipment captured (recall), machine type accuracy, physical-instance dedup precision, distance/position error vs surveyed control points, % routes judged safe/correct, unknown/refusal rate, camera CPU/battery/thermal metrics, upload MB and AI cost per scan, rate of manual corrections and percentage using offline fallback.

Thresholds: NOT YET APPROVED. Establish per-device/per-venue acceptance bounds using frozen ground truth; do not invent sub-meter, 100% recognition, latency or conversion guarantees.

## 7. Explicit product decisions

- Approved product direction: hybrid map + guided scan; staged delivery with useful 2D first.
- Preferred user outcome: "which actual machine should I approach, and where is it?"
- Assumed MVP floor count: one; multi-floor is scheduled for later, data model supports floors immediately.
- Voice and AR are enhancements, not launch blockers.
- Publication, venue/admin identity, privacy retention and commercial OSS reuse require dedicated go/no-go approval.
- No shipping or code modification is authorized by this product-scope document.
