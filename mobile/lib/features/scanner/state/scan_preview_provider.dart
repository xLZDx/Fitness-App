import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/camera/camera_session.dart';
import '../../visual_equipment/widgets/live_equipment_preview.dart';

/// What the Scan viewfinder card draws where the camera goes.
///
/// Production: [LiveEquipmentPreview] on the shared session -- the live
/// camera, or its warming spinner while the camera opens. A test seam, not a
/// feature flag: the reference-fidelity goldens (`scan_reference_golden_test`)
/// override it with a transparent box, because the reference draws no photo
/// in the card (SCAN-G1, core/SCAN_G1_SCOPE.md R6) and a warming spinner --
/// what a host test's camera-less session would otherwise show -- would put
/// an animating, half-black square where the diff is measured.
final scanPreviewBuilderProvider =
    Provider<Widget Function(CameraSession session)>(
  (_) => (CameraSession session) => LiveEquipmentPreview(session: session),
);
