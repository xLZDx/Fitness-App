# GYM DIGITAL TWIN — Open Source Reuse Register

Date: 2026-10-19. Status: shortlist/research; source references checked in current planning session and preceding product/review research. This is NOT legal clearance and no repository has been imported or executed.

## 1. Selection policy

Priority order:
1. Reuse current Fitness App capability when it already satisfies a narrow task.
2. Prefer maintained, testable projects with commercial-friendly LICENSE for source, dependencies, weights, datasets and assets.
3. Isolate heavy 3D/SLAM computation in optional research pipeline rather than impose on everyday mobile users.
4. Provenance/calibration is mandatory; a beautiful 3D scene is not automatically a navigable floor graph.
5. Benchmark on own consented gym corpus rather than using upstream accuracy as acceptance evidence.
6. Pin immutable upstream commit/tag/model SHA, record SBOM and provenance; security/license review before distribution or cloud deployment.

Legend: CANDIDATE = worth benchmarking; CONDITIONAL = only with rights/capability checks; REFERENCE = learn from, not approved to embed; HOLD = not suitable for current closed-source product without different license or material review.

## 2. Map reconstruction and spatial candidates

| Candidate | Reference URL | Role / technical fit | Rights / integration condition | Decision |
|---|---|---|---|---|
| MapAnything | https://github.com/facebookresearch/map-anything | Images/poses/depth -> metric geometry, server/GPU PoC; not graph/walkway verification | README distinguishes Apache weights facebook/map-anything-apache from other noncommercial weights; verify exact code+model+dependencies | CANDIDATE P1 (PoC only) |
| RTAB-Map | https://github.com/introlab/rtabmap | SLAM, loop closure, map/trajectory; R&D benchmark | BSD-style core; inspect optional libraries and build switches for incompatible rights | CANDIDATE P1 |
| COLMAP | https://github.com/colmap/colmap | Multi-photo Structure-from-Motion; offline reference geometry | Verify release, BSD components, CUDA/GPU dependency redistribution | CANDIDATE P2 |
| Open3D | https://github.com/isl-org/Open3D | Point cloud/post-processing, geometry cleanup, export to planar outlines | MIT source; inspect transitive and binary licenses | CANDIDATE P1 |
| stella_vslam | https://github.com/stella-cv/stella_vslam | Alternative SLAM | Need independent source/provenance and license/legal review of historical code disputes | HOLD |
| ORB-SLAM3 | https://github.com/UZ-SLAMLab/ORB_SLAM3 | Alternative visual-inertial SLAM reference | GPLv3 / separate commercial arrangement required for certain uses | HOLD |
| ARCore / Depth API | https://developers.google.com/ar/develop/depth | Android sensor/depth/pose capture adapter | Proprietary platform API; not an OSS library. Capability availability by phone; no guarantees | CONDITIONAL |
| ARKit | https://developer.apple.com/augmented-reality/arkit/ | iOS native spatial adapter | Platform API / supported device; parity contract required | CONDITIONAL |
| AprilTag | https://github.com/AprilRobotics/apriltag | Venue-approved fiducial landmarks and repeat localization | BSD-2-Clause claimed; validate license in exact release | CANDIDATE P2 |

## 3. Recognition/detection/segmentation candidates

| Candidate | Reference URL | Role / technical fit | Rights / integration condition | Decision |
|---|---|---|---|---|
| Existing aiEquipmentRecognition | functions/src/ai_equipment_recognition.ts | SINGLE centered gym machine -> raw model answer -> existing alias index client-side | Already in Fitness App; preserve its gateway quotas, auth, image validation, timeout | REUSE FIRST (Quick Scan) |
| Grounding DINO | https://github.com/IDEA-Research/GroundingDINO | Detect multiple object candidates based on category labels | Apache-2.0 source; separately check released weights and all dependencies | CANDIDATE P1 |
| RF-DETR | https://github.com/roboflow/rf-detr | Fine-tunable multi-object detector | Apache package + Apache-marked weights only; Plus / certain XL weights under PML 1.0 | CANDIDATE P1 |
| SAM 2 | https://github.com/facebookresearch/sam2 | Segmentation and tracking across views; duplicates/footprints support | Apache-2.0 project; confirm downloaded weights/rights | CONDITIONAL, only if measured improvement |
| Depth Anything V2 | https://github.com/DepthAnything/Depth-Anything-V2 | Supplemental monocular depth; NOT persistent floor localization | Small checkpoint Apache-2.0; Base/Large noncommercial CC-BY-NC-4.0 per upstream; verify exact variant | CONDITIONAL P2 |
| ONNX Runtime | https://github.com/microsoft/onnxruntime | Local inference runtime if model exported and device performance works | MIT; audit providers/backends/dependencies | CANDIDATE P2 |
| Gym-Machines-Classifier | https://github.com/Mohamed1Youssef/Gym-Machines-Classifier | EfficientNet-B0, 16-category single-photo baseline, author claims 83.87% validation accuracy | No explicit root LICENSE found in initial inspection: source/checkpoint/dataset cannot be assumed commercial | REFERENCE ONLY pending permissions |
| gym-equip-classifier | https://github.com/arkaadiana/gym-equip-classifier | MobileNetV2/TFLite example for 8 equipment classes | Separate license for source/weights/dataset not established | REFERENCE ONLY |
| gym_equipment_recognition | https://github.com/Aashi3131/gym_equipment_recognition | CNN/Streamlit teaching example | Commercial rights and quality unclear | REFERENCE ONLY |
| Fitness Equipment Detection Model | https://github.com/cpruz/Fitness-Equipment-Detection-Model | Points to Roboflow-hosted detector; reported 20+ categories | GitHub CC0 README does NOT grant external hosted model/dataset rights; inspect Roboflow asset terms | REFERENCE ONLY |

