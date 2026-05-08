import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mock_notification_service.dart';
import 'notification_service.dart';

/// Cross-feature reminder service. Default is the in-memory mock so
/// nothing in the app accidentally requires a platform plugin during
/// tests; `main.dart` overrides it with `LocalNotificationService`.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return MockNotificationService();
});
