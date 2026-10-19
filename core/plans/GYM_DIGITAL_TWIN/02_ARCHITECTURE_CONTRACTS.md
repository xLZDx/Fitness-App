# GYM DIGITAL TWIN — System Architecture and Data Contracts

Status: PROPOSED architecture, for review only. Date: 2026-10-19.

## 1. Core separation of concerns

Five independent planes:
1. **Catalog/Workout** (existing and authoritative): equipment type IDs, exercise relationships, injury/contraindication eligibility, scheduled exercise and workout session read/write.
2. **Gym Map Registry**: durable venue/floor/instance identity, map revision, obstacles, edges and points of approach; not an exercise catalog or workout history.
3. **Capture/Vision**: intentional foreground frame acquisition; per-frame observations and candidates; optional detection/segmentation, never authoritative position.
4. **Spatial/Localization**: camera tracking, map alignment, loop closure and landmark anchors with explicit quality estimates; outputs PROPOSED coordinates.
5. **Navigation/Presentation**: deterministic route calculation against a verified walkability graph, starting from explicitly resolved origin, and read-only connection to current workout exercise.

Data flow:

    Existing workout exercise + existing safety filter
            -> equipmentTypeId
            -> GymMapRegistry.findInstances(locationId, typeId, version)
            -> verified candidate instances with approach nodes
    Manual origin OR verified localization -> route planner -> 2D UI / voice wording

    Import plan OR targeted camera OR guided spatial capture
            -> draft observations
            -> reconciliation (dedup + catalog canonicalization)
            -> human/operator review
            -> new map revision
            -> optional authorized publication

No AI model is trusted to emit a final route, overwrite an official map, or commit workout outcomes.

## 2. Domain model (canonical IDs and status)

**GymLocation**
- locationId: immutable, generated globally unique identifier; NOT the free-text onboarding EquipmentAccess.gymId.
- displayName, optional venueChain, branchLabel, address (if authorized), ownerScope (private or venue), ownerPrincipal, status.
- Approval/claims model TBD by GYM-00 security and admin policy.
- Legacy free-text gymId is retained; migration/matching is explicit and reversible, never silent.

**GymFloor**
- locationId, floorId, label, transformToLocation, metricScale/meterPerUnit, boundary geometry.
- Coordinates in a documented floor-local, right-handed 2D Cartesian coordinate system (meters), origin and axis orientation fixed per map revision.
- transformFromScanSession to floor coordinates is separate and confidence-gated.
- Units normalized to meters; prevent mixed unit coordinates on import.

**GymMapVersion**
- mapVersionId, locationId, state (draft, verified, published, superseded, disabled).
- floor snapshots, geometry checksum, createdBy, approvedBy, timestamps, provenance.
- immutable published revision; changes create a new revision with compare/rollback support.
- obstacle polygons, doors/restricted areas, accessible walkable graph node/edge list and map metadata.
- pin routes to version; revalidate or recalc when version changes.

**GymEquipmentInstance**
- instanceId: stable within location; equipmentId: existing catalog TYPE ID.
- floorId, position2D, orientation, bounding footprint, approachNodeIds.
- state: proposed / confirmed / retired / missing; model confidence does not confer confirmed status.
- provenance: manual, import, scan, venue_verified; optional photo reference after consent/redaction.
- N physical instances can share one equipmentId. Never key inventory by equipmentId alone.

**SpatialObservation** (draft evidence only)
- scanSessionId, frameId, captureTimestamp, ephemeral encrypted local media pointer (optional), modelVersion/checkpoint, predicted type candidates and scores, estimated cameraPose, intrinsics, depth units, tracking quality, transform confidence.
- subject/person masks when available; raw third-party frames not synced by default.
- candidates may be unresolved, duplicate or unknown.
- retention/consent class separate from publishable geometry.

**NavigationStart**
- explicit origin kind: entry landmark, confirmed instance approach node, user-picked map point on walkable graph, or VERIFIED device localization.
- source, confidence, mapVersionId and timestamp.
- unknown origin must not silently default to entry.

**RoutePlan**
- routeId ephemeral, locationId, mapVersionId, floorId, originNodeId, destinationInstanceId, destinationApproachNodeId, node/edge path, graph verification version and confidence metadata.
- No fabricated ETA/distances. If scale not calibrated, show turn descriptions and schematic path without meters.

## 3. Firestore and ownership boundaries (design proposal, not existing schema)

Logical data scopes:
- users/{uid}/gym_map_drafts/{draftId} — user-owned private drafts and metadata; enforce user-only access; no shared visibility by default.
- users/{uid}/gym_scan_sessions/{sessionId} — transient metadata with explicit retention; media in private protected storage if and only if opted in.
- gym_locations/{locationId} — normalized venue identity; owner/role checks required.
- gym_locations/{locationId}/map_versions/{versionId} — immutable published snapshots; creation/approval only via authorized server workflow.
- gym_locations/{locationId}/equipment_instances/{instanceId} — preferably version-snapshot scoped, not a mutable global truth; exact physical schema decided with GYM-00.
- gym_locations/{locationId}/contributions/{contributionId} — bounded drafts for moderator review; deny untrusted direct public-map edits.