Upstream model performance applies to upstream validation data, NOT this project's gym pilot. Record all licensing claims with exact upstream URL/commit and model checkpoint ID at GDT-004.

## 4. Navigation, AR and Flutter ecosystem

| Candidate | URL | Role / rights | Decision |
|---|---|---|---|
| Recast & Detour | https://github.com/recastnavigation/recastnavigation | Zlib; navmesh generator/path queries, overkill for first verified 2D graph | CONDITIONAL P2 |
| ar_flutter_plugin_plus | https://pub.dev/packages/ar_flutter_plugin_plus | Flutter AR bridge; verify actual depth/camera pose APIs, maintenance and iOS support | SPIKE ONLY |
| Navigine Flutter SDK 2.0 | https://github.com/Navigine/Indoor-Navigation-Flutter-SDK-2.0 | Indoor SDK sample, but its repository license describes a commercial license requiring vendor agreement | HOLD |
| Flutter/CustomPainter + deterministic A* | Existing Flutter stack and project-owned algorithm | Controlled small graph rendering, no external nav runtime/fees | FIRST CHOICE P0 |
| Ultralytics | https://github.com/ultralytics/ultralytics | YOLO detection ecosystem under AGPL-3.0/Enterprise licensing | HOLD unless counsel accepts obligations or commercial contract |

## 5. Experiment decision matrix

**MapAnything versus RTAB-Map versus no 3D:**
- Common frozen input: same consented frames, calibrated points, repeated scans and field notes.
- Outputs: absolute/relative pose error, instance-to-floor placement error, geometry completeness, failure mode, resource/cost profile.
- Exclude from production if inaccurate, unlicensed, unstable, impossible to align or poorer value than import/manual mapping.
- Use image-only reconstruction only when users opt in to necessary processing; never silently sync bystander video.

**Existing recognizer versus Grounding DINO versus RF-DETR:**
- Compare centered-image type accuracy, multi-object detection recall, correct catalog mapping and instances across frames.
- Include mismatched, novel and similar-looking equipment and out-of-catalog "unknown".
- Count cost and compute; measure phones and server separately.
- No trained checkpoint accepted without copyright/data/license, training and validation manifest.

**Map UI routing:**
- First implement deterministic A* over verified corridors/approach points with a plain Dart data-layer test library.
- Compare Recast & Detour only after multi-floor complex layouts justify its footprint.

## 6. Adoption checklist for each candidate

- [ ] Pin repository URL, tag/commit SHA, release and maintenance status.
- [ ] Review LICENSE and NOTICE for **source**.
- [ ] Check pretrained **weights** separately, including all variants used.
- [ ] Confirm **dataset** use/training/redistribution and any image-rights restrictions.
- [ ] Check bundled **assets**, fonts and example code rights.
- [ ] Generate dependency tree/SBOM and record native binary/CPU/GPU licenses.
- [ ] Record security CVEs, pinned hashes, provenance of model downloads.
- [ ] Record on-device performance, cloud spend, minimum OS and iOS fallback.
- [ ] Compare against existing Fitness App capability and no-AI baseline.
- [ ] Obtain legal/security decision before merge or release.

No code, checkpoint or dataset should be embedded just because a repository is publicly readable. No candidate is approved merely by this shortlist.
