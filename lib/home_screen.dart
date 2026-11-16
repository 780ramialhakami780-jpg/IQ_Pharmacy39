import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'subject_screen.dart';

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

  List<dynamic> _subjects = [];
  List<dynamic> _schedule = [];
  List<dynamic> _assignments = [];
  List<dynamic> _notifications = [];

  final List<String> _days = ['السبت', 'الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس'];
  int _selectedDayIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadLocalData();
    _syncWithCloud(silent: true);
  }

  // تحميل البيانات المحفوظة محلياً للعمل بدون إنترنت فوراً
  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _studentName = prefs.getString('full_name') ?? 'طالب صيدلة';
      _studentId = prefs.getString('student_id') ?? '';
      _isAdmin = prefs.getBool('is_admin') ?? false;

      _subjects = jsonDecode(prefs.getString('cache_subjects') ?? '[]');
      _schedule = jsonDecode(prefs.getString('cache_schedule') ?? '[]');
      _assignments = jsonDecode(prefs.getString('cache_assignments') ?? '[]');
      _notifications = jsonDecode(prefs.getString('cache_notifications') ?? '[]');
    });
  }

  // مزامنة البيانات من السحابة وحفظها في الهاتف
  Future<void> _syncWithCloud({bool silent = false}) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      final client = Supabase.instance.client;
      final subjectsData = await client.from('subjects').select().order('sort_order');
      final scheduleData = await client.from('schedule').select().order('id');
      final assignmentsData = await client.from('assignments').select().order('due_date');
      final notificationsData = await client.from('notifications').select().order('created_at', ascending: false);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cache_subjects', jsonEncode(subjectsData));
      await prefs.setString('cache_schedule', jsonEncode(scheduleData));
      await prefs.setString('cache_assignments', jsonEncode(assignmentsData));
      await prefs.setString('cache_notifications', jsonEncode(notificationsData));

      if (!mounted) return;
      setState(() {
        _subjects = subjectsData;
        _schedule = scheduleData;
        _assignments = assignmentsData;
        _notifications = notificationsData;
      });

      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث ومزامنة جميع البيانات بنجاح'), backgroundColor: Colors.teal),
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أنت تعمل الآن بوضع عدم الاتصال (البيانات المحفوظة)'), backgroundColor: Colors.orange),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildDashboardTab(),
      _buildScheduleTab(),
      _buildAssignmentsTab(),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_currentIndex]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF181B20),
        selectedItemColor: const Color(0xFF4FD1C5),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'الرئيسية'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month_rounded), label: 'الجدول'),
          BottomNavigationBarItem(icon: Icon(Icons.push_pin_rounded), label: 'التكاليف'),
        ],
      ),
    );
  }

  // 1. تبويب الشاشة الرئيسية
  Widget _buildDashboardTab() {
    return RefreshIndicator(
      onRefresh: () => _syncWithCloud(silent: false),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // الشريط العلوي: الترحيب + الأزرار الستة
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('مرحباً بك،', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    Text(
                      _studentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // صف الأزرار العلوية (البحث العام، الإشعارات، QR، المزامنة، الدردشة، الإعدادات)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _topActionBtn(Icons.search_rounded, 'بحث', () => _openGlobalSearch()),
                _topActionBtn(Icons.notifications_active_rounded, 'الإشعارات', () => _openNotifications(), badge: _notifications.length),
                _topActionBtn(Icons.qr_code_scanner_rounded, 'تحضير', () => _openQRScanner()),
                _topActionBtn(
                  _isSyncing ? Icons.hourglass_top_rounded : Icons.sync_rounded,
                  'مزامنة',
                  () => _syncWithCloud(silent: false),
                ),
                _topActionBtn(Icons.chat_bubble_outline_rounded, 'الدردشة', () => _openBatchChat()),
                _topActionBtn(Icons.settings_rounded, 'الإعدادات', () => _openGeneralSettings()),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // شريط الأخبار والتحديثات
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
                      const Text('تطبيق IQ_Pharmacy39', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(
                        _notifications.isNotEmpty
                            ? _notifications.first['title']
                            : 'دفعة 39 صيدلة - بوابتك الدراسية المتكاملة',
                        style: const TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ملخص الجدول السريع
          InkWell(
            onTap: () => setState(() => _currentIndex = 1),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF181B20),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_note_rounded, color: Color(0xFF4FD1C5), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('جدول المحاضرات (${_schedule.length} محاضرة مسجلة)', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const Text('اضغط لعرض جدول الأسبوع والقاعات', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          const Text('المواد الدراسية', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          // قائمة المواد
          if (_subjects.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('اسحب للأسفل لمزامنة المواد لأول مرة')))
          else
            ..._subjects.map((subj) {
              Color cardColor = const Color(0xFF2B6CB0);
              try {
                final hex = (subj['color_hex'] ?? '#2B6CB0').toString().replaceAll('#', '');
                cardColor = Color(int.parse('FF$hex', radix: 16));
              } catch (_) {}

              return Card(
                color: const Color(0xFF181B20),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(color: cardColor.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.menu_book_rounded, color: cardColor),
                  ),
                  title: Text(subj['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Text(subj['subtitle'] ?? 'اضغط لفتح المادة والملفات', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SubjectScreen(subject: subj, defaultColor: cardColor),
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

  Widget _topActionBtn(IconData icon, String label, VoidCallback onTap, {int badge = 0}) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF181B20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF4FD1C5)),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              if (badge > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(10)),
                  child: Text('$badge', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  // 2. تبويب جدول المحاضرات
  Widget _buildScheduleTab() {
    final selectedDay = _days[_selectedDayIndex];
    final dayLectures = _schedule.where((item) => item['day_name'] == selectedDay).toList();

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.calendar_today_rounded, color: Color(0xFF4FD1C5)),
              SizedBox(width: 10),
              Text('جدول المحاضرات', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                  selectedColor: const Color(0xFF4FD1C5),
                  labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                  onSelected: (_) => setState(() => _selectedDayIndex = idx),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: dayLectures.isEmpty
              ? Center(child: Text('لا توجد محاضرات مسجلة ليوم $selectedDay', style: const TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: dayLectures.length,
                  itemBuilder: (context, idx) {
                    final lec = dayLectures[idx];
                    return Card(
                      color: const Color(0xFF181B20),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(lec['time_range'] ?? '', style: const TextStyle(color: Color(0xFF4FD1C5), fontWeight: FontWeight.bold)),
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

  // 3. تبويب التكاليف
  Widget _buildAssignmentsTab() {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.push_pin_rounded, color: Colors.redAccent),
              SizedBox(width: 10),
              Text('التكاليف والواجبات', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(
          child: _assignments.isEmpty
              ? const Center(child: Text('لا توجد تكاليف حالياً 🎉', style: TextStyle(fontSize: 16, color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _assignments.length,
                  itemBuilder: (context, idx) {
                    final task = _assignments[idx];
                    return Card(
                      color: const Color(0xFF181B20),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text('${task['subject_name']}: ${task['title']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${task['details']}\nموعد التسليم: ${task['due_date'].toString().split('T').first}'),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // نافذة البحث العام الشامل
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

  // نافذة الإشعارات
  void _openNotifications() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F1115),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('🔔 الإشعارات والتعاميم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: _notifications.isEmpty
                  ? const Center(child: Text('لا توجد إشعارات حالياً'))
                  : ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.all(16),
                      itemCount: _notifications.length,
                      itemBuilder: (_, i) {
                        final n = _notifications[i];
                        return Card(
                          color: const Color(0xFF181B20),
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(n['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
                                const SizedBox(height: 6),
                                Text(n['body'] ?? '', style: const TextStyle(height: 1.4)),
                                const SizedBox(height: 8),
                                Text('من: ${n['sender_name'] ?? 'مندوب الدفعة'}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
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

  // ماسح QR للتحضير في المحاضرات
  void _openQRScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('ماسح كود التحضير')),
          body: MobileScanner(
            onDetect: (capture) async {
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                final code = barcodes.first.rawValue!;
                Navigator.pop(context);
                try {
                  await Supabase.instance.client.from('attendance').insert({
                    'student_id': _studentId,
                    'full_name': _studentName,
                    'session_code': code,
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم تسجيل حضورك بنجاح ($_studentName)'), backgroundColor: Colors.green),
                    );
                  }
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تعذر إرسال التحضير، تأكد من اتصال الإنترنت'), backgroundColor: Colors.red),
                    );
                  }
                }
              }
            },
          ),
        ),
      ),
    );
  }

  // دردشة الدفعة
  void _openBatchChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BatchChatScreen(studentId: _studentId, defaultName: _studentName),
      ),
    );
  }

  // الإعدادات العامة (وتحتوي على مدخل لوحة الإدارة السرية)
  void _openGeneralSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('الإعدادات العامة')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                leading: const Icon(Icons.person, color: Color(0xFF4FD1C5)),
                title: Text(_studentName),
                subtitle: Text('رقم القيد المقفل بهذا الهاتف: $_studentId'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.sync, color: Colors.tealAccent),
                title: const Text('مزامنة وتحديث البيانات الآن'),
                onTap: () {
                  Navigator.pop(context);
                  _syncWithCloud(silent: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.admin_panel_settings, color: Colors.amber),
                title: const Text('لوحة إدارة الدفعة (للمشرفين فقط)'),
                subtitle: const Text('إرسال إشعارات، إضافة أسئلة، تعديل الجدول'),
                onTap: () => _promptAdminPassword(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _promptAdminPassword() {
    final passCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('رمز دخول المشرفين'),
        content: TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'أدخل الرمز السري للإدارة'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              // الرمز الافتراضي هو 3939 ويمكنك تغييره في المرحلة الرابعة
              if (passCtrl.text == '3939' || _isAdmin) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('مرحباً أيها المشرف! سنضيف لوحة التحكم الكاملة في المرحلة الرابعة')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('الرمز السري غير صحيح'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('دخول'),
          ),
        ],
      ),
    );
  }
}

// محرك البحث العام الشامل
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
  String get searchFieldLabel => 'ابحث في المواد، الجدول، الإشعارات، التكاليف...';

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
      return const Center(child: Text('اكتب أي كلمة للبحث في جميع أقسام التطبيق'));
    }
    final q = query.toLowerCase();
    final List<Widget> results = [];

    for (var s in subjects) {
      if ((s['name'] ?? '').toString().toLowerCase().contains(q)) {
        results.add(ListTile(
          leading: const Icon(Icons.book, color: Color(0xFF4FD1C5)),
          title: Text(s['name']),
          subtitle: const Text('قسم: المواد الدراسية'),
        ));
      }
    }
    for (var n in notifications) {
      if ((n['title'] ?? '').toString().toLowerCase().contains(q) || (n['body'] ?? '').toString().toLowerCase().contains(q)) {
        results.add(ListTile(
          leading: const Icon(Icons.notifications, color: Colors.amber),
          title: Text(n['title']),
          subtitle: Text('قسم: الإشعارات - ${n['body']}', maxLines: 1, overflow: TextOverflow.ellipsis),
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
        ? const Center(child: Text('لا توجد نتائج مطابقة لبحثك'))
        : ListView(children: results);
  }
}

// شاشة دردشة الدفعة
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
        const SnackBar(content: Text('الروابط غير مسموحة في دردشة الدفعة'), backgroundColor: Colors.red),
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
    final stream = Supabase.instance.client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('دردشة الدفعة'),
        actions: [
          TextButton(
            onPressed: () {
              final ctrl = TextEditingController(text: _nickname);
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('تغيير الاسم في الدردشة'),
                  content: TextField(controller: ctrl),
                  actions: [
                    ElevatedButton(
                      onPressed: () {
                        if (ctrl.text.trim().isNotEmpty) setState(() => _nickname = ctrl.text.trim());
                        Navigator.pop(context);
                      },
                      child: const Text('حفظ'),
                    )
                  ],
                ),
              );
            },
            child: const Text('تغيير الاسم', style: TextStyle(color: Color(0xFF4FD1C5))),
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
                          color: isMe ? const Color(0xFF1E3A5F) : const Color(0xFF181B20),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m['nickname'] ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFF4FD1C5), fontWeight: FontWeight.bold)),
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
            color: const Color(0xFF181B20),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    decoration: const InputDecoration(hintText: 'اكتب رسالة... (الروابط غير مسموحة)', border: InputBorder.none),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send_rounded, color: Color(0xFF4FD1C5)),
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
