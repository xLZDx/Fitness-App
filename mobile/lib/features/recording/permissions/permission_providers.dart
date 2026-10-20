import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'permission_handler_permission_service.dart';
import 'permission_service.dart';

/// The permission seam for the recorder. Tests override it with
/// `FakePermissionService`. Creating the provider performs no platform call;
/// nothing requests a permission until a Start tap does (S04-R-021).
final permissionServiceProvider = Provider<PermissionService>(
  (ref) => const PermissionHandlerPermissionService(),
);
