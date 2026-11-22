import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _oneSignalAppId = 'ba4385de-98c4-41e9-b94e-04fb783a241e';

class NotificationService {
  static bool _initialized = false;
  static Timer? _tagSyncTimer;

  static Future<void> init() async {
    if (kIsWeb || _initialized) return;
    _initialized = true;

    try {
      OneSignal.initialize(_oneSignalAppId);
      unawaited(_setupUserAndPermissions());
    } catch (_) {}
  }

  static Future<void> _setupUserAndPermissions() async {
    try {
      await OneSignal.Notifications.requestPermission(true);
      await syncUserTags();

      _tagSyncTimer?.cancel();
      _tagSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        syncUserTags();
      });
    } catch (_) {}
  }

  static Future<void> syncUserTags() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final isRegistered = prefs.getBool('is_registered') ?? false;
      final myId = prefs.getString('student_id') ?? '';

      if (isRegistered && myId.isNotEmpty) {
        await OneSignal.login(myId);
      }

      final masterEnabled = prefs.getBool('notif_master_enabled') ?? true;
      final academicEnabled = prefs.getBool('notif_academic_enabled') ?? true;
      final supportEnabled = prefs.getBool('notif_support_enabled') ?? true;
      final batchChatMuted = prefs.getBool('notif_batch_chat_muted') ?? false;

      await OneSignal.User.addTags({
        'student_id': myId,
        'master_notif': masterEnabled.toString(),
        'academic_notif': academicEnabled.toString(),
        'support_notif': supportEnabled.toString(),
        'mute_chat': batchChatMuted.toString(),
      });
    } catch (_) {}
  }

  static Future<void> checkForNewUpdates({bool isBackground = false}) async {
    await syncUserTags();
  }
}
