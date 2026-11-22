import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_prefs.dart';
import 'subject_screen.dart';
import 'admin_screen.dart';
import 'gpa_screen.dart';
import 'directory_screen.dart';
import 'startup_manager.dart';
import 'notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  String _studentName = '';
  String _studentId = '';
  String _universityEmail = '';
  bool _isAdmin = false;
  bool _isSyncing = false;
  String _urgentBanner = '';

  List<dynamic> _subjects = [];
  List<dynamic> _schedule = [];
  List<dynamic> _assignments = [];
  List<dynamic> _notifications = [];
  List<dynamic> _myAttendance = [];
  List<dynamic> _announcements = [];

  final PageController _bannerPageCtrl = PageController();
  int _currentBannerPage = 0;
  bool _bannerDismissed = false;
  Timer? _bannerTimer;

  final List<String> _days = ['السبت', 'الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس'];
  int _selectedDayIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadLocalData();
    _syncWithCloud(silent: true);
    _startBannerAutoSlide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        StartupManager.checkOnStartup(context);
      }
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerPageCtrl.dispose();
    super.dispose();
  }

  String _formattedTodayDate() {
    final now = DateTime.now();
    if (AppPrefs.isEnglish) {
      const weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${weekDays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}';
    } else {
      const weekDays = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
      const months = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
      return '${weekDays[now.weekday - 1]}، ${now.day} ${months[now.month - 1]}';
    }
  }

  void _startBannerAutoSlide() {
    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _announcements.length <= 1 || _bannerDismissed) return;
      if (_bannerPageCtrl.hasClients) {
        final next = (_currentBannerPage + 1) % _announcements.length;
        _bannerPageCtrl.animateToPage(
          next,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _studentName = prefs.getString('full_name') ?? 'طالب صيدلة';
      _studentId = prefs.getString('student_id') ?? '';
      _universityEmail = prefs.getString('university_email') ?? '';
      _isAdmin = prefs.getBool('is_admin') ?? false;
      _urgentBanner = prefs.getString('cache_urgent_banner') ?? '';

      _subjects = jsonDecode(prefs.getString('cache_subjects') ?? '[]');
      _schedule = jsonDecode(prefs.getString('cache_schedule') ?? '[]');
      _assignments = jsonDecode(prefs.getString('cache_assignments') ?? '[]');
      _notifications = jsonDecode(prefs.getString('cache_notifications') ?? '[]');
      _myAttendance = jsonDecode(prefs.getString('cache_my_attendance') ?? '[]');
      _announcements = jsonDecode(prefs.getString('cache_announcements') ?? '[]');
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

      List<dynamic> announcementsData = _announcements;
      try {
        announcementsData = await client
            .from('announcements')
            .select()
            .eq('is_active', true)
            .order('created_at', ascending: false);
      } catch (_) {}

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
      String cloudEmail = _universityEmail;
      List<dynamic> attendanceData = _myAttendance;
      if (_studentId.isNotEmpty) {
        final me = await client
            .from('students')
            .select('is_admin, university_email')
            .eq('student_id', _studentId)
            .maybeSingle();
        if (me != null) {
          cloudAdmin = me['is_admin'] ?? false;
          if (me['university_email'] != null) {
            cloudEmail = me['university_email'].toString();
          }
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
      await prefs.setString('university_email', cloudEmail);
      await prefs.setString('cache_urgent_banner', bannerText);
      await prefs.setString('cache_subjects', jsonEncode(subjectsData));
      await prefs.setString('cache_schedule', jsonEncode(scheduleData));
      await prefs.setString('cache_assignments', jsonEncode(assignmentsData));
      await prefs.setString('cache_notifications', jsonEncode(notificationsData));
      await prefs.setString('cache_my_attendance', jsonEncode(attendanceData));
      await prefs.setString('cache_announcements', jsonEncode(announcementsData));

      if (!mounted) return;
      setState(() {
        _isAdmin = cloudAdmin;
        _universityEmail = cloudEmail;
        _urgentBanner = bannerText;
        _subjects = subjectsData;
        _schedule = scheduleData;
        _assignments = assignmentsData;
        _notifications = notificationsData;
        _myAttendance = attendanceData;
        _announcements = announcementsData;
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

  Widget _wrapWithWallpaper(Widget child) {
    if (AppPrefs.wallpaperType == 'none') return child;

    Widget bgLayer;
    if (AppPrefs.wallpaperType == 'preset') {
      List<Color> colors;
      switch (AppPrefs.wallpaperValue) {
        case 'gradient_blue':
          colors = [const Color(0xFF0F172A), const Color(0xFF1E3A8A), const Color(0xFF0F172A)];
          break;
        case 'gradient_emerald':
          colors = [const Color(0xFF022C22), const Color(0xFF065F46), const Color(0xFF042F2E)];
          break;
        case 'gradient_royal':
          colors = [const Color(0xFF1E1B4B), const Color(0xFF312E81), const Color(0xFF0F172A)];
          break;
        default:
          colors = [const Color(0xFF042F2E), const Color(0xFF115E59), const Color(0xFF0F172A)];
      }
      bgLayer = Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        ),
      );
    } else if (AppPrefs.wallpaperType == 'gallery' && AppPrefs.wallpaperValue.isNotEmpty) {
      bgLayer = kIsWeb
          ? Image.network(AppPrefs.wallpaperValue, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink())
          : Image.file(File(AppPrefs.wallpaperValue), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink());
    } else {
      return child;
    }

    final overlayColor = AppPrefs.isDark
        ? Colors.black.withOpacity(AppPrefs.wallpaperDim)
        : Colors.white.withOpacity(AppPrefs.wallpaperDim);

    return Stack(
      fit: StackFit.expand,
      children: [
        bgLayer,
        Container(color: overlayColor),
        child,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppPrefs.settingsNotifier,
      builder: (context, _, __) {
        final cardBg = Theme.of(context).cardColor;
        final accent = Theme.of(context).colorScheme.primary;

        final pages = [
          _buildDashboardTab(cardBg, accent),
          _buildScheduleTab(cardBg, accent),
          _buildAssignmentsTab(cardBg),
        ];

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            if (_currentIndex != 0) {
              setState(() => _currentIndex = 0);
              return;
            }
            await StartupManager.showExitDialog(context);
          },
          child: _wrapWithWallpaper(
            Scaffold(
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
            ),
          ),
        );
      },
    );
  }

  Widget _buildDashboardTab(Color cardBg, Color accent) {
    final borderCol = Colors.grey.withOpacity(0.2);
    final radius = AppPrefs.cardRadius;
    final orderedSubjects = AppPrefs.applySubjectOrder(_subjects);

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
                borderRadius: BorderRadius.circular(radius),
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppPrefs.tr('مرحباً بك،', 'Welcome,'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    Text(
                      _studentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => setState(() => _currentIndex = 1),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderCol),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 13, color: accent),
                      const SizedBox(width: 6),
                      Text(
                        _formattedTodayDate(),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                _topActionBtn(Icons.support_agent_rounded, AppPrefs.tr('الدعم والتواصل', 'Support'), () => _openSupportContactsSheet(), cardBg, accent),
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
          const SizedBox(height: 14),

          if (AppPrefs.showAnnouncements) ...[
            _buildAnnouncementsSection(cardBg, accent, radius),
            const SizedBox(height: 14),
          ],

          if (AppPrefs.showQuickCards) ...[
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _currentIndex = 1),
                    borderRadius: BorderRadius.circular(radius),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(radius),
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
                    borderRadius: BorderRadius.circular(radius),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(radius),
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
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(AppPrefs.tr('المواد الدراسية', 'Subjects'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                tooltip: AppPrefs.subjectsGrid ? AppPrefs.tr('عرض كلائحة', 'List View') : AppPrefs.tr('عرض كشبكة', 'Grid View'),
                icon: Icon(AppPrefs.subjectsGrid ? Icons.view_list_rounded : Icons.grid_view_rounded, color: accent),
                onPressed: () => AppPrefs.setSubjectsGrid(!AppPrefs.subjectsGrid),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (orderedSubjects.isEmpty)
            Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(AppPrefs.tr('اسحب للأسفل لمزامنة المواد لأول مرة', 'Pull down to sync subjects'))))
          else if (AppPrefs.subjectsGrid)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.15,
              ),
              itemCount: orderedSubjects.length,
              itemBuilder: (_, idx) {
                final subj = orderedSubjects[idx];
                Color subjColor = const Color(0xFF2B6CB0);
                try {
                  final hex = (subj['color_hex'] ?? '#2B6CB0').toString().replaceAll('#', '');
                  subjColor = Color(int.parse('FF$hex', radix: 16));
                } catch (_) {}

                return InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SubjectScreen(subject: subj, defaultColor: subjColor)),
                    );
                  },
                  borderRadius: BorderRadius.circular(radius),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(color: borderCol),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(color: subjColor.withOpacity(0.18), borderRadius: BorderRadius.circular(12)),
                          child: Icon(Icons.menu_book_rounded, color: subjColor, size: 26),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          subj['name'] ?? '',
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                );
              },
            )
          else
            ...orderedSubjects.map((subj) {
              Color subjColor = const Color(0xFF2B6CB0);
              try {
                final hex = (subj['color_hex'] ?? '#2B6CB0').toString().replaceAll('#', '');
                subjColor = Color(int.parse('FF$hex', radix: 16));
              } catch (_) {}

              return Card(
                color: cardBg,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
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

  Widget _buildAnnouncementsSection(Color cardBg, Color accent, double radius) {
    if (_announcements.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF1D4ED8), Color(0xFF0D9488)]),
          borderRadius: BorderRadius.circular(radius),
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
      );
    }

    if (_bannerDismissed) {
      return Align(
        alignment: Alignment.centerRight,
        child: ActionChip(
          avatar: Icon(Icons.campaign_rounded, size: 16, color: accent),
          label: Text(AppPrefs.tr('إظهار الإعلانات (${_announcements.length})', 'Show Announcements (${_announcements.length})'), style: const TextStyle(fontSize: 12)),
          onPressed: () => setState(() => _bannerDismissed = false),
        ),
      );
    }

    return SizedBox(
      height: 155,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: PageView.builder(
              controller: _bannerPageCtrl,
              itemCount: _announcements.length,
              onPageChanged: (idx) => setState(() => _currentBannerPage = idx),
              itemBuilder: (_, idx) {
                final item = _announcements[idx];
                final imgUrl = (item['image_url'] ?? '').toString();
                final title = (item['title'] ?? '').toString();

                return GestureDetector(
                  onTap: () => _showAnnouncementFullModal(item),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imgUrl.isNotEmpty && !AppPrefs.dataSaver)
                        Image.network(
                          imgUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(colors: [Color(0xFF1E3A8A), Color(0xFF0D9488)]),
                            ),
                            child: const Center(child: Icon(Icons.campaign_rounded, size: 48, color: Colors.white70)),
                          ),
                        )
                      else
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(colors: [Color(0xFF1E3A8A), Color(0xFF0D9488)]),
                          ),
                          child: const Center(child: Icon(Icons.campaign_rounded, size: 48, color: Colors.white70)),
                        ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withOpacity(0.82)],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 22,
                        right: 14,
                        left: 14,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: GestureDetector(
              onTap: () => setState(() => _bannerDismissed = true),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
              ),
            ),
          ),
          if (_announcements.length > 1)
            Positioned(
              bottom: 7,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_announcements.length, (i) {
                  final active = i == _currentBannerPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active ? accent : Colors.white54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  void _showAnnouncementFullModal(Map<String, dynamic> item) {
    final imgUrl = (item['image_url'] ?? '').toString();
    final title = (item['title'] ?? '').toString();
    final desc = (item['description'] ?? '').toString();
    final actionUrl = (item['action_url'] ?? '').toString().trim();
    final accent = Theme.of(context).colorScheme.primary;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                style: IconButton.styleFrom(backgroundColor: Colors.white24),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            const SizedBox(height: 8),
            if (imgUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                  child: Image.network(imgUrl, fit: BoxFit.contain),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                desc,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
              ),
            ],
            if (actionUrl.isNotEmpty) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(AppPrefs.tr('فتح الرابط', 'Open Link'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  onPressed: () => launchUrl(Uri.parse(actionUrl), mode: LaunchMode.externalApplication),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openSupportContactsSheet() {
    final cardBg = Theme.of(context).cardColor;
    final accent = Theme.of(context).colorScheme.primary;

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => FutureBuilder(
          future: Supabase.instance.client
              .from('support_contacts')
              .select()
              .eq('is_active', true)
              .order('sort_order'),
          builder: (context, snapshot) {
            final contacts = (snapshot.data as List<dynamic>?) ?? [];
            final amISupport = _isAdmin || contacts.any((c) => c['student_id'].toString() == _studentId);

            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Icon(Icons.support_agent_rounded, color: accent, size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        AppPrefs.tr('التواصل المباشر مع المطورين والمناديب', 'Direct Support & Developers'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  AppPrefs.tr(
                    'اختر الشخص المناسب لبدء محادثة خاصة مباشرة داخل التطبيق لطرح استفسارك أو اقتراحك:',
                    'Select a contact to start a private in-app chat:',
                  ),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (amISupport) ...[
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.inbox_rounded),
                    label: Text(AppPrefs.tr('صندوق رسائل الطلاب الواردة (للمطورين والمناديب)', 'Incoming Student Messages'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SupportInboxScreen(myId: _studentId, myName: _studentName, isAdmin: _isAdmin),
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 16),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                else if (contacts.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        AppPrefs.tr('لم يتم إضافة جهات تواصل بعد من لوحة الإدارة.', 'No support contacts added yet.'),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ...contacts.map((c) {
                    final targetId = (c['student_id'] ?? '').toString();
                    final name = (c['display_name'] ?? '').toString();
                    final role = (c['role_title'] ?? '').toString();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: accent.withOpacity(0.2),
                          child: Icon(Icons.person_rounded, color: accent),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(role, style: TextStyle(color: accent, fontSize: 12)),
                        trailing: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent.withOpacity(0.18),
                            foregroundColor: accent,
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.chat_rounded, size: 16),
                          label: Text(AppPrefs.tr('مراسلة', 'Chat'), style: const TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DirectSupportChatScreen(
                                  myId: _studentId,
                                  myName: _studentName,
                                  peerId: targetId,
                                  peerName: name,
                                  peerRole: role,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cardBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.withOpacity(0.22)),
                ),
                child: Icon(icon, size: 20, color: accent),
              ),
              if (badge > 0)
                Positioned(
                  top: -3,
                  left: -3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppPrefs.cardRadius)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppPrefs.cardRadius)),
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
    final emailCtrl = TextEditingController(text: _universityEmail);
    bool savingEmail = false;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (ctx, setSettingsState) {
            final accent = Theme.of(ctx).colorScheme.primary;
            final cardBg = Theme.of(ctx).cardColor;
            final orderedList = AppPrefs.applySubjectOrder(_subjects);

            return Scaffold(
              appBar: AppBar(title: Text(AppPrefs.tr('الإعدادات والتخصيص', 'Settings & Customization'))),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  FutureBuilder<SharedPreferences>(
                    future: SharedPreferences.getInstance(),
                    builder: (context, snap) {
                      final prefs = snap.data;
                      final masterOn = prefs?.getBool('notif_master_enabled') ?? true;
                      final academicOn = prefs?.getBool('notif_academic_enabled') ?? true;
                      final supportOn = prefs?.getBool('notif_support_enabled') ?? true;
                      final chatMuted = prefs?.getBool('notif_batch_chat_muted') ?? false;

                      return Card(
                        color: cardBg,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ExpansionTile(
                          leading: Icon(Icons.notifications_active_rounded, color: accent),
                          title: Text(AppPrefs.tr('إعدادات الإشعارات', 'Notification Settings'), style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(AppPrefs.tr('التحكم في إشعارات الدفعة، التكاليف، والدردشة', 'Alerts, assignments & chat mute'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(AppPrefs.tr('تفعيل جميع الإشعارات', 'Enable All Notifications'), style: const TextStyle(fontWeight: FontWeight.bold)),
                              value: masterOn,
                              onChanged: prefs == null
                                  ? null
                                  : (v) async {
                                      await prefs.setBool('notif_master_enabled', v);
                                      unawaited(NotificationService.syncUserTags());
                                      setSettingsState(() {});
                                    },
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(AppPrefs.tr('إشعارات الدفعة والتكاليف والجدول', 'Batch Alerts, Tasks & Schedule')),
                              value: academicOn,
                              onChanged: (prefs == null || !masterOn)
                                  ? null
                                  : (v) async {
                                      await prefs.setBool('notif_academic_enabled', v);
                                      unawaited(NotificationService.syncUserTags());
                                      setSettingsState(() {});
                                    },
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(AppPrefs.tr('إشعارات الرسائل الخاصة والدعم', 'Direct Support Messages')),
                              value: supportOn,
                              onChanged: (prefs == null || !masterOn)
                                  ? null
                                  : (v) async {
                                      await prefs.setBool('notif_support_enabled', v);
                                      unawaited(NotificationService.syncUserTags());
                                      setSettingsState(() {});
                                    },
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(AppPrefs.tr('كتم إشعارات دردشة الدفعة', 'Mute Batch Chat Notifications')),
                              value: chatMuted,
                              onChanged: (prefs == null || !masterOn)
                                  ? null
                                  : (v) async {
                                      await prefs.setBool('notif_batch_chat_muted', v);
                                      unawaited(NotificationService.syncUserTags());
                                      setSettingsState(() {});
                                    },
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                icon: Icon(Icons.settings_applications_rounded, color: accent),
                                label: Text(AppPrefs.tr('فتح أذونات الإشعارات في إعدادات الهاتف', 'Open System Notification Settings')),
                                onPressed: () => openAppSettings(),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),

                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.verified_user_rounded, color: accent),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_studentName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    Text('${AppPrefs.tr('رقم القيد:', 'Student ID:')} $_studentId', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                              ),
                              if (_universityEmail.isNotEmpty)
                                Chip(
                                  backgroundColor: Colors.green.withOpacity(0.18),
                                  label: Text(AppPrefs.tr('مرتبط ✓', 'Linked ✓'), style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                          const Divider(height: 24),
                          Text(
                            AppPrefs.tr('ربط البريد الجامعي (لنظام الكلية والتحضير)', 'Link University Email'),
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: accent),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: emailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: InputDecoration(
                                    hintText: 'example@su.edu.ye',
                                    isDense: true,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
                                onPressed: savingEmail
                                    ? null
                                    : () async {
                                        final em = emailCtrl.text.trim();
                                        if (em.isEmpty || !em.contains('@')) {
                                          ScaffoldMessenger.of(ctx).showSnackBar(
                                            SnackBar(content: Text(AppPrefs.tr('يرجى إدخال بريد إلكتروني صحيح', 'Enter a valid email')), backgroundColor: Colors.red),
                                          );
                                          return;
                                        }
                                        setSettingsState(() => savingEmail = true);
                                        try {
                                          await Supabase.instance.client
                                              .from('students')
                                              .update({'university_email': em})
                                              .eq('student_id', _studentId);
                                          final prefs = await SharedPreferences.getInstance();
                                          await prefs.setString('university_email', em);
                                          setState(() => _universityEmail = em);
                                          setSettingsState(() => savingEmail = false);
                                          if (!ctx.mounted) return;
                                          ScaffoldMessenger.of(ctx).showSnackBar(
                                            SnackBar(content: Text(AppPrefs.tr('تم ربط البريد الجامعي بنجاح ✓', 'University email linked ✓')), backgroundColor: Colors.teal),
                                          );
                                        } catch (_) {
                                          setSettingsState(() => savingEmail = false);
                                          if (!ctx.mounted) return;
                                          ScaffoldMessenger.of(ctx).showSnackBar(
                                            SnackBar(content: Text(AppPrefs.tr('تعذر الحفظ (قد يكون البريد مستخدماً لطالب آخر)', 'Failed to save email')), backgroundColor: Colors.red),
                                          );
                                        }
                                      },
                                child: savingEmail
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                    : Text(AppPrefs.tr('ربط', 'Link'), style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ExpansionTile(
                      leading: Icon(Icons.wallpaper_rounded, color: accent),
                      title: Text(AppPrefs.tr('الخلفيات والسمات', 'Wallpapers & Themes'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(AppPrefs.tr('الألوان، خلفيات التطبيق، أو صورة من المعرض', 'Theme colors, presets, or gallery'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(AppPrefs.tr('سمة الألوان:', 'Color Theme:'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _themeChip(ctx, setSettingsState, 'dark', AppPrefs.tr('داكن', 'Dark'), const Color(0xFF181B20)),
                            _themeChip(ctx, setSettingsState, 'amoled', 'AMOLED', Colors.black),
                            _themeChip(ctx, setSettingsState, 'pharmacy', AppPrefs.tr('صيدلاني', 'Pharmacy'), const Color(0xFF0F2927)),
                            _themeChip(ctx, setSettingsState, 'light', AppPrefs.tr('فاتح', 'Light'), Colors.white),
                          ],
                        ),
                        const Divider(height: 24),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(AppPrefs.tr('خلفية الواجهة:', 'App Wallpaper:'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: Text(AppPrefs.tr('بدون خلفية', 'None')),
                              selected: AppPrefs.wallpaperType == 'none',
                              onSelected: (_) async {
                                await AppPrefs.setWallpaper('none', '');
                                setSettingsState(() {});
                              },
                            ),
                            ChoiceChip(
                              label: Text(AppPrefs.tr('تدرج تركوازي', 'Teal')),
                              selected: AppPrefs.wallpaperValue == 'gradient_teal',
                              onSelected: (_) async {
                                await AppPrefs.setWallpaper('preset', 'gradient_teal');
                                setSettingsState(() {});
                              },
                            ),
                            ChoiceChip(
                              label: Text(AppPrefs.tr('تدرج أزرق', 'Blue')),
                              selected: AppPrefs.wallpaperValue == 'gradient_blue',
                              onSelected: (_) async {
                                await AppPrefs.setWallpaper('preset', 'gradient_blue');
                                setSettingsState(() {});
                              },
                            ),
                            ChoiceChip(
                              label: Text(AppPrefs.tr('تدرج زمردي', 'Emerald')),
                              selected: AppPrefs.wallpaperValue == 'gradient_emerald',
                              onSelected: (_) async {
                                await AppPrefs.setWallpaper('preset', 'gradient_emerald');
                                setSettingsState(() {});
                              },
                            ),
                            ActionChip(
                              avatar: Icon(Icons.photo_library_rounded, size: 16, color: accent),
                              label: Text(AppPrefs.tr('من المعرض', 'From Gallery')),
                              onPressed: () async {
                                final picker = ImagePicker();
                                final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                                if (picked != null) {
                                  await AppPrefs.setWallpaper('gallery', picked.path);
                                  setSettingsState(() {});
                                }
                              },
                            ),
                          ],
                        ),
                        if (AppPrefs.wallpaperType != 'none') ...[
                          const SizedBox(height: 12),
                          Text('${AppPrefs.tr('درجة تعتيم الخلفية:', 'Wallpaper Dimming:')} ${(AppPrefs.wallpaperDim * 100).round()}%', style: const TextStyle(fontSize: 12)),
                          Slider(
                            value: AppPrefs.wallpaperDim,
                            min: 0.2,
                            max: 0.95,
                            onChanged: (v) async {
                              await AppPrefs.setWallpaperDim(v);
                              setSettingsState(() {});
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ExpansionTile(
                      leading: Icon(Icons.font_download_rounded, color: accent),
                      title: Text(AppPrefs.tr('الخط والحجم', 'Font & Size'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(AppPrefs.tr('تلقائي، النسخ، الرقعة، القاهرة، تجوال، المراعي', 'Font family & text scale'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            AppPrefs.tr('معاينة النص: دفعة 39 صيدلة إكلينيكية - جامعة صنعاء', 'Text Preview: Batch 39 Clinical Pharmacy'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _fontChip(setSettingsState, 'system', AppPrefs.tr('تلقائي', 'System')),
                            _fontChip(setSettingsState, 'cairo', AppPrefs.tr('القاهرة', 'Cairo')),
                            _fontChip(setSettingsState, 'tajawal', AppPrefs.tr('تجوال', 'Tajawal')),
                            _fontChip(setSettingsState, 'amiri', AppPrefs.tr('النسخ (أميري)', 'Naskh (Amiri)')),
                            _fontChip(setSettingsState, 'ruqaa', AppPrefs.tr('الرقعة', 'Ruqaa')),
                            _fontChip(setSettingsState, 'almarai', AppPrefs.tr('المراعي', 'Almarai')),
                          ],
                        ),
                        const Divider(height: 24),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(AppPrefs.tr('حجم الخط:', 'Font Size:'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<double>(
                          segments: [
                            ButtonSegment(value: 0.85, label: Text(AppPrefs.tr('صغير', 'S'))),
                            ButtonSegment(value: 1.0, label: Text(AppPrefs.tr('متوسط', 'M'))),
                            ButtonSegment(value: 1.15, label: Text(AppPrefs.tr('كبير', 'L'))),
                            ButtonSegment(value: 1.30, label: Text(AppPrefs.tr('ضخم', 'XL'))),
                          ],
                          selected: {AppPrefs.fontScale},
                          onSelectionChanged: (sel) async {
                            await AppPrefs.setFontScale(sel.first);
                            setSettingsState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ExpansionTile(
                      leading: Icon(Icons.reorder_rounded, color: accent),
                      title: Text(AppPrefs.tr('المواد وطريقة العرض', 'Subjects Layout & Order'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(AppPrefs.tr('لائحة أو شبكة + ترتيب المواد بالأسهم', 'Grid/List & Reorder subjects'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(AppPrefs.tr('طريقة العرض في الرئيسية:', 'Home Layout:'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            SegmentedButton<bool>(
                              segments: [
                                ButtonSegment(value: false, icon: const Icon(Icons.view_list_rounded, size: 16), label: Text(AppPrefs.tr('لائحة', 'List'))),
                                ButtonSegment(value: true, icon: const Icon(Icons.grid_view_rounded, size: 16), label: Text(AppPrefs.tr('شبكة', 'Grid'))),
                              ],
                              selected: {AppPrefs.subjectsGrid},
                              onSelectionChanged: (sel) async {
                                await AppPrefs.setSubjectsGrid(sel.first);
                                setSettingsState(() {});
                              },
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(AppPrefs.tr('ترتيب المواد:', 'Reorder Subjects:'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            TextButton(
                              onPressed: () async {
                                await AppPrefs.setSubjectOrder([]);
                                setSettingsState(() {});
                              },
                              child: Text(AppPrefs.tr('استعادة الافتراضي', 'Reset Order'), style: TextStyle(color: accent, fontSize: 12)),
                            ),
                          ],
                        ),
                        ...List.generate(orderedList.length, (index) {
                          final subj = orderedList[index];
                          final isFirst = index == 0;
                          final isLast = index == orderedList.length - 1;
                          Color subjColor = accent;
                          try {
                            final hex = (subj['color_hex'] ?? '#2B6CB0').toString().replaceAll('#', '');
                            subjColor = Color(int.parse('FF$hex', radix: 16));
                          } catch (_) {}

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.menu_book_rounded, color: subjColor, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    subj['name'] ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.arrow_drop_up_rounded, size: 30, color: isFirst ? Colors.grey.withOpacity(0.3) : Colors.white),
                                  onPressed: isFirst
                                      ? null
                                      : () async {
                                          final ids = orderedList.map((e) => (e['id'] ?? '').toString()).toList();
                                          final temp = ids[index - 1];
                                          ids[index - 1] = ids[index];
                                          ids[index] = temp;
                                          await AppPrefs.setSubjectOrder(ids);
                                          setSettingsState(() {});
                                        },
                                ),
                                IconButton(
                                  icon: Icon(Icons.arrow_drop_down_rounded, size: 30, color: isLast ? Colors.grey.withOpacity(0.3) : Colors.white),
                                  onPressed: isLast
                                      ? null
                                      : () async {
                                          final ids = orderedList.map((e) => (e['id'] ?? '').toString()).toList();
                                          final temp = ids[index + 1];
                                          ids[index + 1] = ids[index];
                                          ids[index] = temp;
                                          await AppPrefs.setSubjectOrder(ids);
                                          setSettingsState(() {});
                                        },
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ExpansionTile(
                      leading: Icon(Icons.tune_rounded, color: accent),
                      title: Text(AppPrefs.tr('الواجهة والأمان واللغة', 'UI, Security & Language'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(AppPrefs.tr('استدارة الحواف، قفل التطبيق، اللغة، توفير البيانات', 'Corners, PIN lock, language'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.language, color: Colors.purpleAccent),
                          title: Text(AppPrefs.tr('لغة الواجهة', 'App Language')),
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
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(AppPrefs.tr('استدارة زوايا البطاقات:', 'Card Corner Radius:'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<double>(
                          segments: [
                            ButtonSegment(value: 6.0, label: Text(AppPrefs.tr('حادة', 'Sharp'))),
                            ButtonSegment(value: 14.0, label: Text(AppPrefs.tr('متوسطة', 'Medium'))),
                            ButtonSegment(value: 22.0, label: Text(AppPrefs.tr('دائرية', 'Round'))),
                          ],
                          selected: {AppPrefs.cardRadius},
                          onSelectionChanged: (sel) async {
                            await AppPrefs.setCardRadius(sel.first);
                            setSettingsState(() {});
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(AppPrefs.tr('إظهار شريط الإعلانات في الرئيسية', 'Show Announcements Banner')),
                          value: AppPrefs.showAnnouncements,
                          onChanged: (v) async {
                            await AppPrefs.setTogglePref('show_announcements', v);
                            setSettingsState(() {});
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(AppPrefs.tr('إظهار بطاقتي الجدول والحضور السريعة', 'Show Schedule & Attendance Cards')),
                          value: AppPrefs.showQuickCards,
                          onChanged: (v) async {
                            await AppPrefs.setTogglePref('show_quick_cards', v);
                            setSettingsState(() {});
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(AppPrefs.tr('وضع توفير البيانات (عدم تحميل صور الإعلانات)', 'Data Saver Mode')),
                          value: AppPrefs.dataSaver,
                          onChanged: (v) async {
                            await AppPrefs.setTogglePref('data_saver', v);
                            setSettingsState(() {});
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: Icon(Icons.lock_outline_rounded, color: accent),
                          title: Text(AppPrefs.tr('قفل التطبيق برمز مرور (PIN)', 'Lock App with PIN')),
                          subtitle: Text(AppPrefs.pinEnabled ? AppPrefs.tr('مفعّل', 'Enabled') : AppPrefs.tr('غير مفعّل', 'Disabled')),
                          value: AppPrefs.pinEnabled,
                          onChanged: (val) async {
                            if (val) {
                              final pinCtrl = TextEditingController();
                              showDialog(
                                context: ctx,
                                builder: (dCtx) => AlertDialog(
                                  title: Text(AppPrefs.tr('تعيين رمز مرور (PIN)', 'Set App PIN')),
                                  content: TextField(
                                    controller: pinCtrl,
                                    keyboardType: TextInputType.number,
                                    maxLength: 6,
                                    obscureText: true,
                                    textAlign: TextAlign.center,
                                    decoration: InputDecoration(hintText: AppPrefs.tr('أدخل 4-6 أرقام', 'Enter 4-6 digits')),
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(AppPrefs.tr('إلغاء', 'Cancel'))),
                                    ElevatedButton(
                                      onPressed: () async {
                                        if (pinCtrl.text.trim().length >= 4) {
                                          await AppPrefs.setAppPin(true, pinCtrl.text.trim());
                                          if (dCtx.mounted) Navigator.pop(dCtx);
                                          setSettingsState(() {});
                                        }
                                      },
                                      child: Text(AppPrefs.tr('حفظ', 'Save')),
                                    ),
                                  ],
                                ),
                              );
                            } else {
                              await AppPrefs.setAppPin(false, '');
                              setSettingsState(() {});
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ExpansionTile(
                      leading: Icon(Icons.backup_rounded, color: accent),
                      title: Text(AppPrefs.tr('النسخ الاحتياطي وإعادة الضبط', 'Backup & Reset'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(AppPrefs.tr('تصدير أو استيراد الإعدادات وترتيب المواد', 'Export/Import settings'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.upload_file_rounded, color: Colors.teal),
                          title: Text(AppPrefs.tr('تصدير ومشاركة نسخة احتياطية', 'Export & Share Backup')),
                          onTap: () async {
                            final jsonStr = AppPrefs.exportBackupJson();
                            if (kIsWeb) {
                              await Clipboard.setData(ClipboardData(text: jsonStr));
                              if (!ctx.mounted) return;
                              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(AppPrefs.tr('تم نسخ ملف النسخة الاحتياطية للحافظة', 'Backup copied to clipboard'))));
                            } else {
                              final dir = await getTemporaryDirectory();
                              final file = File('${dir.path}/IQ_Pharmacy39_Backup.json');
                              await file.writeAsString(jsonStr);
                              await Share.shareXFiles([XFile(file.path)], text: 'نسخة احتياطية لإعدادات تطبيق IQ_Pharmacy39');
                            }
                          },
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.download_for_offline_rounded, color: Colors.blueAccent),
                          title: Text(AppPrefs.tr('استيراد نسخة احتياطية (.json)', 'Import Backup (.json)')),
                          onTap: () async {
                            final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
                            if (result != null && result.files.isNotEmpty) {
                              final bytes = result.files.first.bytes;
                              String content = '';
                              if (bytes != null) {
                                content = utf8.decode(bytes);
                              } else if (result.files.first.path != null && !kIsWeb) {
                                content = await File(result.files.first.path!).readAsString();
                              }
                              final ok = await AppPrefs.importBackupJson(content);
                              setSettingsState(() {});
                              if (!ctx.mounted) return;
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(ok ? AppPrefs.tr('تمت استعادة الإعدادات بنجاح ✓', 'Backup restored ✓') : AppPrefs.tr('ملف النسخة الاحتياطية غير صالح', 'Invalid backup file')),
                                  backgroundColor: ok ? Colors.teal : Colors.red,
                                ),
                              );
                            }
                          },
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.restore_rounded, color: Colors.redAccent),
                          title: Text(AppPrefs.tr('إعادة ضبط جميع الإعدادات للافتراضي', 'Reset All Settings'), style: const TextStyle(color: Colors.redAccent)),
                          onTap: () async {
                            await AppPrefs.resetAllSettings();
                            setSettingsState(() {});
                            if (!ctx.mounted) return;
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text(AppPrefs.tr('تمت إعادة الضبط للوضع الافتراضي', 'Settings reset to defaults'))),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.sync, color: Colors.teal),
                          title: Text(AppPrefs.tr('مزامنة وتحديث البيانات الآن', 'Sync Data Now')),
                          onTap: () {
                            Navigator.pop(context);
                            _syncWithCloud(silent: false);
                          },
                        ),
                        if (_isAdmin) ...[
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.admin_panel_settings, color: Colors.orange),
                            title: Text(AppPrefs.tr('لوحة إدارة الدفعة (للمشرفين فقط)', 'Admin Dashboard (Admins Only)')),
                            subtitle: Text(AppPrefs.tr('إدارة الإعلانات، التواصل، الإشعارات، الملفات، كشوفات الحضور', 'Announcements, support, alerts, files, attendance')),
                            onTap: () => _promptAdminPassword(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _themeChip(BuildContext ctx, StateSetter setSettingsState, String preset, String label, Color color) {
    final selected = AppPrefs.themePreset == preset;
    return ChoiceChip(
      avatar: CircleAvatar(backgroundColor: color, radius: 8),
      label: Text(label),
      selected: selected,
      onSelected: (_) async {
        await AppPrefs.setThemePreset(preset);
        setSettingsState(() {});
      },
    );
  }

  Widget _fontChip(StateSetter setSettingsState, String family, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: AppPrefs.fontFamily == family,
      onSelected: (_) async {
        await AppPrefs.setFontFamily(family);
        setSettingsState(() {});
      },
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
  bool _isChatMuted = false;

  @override
  void initState() {
    super.initState();
    _nickname = widget.defaultName.split(' ').take(2).join(' ');
    _loadMuteState();
  }

  Future<void> _loadMuteState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isChatMuted = prefs.getBool('notif_batch_chat_muted') ?? false;
    });
  }

  Future<void> _toggleChatMute() async {
    final prefs = await SharedPreferences.getInstance();
    final nextVal = !_isChatMuted;
    await prefs.setBool('notif_batch_chat_muted', nextVal);
    unawaited(NotificationService.syncUserTags());
    if (!mounted) return;
    setState(() => _isChatMuted = nextVal);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nextVal
              ? AppPrefs.tr('تم كتم إشعارات دردشة الدفعة 🔕', 'Batch chat notifications muted 🔕')
              : AppPrefs.tr('تم تفعيل إشعارات دردشة الدفعة 🔔', 'Batch chat notifications unmuted 🔔'),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
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
          IconButton(
            tooltip: _isChatMuted
                ? AppPrefs.tr('إلغاء كتم إشعارات الدردشة', 'Unmute Chat')
                : AppPrefs.tr('كتم إشعارات الدردشة', 'Mute Chat'),
            icon: Icon(
              _isChatMuted ? Icons.notifications_off_rounded : Icons.notifications_active_rounded,
              color: _isChatMuted ? Colors.amber : accent,
            ),
            onPressed: _toggleChatMute,
          ),
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

class DirectSupportChatScreen extends StatefulWidget {
  final String myId;
  final String myName;
  final String peerId;
  final String peerName;
  final String peerRole;

  const DirectSupportChatScreen({
    super.key,
    required this.myId,
    required this.myName,
    required this.peerId,
    required this.peerName,
    required this.peerRole,
  });

  @override
  State<DirectSupportChatScreen> createState() => _DirectSupportChatScreenState();
}

class _DirectSupportChatScreenState extends State<DirectSupportChatScreen> {
  final TextEditingController _msgCtrl = TextEditingController();
  List<dynamic> _threadMsgs = [];
  bool _loading = true;
  bool _sending = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchMessages(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages({bool silent = false}) async {
    try {
      final data = await Supabase.instance.client
          .from('support_messages')
          .select()
          .or('and(sender_id.eq.${widget.myId},receiver_id.eq.${widget.peerId}),and(sender_id.eq.${widget.peerId},receiver_id.eq.${widget.myId})')
          .order('created_at', ascending: true);

      if (!mounted) return;
      setState(() {
        _threadMsgs = data;
        _loading = false;
      });
    } catch (_) {
      if (!silent && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendDirectMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _msgCtrl.clear();

    try {
      await Supabase.instance.client.from('support_messages').insert({
        'sender_id': widget.myId,
        'sender_name': widget.myName,
        'receiver_id': widget.peerId,
        'message': text,
      });
      await _fetchMessages(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppPrefs.tr('تعذر إرسال الرسالة، تحقق من الاتصال', 'Failed to send message')), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Theme.of(context).cardColor;
    final accent = Theme.of(context).colorScheme.primary;
    final isDark = AppPrefs.isDark;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.peerName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (widget.peerRole.isNotEmpty)
              Text(widget.peerRole, style: TextStyle(fontSize: 11, color: accent)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _threadMsgs.isEmpty
                    ? Center(
                        child: Text(
                          AppPrefs.tr('ابدأ المحادثة الخاصة الآن بكتابة رسالتك بالأسفل', 'Start your private chat below'),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _threadMsgs.length,
                        itemBuilder: (_, i) {
                          final m = _threadMsgs[i];
                          final isMe = (m['sender_id'] ?? '').toString() == widget.myId;
                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? (isDark ? const Color(0xFF1E3A5F) : const Color(0xFFCCFBF1))
                                    : cardBg,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m['sender_name'] ?? '', style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(m['message'] ?? '', style: const TextStyle(height: 1.4)),
                                ],
                              ),
                            ),
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
                      hintText: AppPrefs.tr('اكتب رسالتك الخاصة هنا...', 'Type a private message...'),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendDirectMessage(),
                  ),
                ),
                IconButton(
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.send_rounded, color: accent),
                  onPressed: _sendDirectMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SupportInboxScreen extends StatefulWidget {
  final String myId;
  final String myName;
  final bool isAdmin;

  const SupportInboxScreen({
    super.key,
    required this.myId,
    required this.myName,
    this.isAdmin = false,
  });

  @override
  State<SupportInboxScreen> createState() => _SupportInboxScreenState();
}

class _SupportInboxScreenState extends State<SupportInboxScreen> {
  static const String _ownerId = '27094070';
  bool _allowAdminsDm = false;
  bool _updatingSetting = false;
  bool _loadingInbox = true;
  List _allStudents = [];
  List _conversations = [];
  Timer? _inboxTimer;

  bool get _isOwner => widget.myId.trim() == _ownerId;
  bool get _canStartNewChat => _isOwner || (widget.isAdmin && _allowAdminsDm);

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _inboxTimer = Timer.periodic(const Duration(seconds: 4), (_) => _fetchConversations(silent: true));
  }

  @override
  void dispose() {
    _inboxTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadPermissionsAndStudents(),
      _fetchConversations(),
    ]);
  }

  Future<void> _loadPermissionsAndStudents() async {
    try {
      final client = Supabase.instance.client;
      final settingRes = await client
          .from('app_settings')
          .select('value')
          .eq('key', 'allow_admins_dm')
          .maybeSingle();

      final allow = settingRes != null && settingRes['value'].toString().toLowerCase() == 'true';

      List students = [];
      if (_isOwner || (widget.isAdmin && allow)) {
        students = await client
            .from('students')
            .select('student_id, full_name')
            .order('full_name');
      }

      if (!mounted) return;
      setState(() {
        _allowAdminsDm = allow;
        _allStudents = students;
      });
    } catch (_) {}
  }

  String _resolveStudentName(String peerId, String fallback) {
    for (var st in _allStudents) {
      if ((st['student_id'] ?? '').toString() == peerId) {
        return (st['full_name'] ?? fallback).toString();
      }
    }
    return fallback;
  }

  Future<void> _fetchConversations({bool silent = false}) async {
    try {
      final rawList = await Supabase.instance.client
          .from('support_messages')
          .select()
          .or('receiver_id.eq.${widget.myId},sender_id.eq.${widget.myId}')
          .order('created_at', ascending: false);

      final Map<String, Map<String, dynamic>> convMap = {};
      for (var m in rawList) {
        final s = (m['sender_id'] ?? '').toString();
        final r = (m['receiver_id'] ?? '').toString();
        final peerId = s == widget.myId ? r : s;
        if (!convMap.containsKey(peerId)) {
          final rawName = s == widget.myId
              ? _resolveStudentName(peerId, 'طالب ($peerId)')
              : (m['sender_name'] ?? peerId);
          convMap[peerId] = {
            'peerId': peerId,
            'peerName': rawName,
            'lastMessage': m['message'] ?? '',
          };
        }
      }

      if (!mounted) return;
      setState(() {
        _conversations = convMap.values.toList();
        _loadingInbox = false;
      });
    } catch (_) {
      if (!silent && mounted) setState(() => _loadingInbox = false);
    }
  }

  Future<void> _toggleAdminsPermission(bool value) async {
    if (!_isOwner || _updatingSetting) return;
    setState(() {
      _updatingSetting = true;
      _allowAdminsDm = value;
    });
    try {
      await Supabase.instance.client.from('app_settings').upsert({
        'key': 'allow_admins_dm',
        'value': value.toString(),
      });
      if (!mounted) return;
      setState(() => _updatingSetting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? AppPrefs.tr('تم تفعيل بدء المحادثات لبقية المشرفين ✓', 'Enabled new chats for admins ✓')
                : AppPrefs.tr('تم حصر بدء المحادثات بالمالك فقط 🔒', 'Restricted new chats to owner only 🔒'),
          ),
          backgroundColor: Colors.teal,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _allowAdminsDm = !value;
        _updatingSetting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppPrefs.tr('فشل حفظ الإعداد في قاعدة البيانات', 'Failed to update setting')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openNewStudentChatPicker() {
    final cardBg = Theme.of(context).cardColor;
    final accent = Theme.of(context).colorScheme.primary;
    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final filtered = _allStudents.where((s) {
            final id = (s['student_id'] ?? '').toString();
            final name = (s['full_name'] ?? '').toString();
            if (id == widget.myId) return false;
            if (searchQuery.isEmpty) return true;
            return name.toLowerCase().contains(searchQuery.toLowerCase()) || id.contains(searchQuery);
          }).toList();

          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            maxChildSize: 0.92,
            minChildSize: 0.5,
            expand: false,
            builder: (_, scrollCtrl) => Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    AppPrefs.tr('بدء محادثة خاصة مع طالب', 'Start Private Chat with Student'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: accent),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: AppPrefs.tr('ابحث باسم الطالب أو رقم القيد...', 'Search by name or ID...'),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (val) => setSheetState(() => searchQuery = val.trim()),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              AppPrefs.tr('لا يوجد طلاب مطابقون للبحث', 'No matching students'),
                              style: const TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollCtrl,
                            itemCount: filtered.length,
                            itemBuilder: (_, idx) {
                              final st = filtered[idx];
                              final targetId = (st['student_id'] ?? '').toString();
                              final targetName = (st['full_name'] ?? '').toString();

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: accent.withOpacity(0.18),
                                  child: Icon(Icons.person_rounded, color: accent),
                                ),
                                title: Text(targetName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                subtitle: Text(targetId, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                trailing: Icon(Icons.chat_rounded, color: accent, size: 20),
                                onTap: () async {
                                  Navigator.pop(ctx);
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DirectSupportChatScreen(
                                        myId: widget.myId,
                                        myName: widget.myName,
                                        peerId: targetId,
                                        peerName: targetName,
                                        peerRole: AppPrefs.tr('طالب بالدفعة', 'Batch Student'),
                                      ),
                                    ),
                                  );
                                  _fetchConversations(silent: true);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Theme.of(context).cardColor;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppPrefs.tr('صندوق رسائل الطلاب', 'Student Support Inbox')),
      ),
      floatingActionButton: _canStartNewChat
          ? FloatingActionButton.extended(
              backgroundColor: accent,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add_comment_rounded),
              label: Text(AppPrefs.tr('محادثة جديدة', 'New Chat'), style: const TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _openNewStudentChatPicker,
            )
          : null,
      body: Column(
        children: [
          if (_isOwner)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.admin_panel_settings_rounded, color: accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppPrefs.tr('السماح للمشرفين ببدء محادثات جديدة مع الطلاب', 'Allow admins to start new student chats'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Switch(
                    value: _allowAdminsDm,
                    activeColor: accent,
                    onChanged: _updatingSetting ? null : _toggleAdminsPermission,
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loadingInbox
                ? const Center(child: CircularProgressIndicator())
                : _conversations.isEmpty
                    ? Center(
                        child: Text(
                          AppPrefs.tr('لا توجد رسائل واردة حالياً', 'No incoming messages yet'),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 80),
                        itemCount: _conversations.length,
                        itemBuilder: (_, i) {
                          final c = _conversations[i];
                          return Card(
                            color: cardBg,
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: CircleAvatar(backgroundColor: accent.withOpacity(0.2), child: Icon(Icons.person, color: accent)),
                              title: Text(c['peerName'], style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(c['lastMessage'], maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DirectSupportChatScreen(
                                      myId: widget.myId,
                                      myName: widget.myName,
                                      peerId: c['peerId'],
                                      peerName: c['peerName'],
                                      peerRole: AppPrefs.tr('طالب بالدفعة', 'Batch Student'),
                                    ),
                                  ),
                                );
                                _fetchConversations(silent: true);
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