These are illustrative candidate paths, NOT authority to change Firestore rules or create new collections. Inspect current collection-level wildcard and carve-outs first: Firestore grants access if ANY matching rule grants it. Check no broad wildcard accidentally permits public map writes. Require user identity, App Check where appropriate, per-venue editor authorization, server-side validation, abuse limits, data minimization and explicit audit records. Venue identity must not be assigned by free-text gym name.

## 4. Mobile boundaries

Recommended feature layout when authorized:
- mobile/lib/features/gym_map/data/ — immutable domain structures, geometry/route algorithms, repository interfaces (no Flutter dependency).
- mobile/lib/features/gym_map/state/ — Riverpod provider orchestration, user selection, read models.
- mobile/lib/features/gym_map/widgets/ — 2D map, catalog instance overlays, route preview.
- mobile/lib/features/gym_capture/ — optional camera capture and spatial research adapters.
- mobile/lib/features/gym_navigation/ — read-only adapter from existing eligible workout exercise and selected location to instance/route.
- mobile/lib/core/spatial/ — capability abstraction (Android ARCore; iOS ARKit; no-AR fallback).

Actual folder boundaries and route names require a dedicated code-map/architecture pass. Routing only via mobile/lib/core/router/app_router.dart, visual tokens through existing shared theme/widgets. Do not install Android-only SDK into common Dart business logic.

## 5. Vision and spatial contracts

Existing functions/src/ai_equipment_recognition.ts prompts the model to classify ONE central machine; do NOT call it a multi-object detector. Per-frame Quick Scan MAY reuse it. For simultaneous equipment detection evaluate Grounding DINO and a separately fine-tuned properly licensed RF-DETR; outputs are candidate boxes/classes, not persisted inventory.

Dedupe based on evidence across frames and physical geometry, never purely type ID or lexical name; uncertain instances need manual confirmation. Same visual type at two different locations can be two REAL units. One object from multiple angles must not create multiple units.

For map reconstruction evaluate ARCore depth, RTAB-Map, MapAnything Apache-authorized weights, optionally COLMAP/Open3D. Never equate per-session AR camera coordinates with long-term floor coordinates. Require map alignment against repeatable anchors/control points; detect tracking loss, mirroring, looping error and floor changes. Do not require continuous microphone/camera feed. Preserve inputs/outputs and inference provenance for field tests without retaining people's imagery.

## 6. Navigation, eligibility and voice boundary

- Route planner: weighted A*/Dijkstra on curated graph of edges connecting walkable nodes; verified machine approach point required.
- Obstacles: polygon intersections, walls, blocked corridors and restricted rooms are hard exclusions.
- Manual origin: first-class fallback; if no origin, show destination on map without claiming a route from current position.
- Multi-floor: not MVP, but do not conflate floors; future transitions via stairs/elevators only when explicitly modeled.
- Workout: use current scheduled/existing exercise; before suggesting DIFFERENT exercise, apply the existing injury-aware exercise_filter.dart eligibility logic. A cheaper/closer route never bypasses contraindications.
- Voice: reuse the existing action path once available; current features/voice/data/voice_command.dart parser is not proof of a wired speech-to-action system. Navigation-only voice assistance should not record sets, change planned exercise or assert durable write completion.
- Occupancy: only transient user-reported busy state in early releases; no camera-based crowd tracking or predicted release time.
- Unknown machine/destination: return a typed unavailable result, not synthetic coordinates or advice.

## 7. Resilience and operational contract

- Map data and graph downloaded for offline navigation, with version and signed/authenticated provenance; database/cache reads must be bounded.
- Offline edits remain user-owned pending suggestions; never publish on reconnect automatically.
- Spatial module failure -> drop to manual origin/map; model unavailability -> manual instance entry; routing failure -> show target without route; auth failure -> no cross-user map access.
- Foreground acquisition only; explicit start/stop, cancel, bounded memory/CPU/network, backpressure and battery/thermal mitigation.
- Confidence labels must refer to a defined source; raw model confidence is not calibrated position confidence.
- Telemetry: detection errors, correction counts, map validation failures, navigation fallback, policy denials, performance. Never log raw image/audio or health details by default.

## 8. Compatibility matrix

Existing touchpoints (read-only source review, actual HEAD must be revalidated):
- equipment_models.dart / EquipmentItem.id, ExerciseItem.equipmentId: canonical type references.
- equipment_alias_index.dart: resolve names to types, not physical objects.
- gemini_equipment_service.dart -> aiEquipmentRecognition: existing single-photo recognizer with bounded quota/server gateway.
- workout_session.dart / WorkoutSessionExercise: one authoritative workout persistence model; do not clone.
- workout_player_page.dart and scheduled_session.dart: consumers/entry points, not automatically extension points for writes.
- voice_command.dart: parser-only evidence; voice enablement depends on separate accepted voice action contract.
- GATE_F_GYM_IDENTITY_D0_NOTE: profile gymId free text; NOT a venue directory.
- GATE_G_SETUP_MEMORY_D0_NOTE: per-(type,gym) setup notes are NOT a unique physical machine ID.

## 9. Architecture prohibitions

No separate workout runtime, no unreviewed expansion of Firestore wildcard grants, no hidden cloud upload during passive scan, no false live positioning, no proprietary model weights under noncommercial license, no public maps derived only from unverified clients, and no automatic substitution of exercises without established safety checks.
