/// Localised wording for scan poses and readiness prompts.
library;

import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../readiness_evaluator.dart';
import '../scan_pose.dart';

String poseLabel(AppLocalizations l10n, ScanPose pose) => switch (pose) {
      ScanPose.front => l10n.scanPoseFront,
      ScanPose.side => l10n.scanPoseSide,
      ScanPose.back => l10n.scanPoseBack,
    };

/// Neutral, instruction-only wording. Never says anything about the body.
String hintText(AppLocalizations l10n, ReadinessHint hint) => switch (hint) {
      ReadinessHint.none => l10n.scanHintReady,
      ReadinessHint.moreLight => l10n.scanHintMoreLight,
      ReadinessHint.lessLight => l10n.scanHintLessLight,
      ReadinessHint.showFullBody => l10n.scanHintShowFullBody,
      ReadinessHint.stepBack => l10n.scanHintStepBack,
      ReadinessHint.stepCloser => l10n.scanHintStepCloser,
      ReadinessHint.centerYourself => l10n.scanHintCenter,
      ReadinessHint.turnSideways => l10n.scanHintTurnSideways,
      ReadinessHint.turnAround => l10n.scanHintTurnAround,
      ReadinessHint.faceCamera => l10n.scanHintFaceCamera,
      ReadinessHint.trackingProblem => l10n.scanHintTracking,
    };
