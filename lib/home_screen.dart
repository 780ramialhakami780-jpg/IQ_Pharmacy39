import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'app_prefs.dart';
import 'subject_screen.dart';
import 'admin_screen.dart';
import 'gpa_screen.dart';
import 'directory_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  String _studentName = '';
  String _studentId = '';
  bool _isAdmin = false;
  bool _isSyncing = false;
  String _urgentBanner = '';

  List<dynamic> _subjects = [];
  List<dynamic> _schedule = [];
  List<dynamic> _assignments = [];
  List<dynamic> _notifications = [];
  List<dynamic> _myAttendance = [];

  final List<String> _days = ['السبت', 'الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس'];
  int _selectedDayIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadLocalData();
    _syncWithCloud(silent: true);
  }

  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _studentName = prefs.getString('full_name') ?? 'طالب صيدلة';
      _studentId = prefs.getString('student_id') ?? '';
      _isAdmin = prefs.getBool('is_admin') ?? false;
      _urgentBanner = prefs.getString('cache_urgent_banner') ?? '';

      _subjects = jsonDecode(prefs.getString('cache_subjects') ?? '[]');
      _schedule = jsonDecode(prefs.getString('cache_schedule') ?? '[]');
      _assignments = jsonDecode(prefs.getString('cache_assignments') ?? '[]');
      _notifications = jsonDecode(prefs.getString('cache_notifications') ?? '[]');
      _myAttendance = jsonDecode(prefs.getString('cache_my_attendance') ?? '[]');
    });
  }

  Future<void> _syncWithCloud({bool silent = false}) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      final client = Supabase.instance.client;
      final subjectsData = await client.from('subjects').select().order('sort_order');
      final scheduleData = await client.from('schedule').select().order('id');
      final assignmentsData = await client.from('assignments').select().order('due_date');
      final notificationsData = await client.from('notifications').select().order('created_at', ascending: false);

      String bannerText = '';
      try {
        final bannerRes = await client
            .from('app_settings')
            .select('value')
            .eq('key', 'urgent_banner')
            .maybeSingle();
        if (bannerRes != null && bannerRes['value'] != null) {
          bannerText = bannerRes['value'].toString().trim();
        }
      } catch (_) {}

      bool cloudAdmin = _isAdmin;
      List<dynamic> attendanceData = _myAttendance;
      if (_studentId.isNotEmpty) {
        final me = await client.from('students').select('is_admin').eq('student_id', _studentId).maybeSingle();
        if (me != null) {
          cloudAdmin = me['is_admin'] ?? false;
        }
        try {
          attendanceData = await client
              .from('attendance')
              .select()
              .eq('student_id', _studentId)
              .order('created_at', ascending: false);
        } catch (_) {}
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_admin', cloudAdmin);
      await prefs.setString('cache_urgent_banner', bannerText);
      await prefs.setString('cache_subjects', jsonEncode(subjectsData));
      await prefs.setString('cache_schedule', jsonEncode(scheduleData));
      await prefs.setString('cache_assignments', jsonEncode(assignmentsData));
      await prefs.setString('cache_notifications', jsonEncode(notificationsData));
      await prefs.setString('cache_my_attendance', jsonEncode(attendanceData));

      if (!mounted) return;
      setState(() {
        _isAdmin = cloudAdmin;
        _urgentBanner = bannerText;
        _subjects = subjectsData;
        _schedule = scheduleData;
        _assignments = assignmentsData;
        _notifications = notificationsData;
        _myAttendance = attendanceData;
      });

      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppPrefs.tr('تم تحديث ومزامنة جميع البيانات بنجاح', 'All data synced successfully')),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppPrefs.tr('أنت تعمل الآن بوضع عدم الاتصال (البيانات المحفوظة)', 'Offline mode (using cached data)')),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Theme.of(context).cardColor;
    final accent = Theme.of(context).colorScheme.primary;

    final pages = [
      _buildDashboardTab(cardBg, accent),
      _buildScheduleTab(cardBg, accent),
      _buildAssignmentsTab(cardBg),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_currentIndex]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: cardBg,
        selectedItemColor: accent,
        unselectedItemColor: Colors.grey,
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.home_rounded), label: AppPrefs.tr('الرئيسية', 'Home')),
          BottomNavigationBarItem(icon: const Icon(Icons.calendar_month_rounded), label: AppPrefs.tr('الجدول', 'Schedule')),
          BottomNavigationBarItem(icon: const Icon(Icons.push_pin_rounded), label: AppPrefs.tr('التكاليف', 'Assignments')),
        ],
      ),
    );
  }

  Widget _buildDashboardTab(Color cardBg, Color accent) {
    final borderCol = Colors.grey.withOpacity(0.2);

    return RefreshIndicator(
      onRefresh: () => _syncWithCloud(silent: false),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_urgentBanner.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.redAccent),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppPrefs.tr('تنبيه عاجل للدفعة', 'Urgent Batch Alert'),
                          style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(height: 2),
                        Text(_urgentBanner, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppPrefs.tr('مرحباً بك،', 'Welcome,'), style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    Text(
                      _studentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              if (_isAdmin)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amber),
                  ),
                  child: Text(
                    AppPrefs.tr('مندوب / مشرف', 'Admin'),
                    style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _topActionBtn(Icons.qr_code_2_rounded, AppPrefs.tr('كودي (QR)', 'My QR'), () => _showMyStudentQR(), cardBg, accent),
                _topActionBtn(Icons.calculate_rounded, AppPrefs.tr('حاسبة المعدل', 'GPA Calc'), () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const GpaScreen()));
                }, cardBg, accent),
                _topActionBtn(Icons.contact_phone_rounded, AppPrefs.tr('دليل الدفعة', 'Directory'), () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const DirectoryScreen()));
                }, cardBg, accent),
                _topActionBtn(Icons.search_rounded, AppPrefs.tr('بحث', 'Search'), () => _openGlobalSearch(), cardBg, accent),
                _topActionBtn(Icons.notifications_active_rounded, AppPrefs.tr('الإشعارات', 'Alerts'), () => _openNotifications(), cardBg, accent, badge: _notifications.length),
                _topActionBtn(
                  _isSyncing ? Icons.hourglass_top_rounded : Icons.sync_rounded,
                  AppPrefs.tr('مزامنة', 'Sync'),
                  () => _syncWithCloud(silent: false),
                  cardBg,
                  accent,
                ),
                _topActionBtn(Icons.chat_bubble_outline_rounded, AppPrefs.tr('الدردشة', 'Chat'), () => _openBatchChat(), cardBg, accent),
                _topActionBtn(Icons.settings_rounded, AppPrefs.tr('الإعدادات', 'Settings'), () => _openGeneralSettings(), cardBg, accent),
              ],
            ),
          ),
          const SizedBox(height: 18),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1D4ED8), Color(0xFF0D9488)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.campaign_rounded, size: 36, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppPrefs.tr('تطبيق IQ_Pharmacy39', 'IQ_Pharmacy39 App'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _notifications.isNotEmpty
                            ? _notifications.first['title']
                            : AppPrefs.tr('دفعة 39 صيدلة - بوابتك الدراسية المتكاملة', 'Batch 39 Pharmacy - Your Study Portal'),
                        style: const TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _currentIndex = 1),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderCol),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.event_note_rounded, color: accent, size: 24),
                        const SizedBox(height: 8),
                        Text(AppPrefs.tr('الجدول (${_schedule.length})', 'Schedule (${_schedule.length})'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(AppPrefs.tr('المحاضرات والقاعات', 'Lectures & Halls'), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () => _showMyAttendanceDetails(),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderCol),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.fact_check_rounded, color: Colors.green, size: 24),
                        const SizedBox(height: 8),
                        Text(AppPrefs.tr('سجل حضوري (${_myAttendance.length})', 'Attendance (${_myAttendance.length})'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(AppPrefs.tr('اضغط لعرض التفاصيل', 'Tap for details'), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          Text(AppPrefs.tr('المواد الدراسية', 'Subjects'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          if (_subjects.isEmpty)
            Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(AppPrefs.tr('اسحب للأسفل لمزامنة المواد لأول مرة', 'Pull down to sync subjects'))))
          else
            ..._subjects.map((subj) {
              Color subjColor = const Color(0xFF2B6CB0);
              try {
                final hex = (subj['color_hex'] ?? '#2B6CB0').toString().replaceAll('#', '');
                subjColor = Color(int.parse('FF$hex', radix: 16));
              } catch (_) {}

              return Card(
                color: cardBg,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(color: subjColor.withOpacity(0.18), borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.menu_book_rounded, color: subjColor),
                  ),
                  title: Text(subj['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Text(subj['subtitle'] ?? AppPrefs.tr('اضغط لفتح المادة والملفات', 'Tap to open subject files'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SubjectScreen(subject: subj, defaultColor: subjColor),
                      ),
                    );
                  },
                ),
              );
            }),
        ],
      ),
    );
  }

  void _showMyAttendanceDetails() {
    final cardBg = Theme.of(context).cardColor;
    final accent = Theme.of(context).colorScheme.primary;
    final Map<String, int> grouped = {};
    for (var record in _myAttendance) {
      final code = (record['session_code'] ?? 'عام').toString();
      grouped[code] = (grouped[code] ?? 0) + 1;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(AppPrefs.tr('سجل الحضور الشخصي (QR)', 'My Attendance Log (QR)'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: accent)),
                Chip(label: Text(AppPrefs.tr('الإجمالي: ${_myAttendance.length}', 'Total: ${_myAttendance.length}'))),
              ],
            ),
            const SizedBox(height: 12),
            if (_myAttendance.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    AppPrefs.tr(
                      'لم يتم تسجيل أي حضور لك بعد. اعرض كود QR الخاص بك للمندوب في المحاضرة.',
                      'No attendance recorded yet. Show your QR code to the admin in class.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: grouped.entries.map((e) => ListTile(
                    leading: const Icon(Icons.check_circle, color: Colors.green),
                    title: Text('${AppPrefs.tr('الجلسة / المادة:', 'Session:')} ${e.key}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: Text('${e.value} ${AppPrefs.tr('محاضرة', 'lectures')}', style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
                  )).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _topActionBtn(IconData icon, String label, VoidCallback onTap, Color cardBg, Color accent, {int badge = 0}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              if (badge > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(10)),
                  child: Text('$badge', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  void _showMyStudentQR() {
    final cardBg = Theme.of(context).cardColor;
    final accent = Theme.of(context).colorScheme.primary;
    final qrPayload = jsonEncode({
      'id': _studentId,
      'name': _studentName,
    });

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppPrefs.tr('بطاقة التحضير الذكية', 'Smart Attendance QR'), textAlign: TextAlign.center, style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
              child: QrImageView(
                data: qrPayload,
                version: QrVersions.auto,
                size: 210.0,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(_studentName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${AppPrefs.tr('رقم القيد:', 'Student ID:')} $_studentId', style: TextStyle(fontSize: 14, color: accent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(
              AppPrefs.tr(
                'أبرز هذا الكود للمندوب ليتم مسحه وتسجيل حضورك (يعمل بدون إنترنت)',
                'Show this QR code to the admin to record attendance (works offline)',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(context),
              child: Text(AppPrefs.tr('إغلاق', 'Close'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleTab(Color cardBg, Color accent) {
    final selectedDay = _days[_selectedDayIndex];
    final dayLectures = _schedule.where((item) => item['day_name'] == selectedDay).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.calendar_today_rounded, color: accent),
              const SizedBox(width: 10),
              Text(AppPrefs.tr('جدول المحاضرات', 'Lecture Schedule'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _days.length,
            itemBuilder: (context, idx) {
              final isSelected = idx == _selectedDayIndex;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(_days[idx]),
                  selected: isSelected,
                  selectedColor: accent,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.black : Theme.of(context).textTheme.bodyMedium?.color,
                    fontWeight: FontWeight.bold,
                  ),
                  onSelected: (_) => setState(() => _selectedDayIndex = idx),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: dayLectures.isEmpty
              ? Center(child: Text(AppPrefs.tr('لا توجد محاضرات مسجلة ليوم $selectedDay', 'No lectures on $selectedDay'), style: const TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: dayLectures.length,
                  itemBuilder: (context, idx) {
                    final lec = dayLectures[idx];
                    return Card(
                      color: cardBg,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(lec['time_range'] ?? '', style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(lec['lecture_order'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Text('📚 ${lec['subject_name']}  •  🏛️ ${lec['hall']}  •  👨‍🏫 ${lec['doctor_name']}',
                                style: const TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAssignmentsTab(Color cardBg) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.push_pin_rounded, color: Colors.redAccent),
              const SizedBox(width: 10),
              Text(AppPrefs.tr('التكاليف والواجبات', 'Assignments & Tasks'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(
          child: _assignments.isEmpty
              ? Center(child: Text(AppPrefs.tr('لا توجد تكاليف حالياً 🎉', 'No assignments right now 🎉'), style: const TextStyle(fontSize: 16, color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _assignments.length,
                  itemBuilder: (context, idx) {
                    final task = _assignments[idx];
                    return Card(
                      color: cardBg,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text('${task['subject_name']}: ${task['title']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${task['details']}\n${AppPrefs.tr('موعد التسليم:', 'Due:')} ${task['due_date'].toString().split('T').first}'),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _openGlobalSearch() {
    showSearch(
      context: context,
      delegate: AppGlobalSearchDelegate(
        subjects: _subjects,
        schedule: _schedule,
        assignments: _assignments,
        notifications: _notifications,
      ),
    );
  }

  void _openNotifications() {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final cardBg = Theme.of(context).cardColor;
    final accent = Theme.of(context).colorScheme.primary;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bg,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(AppPrefs.tr('🔔 الإشعارات والتعاميم', '🔔 Notifications'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: _notifications.isEmpty
                  ? Center(child: Text(AppPrefs.tr('لا توجد إشعارات حالياً', 'No notifications')))
                  : ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.all(16),
                      itemCount: _notifications.length,
                      itemBuilder: (_, i) {
                        final n = _notifications[i];
                        return Card(
                          color: cardBg,
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(n['title'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, color: accent)),
                                const SizedBox(height: 6),
                                Text(n['body'] ?? '', style: const TextStyle(height: 1.4)),
                                const SizedBox(height: 8),
                                Text('${AppPrefs.tr('من:', 'From:')} ${n['sender_name'] ?? 'مندوب الدفعة'}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _openBatchChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BatchChatScreen(studentId: _studentId, defaultName: _studentName),
      ),
    );
  }

  void _openGeneralSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (ctx, setSettingsState) {
            final accent = Theme.of(ctx).colorScheme.primary;
            return Scaffold(
              appBar: AppBar(title: Text(AppPrefs.tr('الإعدادات العامة', 'General Settings'))),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ListTile(
                    leading: Icon(Icons.person, color: accent),
                    title: Text(_studentName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(AppPrefs.tr('رقم القيد المقفل بهذا الهاتف: $_studentId', 'Locked Student ID: $_studentId')),
                  ),
                  const Divider(),
                  SwitchListTile(
                    secondary: Icon(AppPrefs.isDark ? Icons.dark_mode : Icons.light_mode, color: accent),
                    title: Text(AppPrefs.tr('الوضع الليلي (الغامق)', 'Dark Mode')),
                    subtitle: Text(AppPrefs.tr('تبديل مظهر التطبيق بين الغامق والفاتح', 'Switch app theme between Dark and Light')),
                    value: AppPrefs.isDark,
                    onChanged: (val) async {
                      await AppPrefs.setDark(val);
                      setSettingsState(() {});
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.language, color: Colors.purpleAccent),
                    title: Text(AppPrefs.tr('لغة الواجهة', 'App Language')),
                    subtitle: Text(AppPrefs.isEnglish ? 'English' : 'العربية'),
                    trailing: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'ar', label: Text('عربي')),
                        ButtonSegment(value: 'en', label: Text('EN')),
                      ],
                      selected: {AppPrefs.isEnglish ? 'en' : 'ar'},
                      onSelectionChanged: (selection) async {
                        await AppPrefs.setLang(selection.first);
                        setSettingsState(() {});
                      },
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.calculate, color: Colors.amber),
                    title: Text(AppPrefs.tr('حاسبة المعدل الفصلي والتراكمي', 'GPA Calculator')),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const GpaScreen()));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.contact_phone, color: Colors.lightBlue),
                    title: Text(AppPrefs.tr('دليل المناديب والروابط المهمة', 'Batch Directory & Links')),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const DirectoryScreen()));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.sync, color: Colors.teal),
                    title: Text(AppPrefs.tr('مزامنة وتحديث البيانات الآن', 'Sync Data Now')),
                    onTap: () {
                      Navigator.pop(context);
                      _syncWithCloud(silent: false);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.admin_panel_settings, color: Colors.orange),
                    title: Text(AppPrefs.tr('لوحة إدارة الدفعة (للمشرفين فقط)', 'Admin Dashboard (Admins Only)')),
                    subtitle: Text(AppPrefs.tr('إرسال إشعارات، رفع ملفات، كشوفات الحضور، فك الأجهزة', 'Notifications, files, attendance, unlock devices')),
                    onTap: () => _promptAdminPassword(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _promptAdminPassword() async {
    final prefs = await SharedPreferences.getInstance();
    String activePin = prefs.getString('admin_pin') ?? '3939';

    try {
      final res = await Supabase.instance.client
          .from('app_settings')
          .select('value')
          .eq('key', 'admin_pin')
          .maybeSingle();
      if (res != null && res['value'] != null) {
        activePin = res['value'].toString();
        await prefs.setString('admin_pin', activePin);
      }
    } catch (_) {}

    final passCtrl = TextEditingController();
    if (!mounted) return;
    final cardBg = Theme.of(context).cardColor;
    final accent = Theme.of(context).colorScheme.primary;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: cardBg,
        title: Text(AppPrefs.tr('رمز دخول المشرفين السري', 'Admin Secret PIN')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppPrefs.tr('أدخل الرمز السري المخصص لمندوبي الدفعة:', 'Enter admin PIN:'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, letterSpacing: 4),
              decoration: const InputDecoration(hintText: '••••', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: Text(AppPrefs.tr('إلغاء', 'Cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
            onPressed: () {
              if (passCtrl.text.trim() == activePin) {
                Navigator.pop(dialogCtx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AdminScreen(adminName: _studentName)),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppPrefs.tr('الرمز السري غير صحيح! الوصول مرفوض.', 'Invalid PIN! Access denied.')), backgroundColor: Colors.red),
                );
              }
            },
            child: Text(AppPrefs.tr('دخول للوحة', 'Enter'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class AppGlobalSearchDelegate extends SearchDelegate {
  final List<dynamic> subjects;
  final List<dynamic> schedule;
  final List<dynamic> assignments;
  final List<dynamic> notifications;

  AppGlobalSearchDelegate({
    required this.subjects,
    required this.schedule,
    required this.assignments,
    required this.notifications,
  });

  @override
  String get searchFieldLabel => AppPrefs.tr('ابحث في المواد، الجدول، الإشعارات...', 'Search subjects, schedule, alerts...');

  @override
  List<Widget>? buildActions(BuildContext context) => [
        IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
      ];

  @override
  Widget? buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults();

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults();

  Widget _buildSearchResults() {
    if (query.trim().isEmpty) {
      return Center(child: Text(AppPrefs.tr('اكتب أي كلمة للبحث في جميع أقسام التطبيق', 'Type to search across the app')));
    }
    final q = query.toLowerCase();
    final List<Widget> results = [];

    for (var s in subjects) {
      if ((s['name'] ?? '').toString().toLowerCase().contains(q)) {
        results.add(ListTile(
          leading: const Icon(Icons.book, color: Color(0xFF4FD1C5)),
          title: Text(s['name']),
          subtitle: Text(AppPrefs.tr('قسم: المواد الدراسية', 'Subjects')),
        ));
      }
    }
    for (var n in notifications) {
      if ((n['title'] ?? '').toString().toLowerCase().contains(q) || (n['body'] ?? '').toString().toLowerCase().contains(q)) {
        results.add(ListTile(
          leading: const Icon(Icons.notifications, color: Colors.amber),
          title: Text(n['title']),
          subtitle: Text('${n['body']}', maxLines: 1, overflow: TextOverflow.ellipsis),
        ));
      }
    }
    for (var sc in schedule) {
      if ((sc['subject_name'] ?? '').toString().toLowerCase().contains(q) || (sc['doctor_name'] ?? '').toString().toLowerCase().contains(q)) {
        results.add(ListTile(
          leading: const Icon(Icons.calendar_today, color: Colors.blueAccent),
          title: Text('${sc['subject_name']} (${sc['day_name']})'),
          subtitle: Text('${sc['time_range']} - ${sc['hall']}'),
        ));
      }
    }

    return results.isEmpty
        ? Center(child: Text(AppPrefs.tr('لا توجد نتائج مطابقة لبحثك', 'No matching results')))
        : ListView(children: results);
  }
}

class BatchChatScreen extends StatefulWidget {
  final String studentId;
  final String defaultName;
  const BatchChatScreen({super.key, required this.studentId, required this.defaultName});

  @override
  State<BatchChatScreen> createState() => _BatchChatScreenState();
}

class _BatchChatScreenState extends State<BatchChatScreen> {
  final TextEditingController _msgCtrl = TextEditingController();
  late String _nickname;

  @override
  void initState() {
    super.initState();
    _nickname = widget.defaultName.split(' ').take(2).join(' ');
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    if (text.contains('http://') || text.contains('https://') || text.contains('www.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppPrefs.tr('الروابط غير مسموحة في دردشة الدفعة', 'Links are not allowed in batch chat')), backgroundColor: Colors.red),
      );
      return;
    }
    _msgCtrl.clear();
    await Supabase.instance.client.from('chat_messages').insert({
      'student_id': widget.studentId,
      'nickname': _nickname,
      'message': text,
    });
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Theme.of(context).cardColor;
    final accent = Theme.of(context).colorScheme.primary;
    final isDark = AppPrefs.isDark;

    final stream = Supabase.instance.client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppPrefs.tr('دردشة الدفعة', 'Batch Chat')),
        actions: [
          TextButton(
            onPressed: () {
              final ctrl = TextEditingController(text: _nickname);
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(AppPrefs.tr('تغيير الاسم في الدردشة', 'Change Nickname')),
                  content: TextField(controller: ctrl),
                  actions: [
                    ElevatedButton(
                      onPressed: () {
                        if (ctrl.text.trim().isNotEmpty) setState(() => _nickname = ctrl.text.trim());
                        Navigator.pop(context);
                      },
                      child: Text(AppPrefs.tr('حفظ', 'Save')),
                    )
                  ],
                ),
              );
            },
            child: Text(AppPrefs.tr('تغيير الاسم', 'Edit Name'), style: TextStyle(color: accent)),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder(
              stream: stream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final msgs = snapshot.data!;
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[i];
                    final isMe = m['student_id'] == widget.studentId;
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe
                              ? (isDark ? const Color(0xFF1E3A5F) : const Color(0xFFCCFBF1))
                              : cardBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m['nickname'] ?? '', style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(m['message'] ?? ''),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            color: cardBg,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    decoration: InputDecoration(
                      hintText: AppPrefs.tr('اكتب رسالة... (الروابط غير مسموحة)', 'Type a message... (no links)'),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send_rounded, color: accent),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
