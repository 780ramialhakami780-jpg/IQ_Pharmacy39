import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'subject_screen.dart';
import 'admin_screen.dart';

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

  Future<void> _syncWithCloud({bool silent = false}) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      final client = Supabase.instance.client;
      final subjectsData = await client.from('subjects').select().order('sort_order');
      final scheduleData = await client.from('schedule').select().order('id');
      final assignmentsData = await client.from('assignments').select().order('due_date');
      final notificationsData = await client.from('notifications').select().order('created_at', ascending: false);

      // تحديث حالة الصلاحية من السحابة أيضاً
      bool cloudAdmin = _isAdmin;
      if (_studentId.isNotEmpty) {
        final me = await client.from('students').select('is_admin').eq('student_id', _studentId).maybeSingle();
        if (me != null) {
          cloudAdmin = me['is_admin'] ?? false;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_admin', cloudAdmin);
      await prefs.setString('cache_subjects', jsonEncode(subjectsData));
      await prefs.setString('cache_schedule', jsonEncode(scheduleData));
      await prefs.setString('cache_assignments', jsonEncode(assignmentsData));
      await prefs.setString('cache_notifications', jsonEncode(notificationsData));

      if (!mounted) return;
      setState(() {
        _isAdmin = cloudAdmin;
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

  Widget _buildDashboardTab() {
    return RefreshIndicator(
      onRefresh: () => _syncWithCloud(silent: false),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
              if (_isAdmin)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amber),
                  ),
                  child: const Text('مندوب / مشرف', style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _topActionBtn(Icons.qr_code_2_rounded, 'كودي (QR)', () => _showMyStudentQR()),
                _topActionBtn(Icons.search_rounded, 'بحث', () => _openGlobalSearch()),
                _topActionBtn(Icons.notifications_active_rounded, 'الإشعارات', () => _openNotifications(), badge: _notifications.length),
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

  // عرض بطاقة كود QR الخاص بالطالب للتحضير (يعمل أوفلاين 100%)
  void _showMyStudentQR() {
    final qrPayload = jsonEncode({
      'id': _studentId,
      'name': _studentName,
    });

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF181B20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('بطاقة التحضير الذكية', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF4FD1C5), fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: qrPayload,
                version: QrVersions.auto,
                size: 210.0,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(_studentName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 4),
            Text('رقم القيد: $_studentId', style: const TextStyle(fontSize: 14, color: Color(0xFF4FD1C5), fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text(
              'أبرز هذا الكود للمندوب ليتم مسحه وتسجيل حضورك (يعمل بدون إنترنت)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FD1C5), foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

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
                subtitle: const Text('إرسال إشعارات، رفع ملفات، تحضير QR، تعديل الجدول'),
                onTap: () => _promptAdminPassword(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // التحقق الصارم بالرمز السري الخاص بالمشرفين فقط
  Future<void> _promptAdminPassword() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString('admin_pin') ?? '3939'; // الرمز الافتراضي 3939 ويمكن تغييره من اللوحة
    final passCtrl = TextEditingController();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF181B20),
        title: const Text('رمز دخول المشرفين السري'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('أدخل الرمز السري المخصص لمندوبي الدفعة:', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, letterSpacing: 4),
              decoration: const InputDecoration(
                hintText: '••••',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FD1C5), foregroundColor: Colors.black),
            onPressed: () {
              if (passCtrl.text.trim() == savedPin) {
                Navigator.pop(dialogCtx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AdminScreen(adminName: _studentName)),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('الرمز السري غير صحيح! الوصول مرفوض.'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('دخول للوحة', style: TextStyle(fontWeight: FontWeight.bold)),
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
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class AdminScreen extends StatefulWidget {
  final String adminName;
  const AdminScreen({super.key, required this.adminName});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _client = Supabase.instance.client;
  List<dynamic> _subjects = [];
  List<dynamic> _attendance = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    try {
      final subjs = await _client.from('subjects').select().order('sort_order');
      final att = await _client.from('attendance').select().order('created_at', ascending: false).limit(50);
      if (!mounted) return;
      setState(() {
        _subjects = subjs;
        _attendance = att;
      });
    } catch (_) {}
  }

  void _showMsg(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: isError ? Colors.redAccent : Colors.teal),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لوحة إدارة الدفعة السرية'),
          backgroundColor: const Color(0xFF1E293B),
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: Color(0xFF4FD1C5),
            tabs: [
              Tab(text: 'إشعارات وتكاليف'),
              Tab(text: 'المواد والملفات'),
              Tab(text: 'بنك الأسئلة'),
              Tab(text: 'الجدول والحضور'),
              Tab(text: 'الرمز السري'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildNotificationsAndTasksTab(),
                  _buildSubjectsAndFilesTab(),
                  _buildAddQuestionTab(),
                  _buildScheduleAndAttendanceTab(),
                  _buildChangePinTab(),
                ],
              ),
      ),
    );
  }

  // 1. تبويب إرسال إشعار + إضافة تكليف
  Widget _buildNotificationsAndTasksTab() {
    final notifTitle = TextEditingController();
    final notifBody = TextEditingController();

    final taskSubj = TextEditingController();
    final taskTitle = TextEditingController();
    final taskDetails = TextEditingController();
    final taskDate = TextEditingController(text: '2026-11-25');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('📢 إرسال إشعار عاجل للدفعة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
        const SizedBox(height: 10),
        TextField(controller: notifTitle, decoration: const InputDecoration(labelText: 'عنوان الإشعار', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: notifBody, maxLines: 3, decoration: const InputDecoration(labelText: 'نص الإشعار', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          icon: const Icon(Icons.send),
          label: const Text('نشر الإشعار الآن'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FD1C5), foregroundColor: Colors.black),
          onPressed: () async {
            if (notifTitle.text.trim().isEmpty || notifBody.text.trim().isEmpty) return;
            setState(() => _isLoading = true);
            try {
              await _client.from('notifications').insert({
                'title': notifTitle.text.trim(),
                'body': notifBody.text.trim(),
                'sender_name': widget.adminName,
              });
              _showMsg('تم إرسال الإشعار لجميع الطلاب بنجاح');
            } catch (e) {
              _showMsg('فشل الإرسال، تأكد من الإنترنت', isError: true);
            } finally {
              if (mounted) setState(() => _isLoading = false);
            }
          },
        ),
        const Divider(height: 36),
        const Text('📌 إضافة تكليف / واجب جديد', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
        const SizedBox(height: 10),
        TextField(controller: taskSubj, decoration: const InputDecoration(labelText: 'اسم المادة', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: taskTitle, decoration: const InputDecoration(labelText: 'عنوان التكليف', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: taskDetails, decoration: const InputDecoration(labelText: 'التفاصيل المطلوبة', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: taskDate, decoration: const InputDecoration(labelText: 'موعد التسليم (YYYY-MM-DD)', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          icon: const Icon(Icons.add_task),
          label: const Text('حفظ التكليف'),
          onPressed: () async {
            if (taskTitle.text.trim().isEmpty) return;
            setState(() => _isLoading = true);
            try {
              await _client.from('assignments').insert({
                'subject_name': taskSubj.text.trim(),
                'title': taskTitle.text.trim(),
                'details': taskDetails.text.trim(),
                'due_date': taskDate.text.trim(),
              });
              _showMsg('تمت إضافة التكليف بنجاح');
            } catch (_) {
              _showMsg('حدث خطأ أثناء الحفظ', isError: true);
            } finally {
              if (mounted) setState(() => _isLoading = false);
            }
          },
        ),
      ],
    );
  }

  // 2. تبويب إضافة مادة + رفع PDF مباشرة أو إضافة رابط فيديو/صوت
  Widget _buildSubjectsAndFilesTab() {
    final subjName = TextEditingController();
    final subjDesc = TextEditingController();

    int? selectedSubjId = _subjects.isNotEmpty ? _subjects.first['id'] : null;
    final lecNum = TextEditingController(text: '1');
    final fileTitle = TextEditingController();
    String selectedType = 'PDF';
    final fileUrl = TextEditingController();
    PlatformFile? pickedPdfFile;

    return StatefulBuilder(
      builder: (context, setInnerState) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('📚 إضافة مادة دراسية جديدة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
          const SizedBox(height: 10),
          TextField(controller: subjName, decoration: const InputDecoration(labelText: 'اسم المادة (مثلاً: Pharmacology)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: subjDesc, decoration: const InputDecoration(labelText: 'وصف مختصر أو اسم الدكتور', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () async {
              if (subjName.text.trim().isEmpty) return;
              setState(() => _isLoading = true);
              try {
                await _client.from('subjects').insert({
                  'name': subjName.text.trim(),
                  'subtitle': subjDesc.text.trim(),
                  'color_hex': '#2B6CB0',
                  'sort_order': _subjects.length + 1,
                });
                await _fetchInitialData();
                _showMsg('تمت إضافة المادة بنجاح');
              } catch (_) {
                _showMsg('تعذر إضافة المادة', isError: true);
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            child: const Text('إضافة المادة'),
          ),
          const Divider(height: 36),
          const Text('📁 إضافة ملف PDF أو رابط محاضرة لمادة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
          const SizedBox(height: 10),
          if (_subjects.isNotEmpty)
            DropdownButtonFormField<int>(
              value: selectedSubjId,
              decoration: const InputDecoration(labelText: 'اختر المادة', border: OutlineInputBorder()),
              items: _subjects.map<DropdownMenuItem<int>>((s) => DropdownMenuItem(value: s['id'], child: Text(s['name']))).toList(),
              onChanged: (val) => setInnerState(() => selectedSubjId = val),
            ),
          const SizedBox(height: 10),
          TextField(controller: lecNum, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'رقم المحاضرة', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: fileTitle, decoration: const InputDecoration(labelText: 'عنوان الملخص أو المحاضرة', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: selectedType,
            decoration: const InputDecoration(labelText: 'نوع المحتوى', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'PDF', child: Text('ملف ملخص / محاضرة (PDF يُحفظ أوفلاين)')),
              DropdownMenuItem(value: 'VIDEO', child: Text('رابط فيديو (يوتيوب / تيليجرام)')),
              DropdownMenuItem(value: 'AUDIO', child: Text('رابط تسجيل صوتي (تيليجرام)')),
            ],
            onChanged: (val) => setInnerState(() {
              selectedType = val ?? 'PDF';
              pickedPdfFile = null;
              fileUrl.clear();
            }),
          ),
          const SizedBox(height: 12),

          if (selectedType == 'PDF') ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.upload_file_rounded, color: Color(0xFF4FD1C5)),
              label: Text(
                pickedPdfFile == null ? 'اختر ملف PDF من الهاتف' : 'تم اختيار: ${pickedPdfFile!.name}',
                style: const TextStyle(color: Colors.white),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Color(0xFF4FD1C5)),
              ),
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['pdf'],
                  withData: true,
                );
                if (result != null && result.files.isNotEmpty) {
                  setInnerState(() => pickedPdfFile = result.files.first);
                }
              },
            ),
          ] else ...[
            TextField(
              controller: fileUrl,
              decoration: const InputDecoration(
                labelText: 'الصق رابط التليجرام أو اليوتيوب هنا',
                border: OutlineInputBorder(),
              ),
            ),
          ],

          const SizedBox(height: 14),
          ElevatedButton.icon(
            icon: const Icon(Icons.cloud_upload_rounded),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4FD1C5),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () async {
              if (selectedSubjId == null || fileTitle.text.trim().isEmpty) {
                _showMsg('يرجى اختيار المادة وكتابة العنوان', isError: true);
                return;
              }

              setState(() => _isLoading = true);
              try {
                String finalUrl = fileUrl.text.trim();

                if (selectedType == 'PDF') {
                  if (pickedPdfFile == null) {
                    _showMsg('يرجى اختيار ملف PDF أولاً', isError: true);
                    setState(() => _isLoading = false);
                    return;
                  }

                  final fileName = 'lec_${DateTime.now().millisecondsSinceEpoch}.pdf';
                  Uint8List? fileBytes = pickedPdfFile!.bytes;
                  if (fileBytes == null && !kIsWeb && pickedPdfFile!.path != null) {
                    fileBytes = await File(pickedPdfFile!.path!).readAsBytes();
                  }

                  if (fileBytes == null) {
                    _showMsg('تعذر قراءة الملف المختار', isError: true);
                    setState(() => _isLoading = false);
                    return;
                  }

                  await _client.storage.from('materials').uploadBinary(
                        fileName,
                        fileBytes,
                        fileOptions: const FileOptions(contentType: 'application/pdf', upsert: true),
                      );

                  finalUrl = _client.storage.from('materials').getPublicUrl(fileName);
                } else {
                  if (finalUrl.isEmpty) {
                    _showMsg('يرجى لصق الرابط أولاً', isError: true);
                    setState(() => _isLoading = false);
                    return;
                  }
                }

                await _client.from('materials').insert({
                  'subject_id': selectedSubjId,
                  'lecture_number': int.tryParse(lecNum.text) ?? 1,
                  'title': fileTitle.text.trim(),
                  'file_type': selectedType,
                  'file_url': finalUrl,
                });

                _showMsg('تم رفع وحفظ المحتوى بنجاح');
              } catch (e) {
                _showMsg('فشل الرفع، تأكد من الإنترنت وصلاحيات Storage', isError: true);
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            label: const Text('رفع وحفظ في المادة', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 3. تبويب إضافة سؤال لبنك الأسئلة
  Widget _buildAddQuestionTab() {
    int? selectedSubjId = _subjects.isNotEmpty ? _subjects.first['id'] : null;
    final qText = TextEditingController();
    final opt1 = TextEditingController();
    final opt2 = TextEditingController();
    final opt3 = TextEditingController();
    final opt4 = TextEditingController();
    int correctIdx = 0;
    final expCtrl = TextEditingController();

    return StatefulBuilder(
      builder: (context, setInnerState) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('❓ إضافة سؤال جديد لبنك الأسئلة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
          const SizedBox(height: 12),
          if (_subjects.isNotEmpty)
            DropdownButtonFormField<int>(
              value: selectedSubjId,
              decoration: const InputDecoration(labelText: 'اختر المادة', border: OutlineInputBorder()),
              items: _subjects.map<DropdownMenuItem<int>>((s) => DropdownMenuItem(value: s['id'], child: Text(s['name']))).toList(),
              onChanged: (val) => setInnerState(() => selectedSubjId = val),
            ),
          const SizedBox(height: 10),
          TextField(controller: qText, maxLines: 2, decoration: const InputDecoration(labelText: 'نص السؤال', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: opt1, decoration: const InputDecoration(labelText: 'الخيار الأول (A)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: opt2, decoration: const InputDecoration(labelText: 'الخيار الثاني (B)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: opt3, decoration: const InputDecoration(labelText: 'الخيار الثالث (C)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: opt4, decoration: const InputDecoration(labelText: 'الخيار الرابع (D)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: correctIdx,
            decoration: const InputDecoration(labelText: 'الإجابة الصحيحة', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 0, child: Text('الخيار الأول (A)')),
              DropdownMenuItem(value: 1, child: Text('الخيار الثاني (B)')),
              DropdownMenuItem(value: 2, child: Text('الخيار الثالث (C)')),
              DropdownMenuItem(value: 3, child: Text('الخيار الرابع (D)')),
            ],
            onChanged: (val) => setInnerState(() => correctIdx = val ?? 0),
          ),
          const SizedBox(height: 10),
          TextField(controller: expCtrl, decoration: const InputDecoration(labelText: 'توضيح الإجابة (اختياري)', border: OutlineInputBorder())),
          const SizedBox(height: 14),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FD1C5), foregroundColor: Colors.black),
            onPressed: () async {
              if (selectedSubjId == null || qText.text.trim().isEmpty) return;
              final opts = [opt1.text.trim(), opt2.text.trim(), opt3.text.trim(), opt4.text.trim()].where((e) => e.isNotEmpty).toList();
              if (opts.length < 2) {
                _showMsg('أدخل خيارين على الأقل', isError: true);
                return;
              }
              setState(() => _isLoading = true);
              try {
                await _client.from('questions').insert({
                  'subject_id': selectedSubjId,
                  'question_text': qText.text.trim(),
                  'options': jsonEncode(opts),
                  'correct_index': correctIdx,
                  'explanation': expCtrl.text.trim(),
                });
                _showMsg('تمت إضافة السؤال لبنك المادة بنجاح');
              } catch (_) {
                _showMsg('فشل حفظ السؤال', isError: true);
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            child: const Text('حفظ السؤال في البنك'),
          ),
        ],
      ),
    );
  }

  // 4. تبويب الجدول + ماسح كاميرا المندوب لتحضير الطلاب عبر QR
  Widget _buildScheduleAndAttendanceTab() {
    String selectedDay = 'السبت';
    final orderCtrl = TextEditingController(text: 'المحاضرة الأولى');
    final timeCtrl = TextEditingController(text: '08:00 - 10:00');
    final subjCtrl = TextEditingController();
    final hallCtrl = TextEditingController();
    final docCtrl = TextEditingController();
    final sessionCtrl = TextEditingController(text: 'محاضرة ${DateTime.now().month}/${DateTime.now().day}');

    return StatefulBuilder(
      builder: (context, setInnerState) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // قسم تحضير الطلاب بالكاميرا
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF181B20),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📷 تحضير الطلاب بمسح كود (QR)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                const SizedBox(height: 10),
                TextField(
                  controller: sessionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم المحاضرة أو الجلسة الحالية',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('فتح الكاميرا لمسح أكواد الطلاب', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
                    onPressed: () => _openAdminAttendanceScanner(sessionCtrl.text.trim()),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 36),

          const Text('📅 إضافة محاضرة إلى الجدول', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: selectedDay,
            decoration: const InputDecoration(labelText: 'اليوم', border: OutlineInputBorder()),
            items: ['السبت', 'الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس']
                .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                .toList(),
            onChanged: (v) => setInnerState(() => selectedDay = v ?? 'السبت'),
          ),
          const SizedBox(height: 8),
          TextField(controller: orderCtrl, decoration: const InputDecoration(labelText: 'ترتيب المحاضرة', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: timeCtrl, decoration: const InputDecoration(labelText: 'الوقت', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: subjCtrl, decoration: const InputDecoration(labelText: 'اسم المادة', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: hallCtrl, decoration: const InputDecoration(labelText: 'القاعة', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: docCtrl, decoration: const InputDecoration(labelText: 'اسم الدكتور', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () async {
              if (subjCtrl.text.trim().isEmpty) return;
              setState(() => _isLoading = true);
              try {
                await _client.from('schedule').insert({
                  'day_name': selectedDay,
                  'lecture_order': orderCtrl.text.trim(),
                  'time_range': timeCtrl.text.trim(),
                  'subject_name': subjCtrl.text.trim(),
                  'hall': hallCtrl.text.trim(),
                  'doctor_name': docCtrl.text.trim(),
                });
                _showMsg('تمت إضافة المحاضرة للجدول');
              } catch (_) {
                _showMsg('فشل إضافة المحاضرة', isError: true);
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            child: const Text('إضافة للجدول'),
          ),
          const Divider(height: 36),
          const Text('✅ آخر الطلاب المسجلين حضورهم', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
          const SizedBox(height: 8),
          if (_attendance.isEmpty)
            const Text('لا توجد سجلات حضور حديثة', style: TextStyle(color: Colors.grey))
          else
            ..._attendance.map((a) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text(a['full_name'] ?? ''),
                  subtitle: Text('رقم القيد: ${a['student_id']} • الجلسة: ${a['session_code'] ?? ''}'),
                )),
        ],
      ),
    );
  }

  // كاميرا المندوب المستمرة لمسح أكواد الطلاب واحداً تلو الآخر
  void _openAdminAttendanceScanner(String sessionName) {
    final Set<String> scannedInSession = {};
    final String session = sessionName.isEmpty ? 'جلسة عامة' : sessionName;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('تحضير: $session')),
          body: MobileScanner(
            onDetect: (capture) async {
              final barcodes = capture.barcodes;
              if (barcodes.isEmpty || barcodes.first.rawValue == null) return;
              final raw = barcodes.first.rawValue!;

              String studentId = raw;
              String studentName = 'طالب';
              try {
                final decoded = jsonDecode(raw);
                studentId = decoded['id']?.toString() ?? raw;
                studentName = decoded['name']?.toString() ?? 'طالب';
              } catch (_) {}

              if (scannedInSession.contains(studentId)) return;
              scannedInSession.add(studentId);

              try {
                await _client.from('attendance').insert({
                  'student_id': studentId,
                  'full_name': studentName,
                  'session_code': session,
                });
                _showMsg('✅ تم تحضير: $studentName ($studentId)');
                _fetchInitialData();
              } catch (_) {
                scannedInSession.remove(studentId);
                _showMsg('تعذر تسجيل $studentName، تأكد من الإنترنت', isError: true);
              }
            },
          ),
        ),
      ),
    );
  }

  // 5. تبويب تغيير الرمز السري للإدارة
  Widget _buildChangePinTab() {
    final newPinCtrl = TextEditingController();
    final confirmPinCtrl = TextEditingController();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🔐 تغيير الرمز السري للوحة الإدارة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
          const SizedBox(height: 8),
          const Text('الرمز الافتراضي هو 3939. يمكنك تغييره هنا لرمز خاص بك لا يعرفه إلا المشرفون.', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 20),
          TextField(
            controller: newPinCtrl,
            keyboardType: TextInputType.number,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'الرمز السري الجديد', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: confirmPinCtrl,
            keyboardType: TextInputType.number,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'تأكيد الرمز السري الجديد', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FD1C5), foregroundColor: Colors.black),
              onPressed: () async {
                final p1 = newPinCtrl.text.trim();
                final p2 = confirmPinCtrl.text.trim();
                if (p1.length < 4) {
                  _showMsg('يجب أن يتكون الرمز من 4 أرقام على الأقل', isError: true);
                  return;
                }
                if (p1 != p2) {
                  _showMsg('الرمزان غير متطابقين', isError: true);
                  return;
                }
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('admin_pin', p1);
                newPinCtrl.clear();
                confirmPinCtrl.clear();
                _showMsg('تم تحديث الرمز السري للوحة الإدارة بنجاح');
              },
              child: const Text('حفظ الرمز السري الجديد', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
