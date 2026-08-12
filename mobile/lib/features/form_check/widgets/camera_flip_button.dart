import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/camera/camera_session.dart' show SessionFacing;
import '../../../shared/widgets/app_buttons.dart';
import '../data/pose_detector_service.dart';

/// Swaps the lens the coach and the posture screen read from.
///
/// ## Why the app needs one at all
///
/// Both screens open the FRONT camera, and both want the whole body in frame.
/// Those two pull in opposite directions: at arm's length a selfie camera sees
/// a torso, and getting far enough away for head-to-heel means putting the
/// phone down — at which point the user cannot see the screen they are being
/// coached by. Standing at a mirror with the BACK camera solves both at once:
/// the reflection carries the distance and the screen stays readable.
///
/// Posture is the case that needs it most. Its measurements are lines through
/// the whole body — shoulder tilt, pelvis tilt, the head over the shoulders —
/// and a frame that stops at the ribs cannot produce any of them.
///
/// ## Shared between the two pages on purpose
///
/// Not copied into each. They already share `poseDetectorServiceProvider`, so
/// a second copy would be two places for the tooltip to drift out of step with
/// which camera is actually open.
class CameraFlipButton extends StatelessWidget {
  const CameraFlipButton({super.key, required this.svc});

  final PoseDetectorService svc;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Rebuilds on what OPENED, not on what was asked for. A phone with a
    // single camera answers the request with the same lens, and the label has
    // to keep saying so rather than flipping to a state the hardware never
    // reached.
    return ValueListenableBuilder<SessionFacing>(
      valueListenable: svc.facing,
      builder: (context, facing, _) {
        final front = facing == SessionFacing.front;
        return AppIconButton(
          key: const Key('camera.flip'),
          icon: front ? Icons.cameraswitch_outlined : Icons.cameraswitch,
          // Names the destination, not the current state: a control that says
          // where it will take you is readable at a glance mid-set, one that
          // reports where you are is not.
          tooltip: front ? l10n.cameraUseBackLens : l10n.cameraUseFrontLens,
          onPressed: svc.flipCamera,
        );
      },
    );
  }
}
