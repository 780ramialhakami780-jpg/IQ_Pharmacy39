import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

const String _bgTaskName = 'iq_pharmacy39_notif_sync';
const String _supabaseUrl = 'https://stvavavzjrcxcivxykfv.supabase.co';
const String _supabaseAnonKey = 'sb_publishable_2D5B4SJgPAwqZqqgpiFaMA_HzTlka-k';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      try {
        Supabase.instance.client;
      } catch (_) {
        await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
      }
      await NotificationService.checkForNewUpdates(isBackground: true);
    } catch (_) {}
    return Future.value(true);
  });
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static Timer? _foregroundTimer;
  static bool _initialized = false;

  static Future<void> init() async {
    if (kIsWeb || _initialized) return;
    _initialized = true;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);

    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }

    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      _bgTaskName,
      _bgTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );

    await checkForNewUpdates();
    _foregroundTimer?.cancel();
    _foregroundTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      checkForNewUpdates();
    });
  }

  static Future<void> _showStatusBarNotification({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  static Future<void> checkForNewUpdates({bool isBackground = false}) async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final isRegistered = prefs.getBool('is_registered') ?? false;
      if (!isRegistered) return;

      final masterEnabled = prefs.getBool('notif_master_enabled') ?? true;
      if (!masterEnabled) return;

      final academicEnabled = prefs.getBool('notif_academic_enabled') ?? true;
      final supportEnabled = prefs.getBool('notif_support_enabled') ?? true;
      final batchChatMuted = prefs.getBool('notif_batch_chat_muted') ?? false;
      final myId = prefs.getString('student_id') ?? '';
      final firstBaselineDone = prefs.getBool('notif_baseline_ready') ?? false;

      final client = Supabase.instance.client;

      // 1. الإشعارات العامة، التكاليف، الإعلانات، الجدول، والملفات
      if (academicEnabled) {
        await _checkTableLatest(
          client: client,
          prefs: prefs,
          table: 'notifications',
          prefKey: 'last_seen_notif_id',
          baselineOnly: !firstBaselineDone,
          notifIdBase: 1000,
          channelId: 'academic_channel',
          channelName: 'إشعارات الدفعة والتكاليف',
          buildTitle: (row) => '📢 ${row['title'] ?? 'إشعار جديد للدفعة'}',
          buildBody: (row) => (row['body'] ?? '').toString(),
        );

        await _checkTableLatest(
          client: client,
          prefs: prefs,
          table: 'assignments',
          prefKey: 'last_seen_assign_id',
          baselineOnly: !firstBaselineDone,
          notifIdBase: 2000,
          channelId: 'academic_channel',
          channelName: 'إشعارات الدفعة والتكاليف',
          buildTitle: (row) => '📌 تكليف جديد: ${row['subject_name'] ?? ''}',
          buildBody: (row) => '${row['title'] ?? ''} (التسليم: ${row['due_date'] ?? ''})',
        );

        await _checkTableLatest(
          client: client,
          prefs: prefs,
          table: 'announcements',
          prefKey: 'last_seen_ann_id',
          baselineOnly: !firstBaselineDone,
          notifIdBase: 3000,
          channelId: 'academic_channel',
          channelName: 'إشعارات الدفعة والتكاليف',
          buildTitle: (row) => '🖼️ إعلان جديد للدفعة',
          buildBody: (row) => (row['title'] ?? '').toString(),
        );

        await _checkTableLatest(
          client: client,
          prefs: prefs,
          table: 'materials',
          prefKey: 'last_seen_mat_id',
          baselineOnly: !firstBaselineDone,
          notifIdBase: 4000,
          channelId: 'academic_channel',
          channelName: 'إشعارات الدفعة والتكاليف',
          buildTitle: (row) => '📁 ملف / محاضرة جديدة',
          buildBody: (row) => '${row['title'] ?? ''} (${row['file_type'] ?? 'ملف'})',
        );

        await _checkTableLatest(
          client: client,
          prefs: prefs,
          table: 'schedule',
          prefKey: 'last_seen_sched_id',
          baselineOnly: !firstBaselineDone,
          notifIdBase: 5000,
          channelId: 'academic_channel',
          channelName: 'إشعارات الدفعة والتكاليف',
          buildTitle: (row) => '📅 تحديث في الجدول الدراسي',
          buildBody: (row) => '${row['day_name'] ?? ''}: ${row['subject_name'] ?? ''} (${row['time_range'] ?? ''})',
        );
      }

      // 2. الرسائل الخاصة (للمشرفين في صندوق الدعم وللطالب عند رد المشرف)
      if (supportEnabled && myId.isNotEmpty) {
        try {
          final latestDm = await client
              .from('support_messages')
              .select()
              .eq('receiver_id', myId)
              .order('id', ascending: false)
              .limit(1)
              .maybeSingle();

          if (latestDm != null && latestDm['id'] != null) {
            final currentId = int.tryParse(latestDm['id'].toString()) ?? 0;
            final lastId = prefs.getInt('last_seen_dm_id') ?? 0;
            if (currentId > lastId) {
              await prefs.setInt('last_seen_dm_id', currentId);
              if (firstBaselineDone) {
                await _showStatusBarNotification(
                  id: 6000 + (currentId % 900),
                  title: '💬 رسالة خاصة من ${latestDm['sender_name'] ?? 'الدعم'}',
                  body: (latestDm['message'] ?? '').toString(),
                  channelId: 'support_dm_channel',
                  channelName: 'الرسائل الخاصة والدعم',
                );
              }
            }
          }
        } catch (_) {}
      }

      // 3. دردشة الدفعة العامة (تتوقف إذا فعّل الطالب زر الكتم)
      if (!batchChatMuted && myId.isNotEmpty) {
        for (final chatTable in ['batch_chat', 'chat_messages']) {
          try {
            final latestChat = await client
                .from(chatTable)
                .select()
                .order('id', ascending: false)
                .limit(1)
                .maybeSingle();

            if (latestChat != null && latestChat['id'] != null) {
              final currentId = int.tryParse(latestChat['id'].toString()) ?? 0;
              final lastId = prefs.getInt('last_seen_batch_chat_id') ?? 0;
              if (currentId > lastId) {
                await prefs.setInt('last_seen_batch_chat_id', currentId);
                final senderId = (latestChat['sender_id'] ?? latestChat['student_id'] ?? '').toString();
                if (firstBaselineDone && senderId != myId) {
                  final senderName = (latestChat['sender_name'] ?? latestChat['full_name'] ?? 'طالب').toString();
                  final msgText = (latestChat['message'] ?? latestChat['text'] ?? '').toString();
                  await _showStatusBarNotification(
                    id: 7000 + (currentId % 900),
                    title: '👥 دردشة الدفعة • $senderName',
                    body: msgText,
                    channelId: 'batch_chat_channel',
                    channelName: 'دردشة الدفعة العامة',
                  );
                }
              }
              break;
            }
          } catch (_) {}
        }
      }

      if (!firstBaselineDone) {
        await prefs.setBool('notif_baseline_ready', true);
      }
    } catch (_) {}
  }

  static Future<void> _checkTableLatest({
    required SupabaseClient client,
    required SharedPreferences prefs,
    required String table,
    required String prefKey,
    required bool baselineOnly,
    required int notifIdBase,
    required String channelId,
    required String channelName,
    required String Function(Map<String, dynamic>) buildTitle,
    required String Function(Map<String, dynamic>) buildBody,
  }) async {
    try {
      final row = await client.from(table).select().order('id', ascending: false).limit(1).maybeSingle();
      if (row != null && row['id'] != null) {
        final currentId = int.tryParse(row['id'].toString()) ?? 0;
        final lastId = prefs.getInt(prefKey) ?? 0;
        if (currentId > lastId) {
          await prefs.setInt(prefKey, currentId);
          if (!baselineOnly) {
            await _showStatusBarNotification(
              id: notifIdBase + (currentId % 900),
              title: buildTitle(row),
              body: buildBody(row),
              channelId: channelId,
              channelName: channelName,
            );
          }
        }
      }
    } catch (_) {}
  }
}
