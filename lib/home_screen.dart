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
import 'attendance_radar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String currentAppVersion = '1.3.0';
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _currentIndex = 0;
  String _studentName = '';
  String _studentId = '';
  String _universityEmail = '';
  String _profilePhotoPath = '';
  String _profileAvatarUrl = '';
  String _lastSyncText = '';
  bool _isAdmin = false;
  bool _isSyncing = false;
  String _urgentBanner = '';
  String _headerLogoUrl = '';
  Map<String, String> _calendarOccasions = {};

  List<dynamic> _subjects = [];
  List<dynamic> _schedule = [];
  List<dynamic> _assignments = [];
  List<dynamic> _notifications = [];
  List<dynamic> _myAttendance = [];
  List<dynamic> _announcements = [];
  List<dynamic> _subjectReferences = [];

  final PageController _bannerPageCtrl = PageController();
  int _currentBannerPage = 0;
  bool _bannerDismissed = false;
  Timer? _bannerTimer;

  final List<String> _days = ['السبت', 'الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس'];
  int _selectedDayIndex = 0;

  String get _firstName {
    final parts = _studentName.trim().split(RegExp(r'\s+'));
    return parts.isNotEmpty && parts.first.isNotEmpty ? parts.first : 'طالب';
  }

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

  String _smartGreetingText() {
    final now = DateTime.now();
    final isoDate =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    if (_calendarOccasions.containsKey(isoDate) && _calendarOccasions[isoDate]!.trim().isNotEmpty) {
      return _calendarOccasions[isoDate]!.trim();
    }

    if (now.weekday == DateTime.friday) {
      return AppPrefs.tr('جمعة مباركة ✨', 'Blessed Friday ✨');
    }
    if (now.month == 9 && now.day == 25) {
      return AppPrefs.tr('يوم صيدلي سعيد 💊', 'Happy World Pharmacists Day 💊');
    }
    if (now.month == 1 && now.day == 1) {
      return AppPrefs.tr('عام ميلادي سعيد 🎉', 'Happy New Year 🎉');
    }

    if (now.hour >= 4 && now.hour < 12) {
      return AppPrefs.tr('صباح الخير،', 'Good morning,');
    }
    return AppPrefs.tr('مساء الخير،', 'Good evening,');
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
    _bannerTimer = Timer.periodic(const Duration(seconds: 6), (_) {
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
    Map<String, String> occMap = {};
    try {
      final rawOcc = prefs.getString('cache_calendar_occasions') ?? '{}';
      occMap = Map<String, String>.from(jsonDecode(rawOcc));
    } catch (_) {}

    setState(() {
      _studentName = prefs.getString('full_name') ?? 'طالب صيدلة';
      _studentId = prefs.getString('student_id') ?? '';
      _universityEmail = prefs.getString('university_email') ?? '';
      _profilePhotoPath = prefs.getString('profile_photo_path') ?? '';
      _profileAvatarUrl = prefs.getString('profile_avatar_url') ?? '';
      _lastSyncText = prefs.getString('last_sync_time') ?? '';
      _isAdmin = prefs.getBool('is_admin') ?? false;
      _urgentBanner = prefs.getString('cache_urgent_banner') ?? '';
      _headerLogoUrl = prefs.getString('cache_header_logo_url') ?? '';
      _calendarOccasions = occMap;

      _subjects = jsonDecode(prefs.getString('cache_subjects') ?? '[]');
      _schedule = jsonDecode(prefs.getString('cache_schedule') ?? '[]');
      _assignments = jsonDecode(prefs.getString('cache_assignments') ?? '[]');
      _notifications = jsonDecode(prefs.getString('cache_notifications') ?? '[]');
      _myAttendance = jsonDecode(prefs.getString('cache_my_attendance') ?? '[]');
      _announcements = jsonDecode(prefs.getString('cache_announcements') ?? '[]');
      _subjectReferences = jsonDecode(prefs.getString('cache_subject_references') ?? '[]');
    });
  }

  Future<void> _syncOfflineAttendance(SharedPreferences prefs) async {
    final pending = prefs.getStringList('pending_offline_attendance') ?? [];
    if (pending.isEmpty) return;
    try {
      final rows = pending.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
      await Supabase.instance.client.from('attendance').insert(rows);
      await prefs.remove('pending_offline_attendance');
    } catch (_) {}
  }

  Future<void> _syncWithCloud({bool silent = false}) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await _syncOfflineAttendance(prefs);

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

      List<dynamic> refsData = _subjectReferences;
      try {
        refsData = await client.from('subject_references').select().order('id');
      } catch (_) {}

      String bannerText = '';
      String logoUrl = _headerLogoUrl;
      Map<String, String> occMap = _calendarOccasions;
      try {
        final settingsRows = await client
            .from('app_settings')
            .select('key, value')
            .inFilter('key', ['urgent_banner', 'calendar_occasions', 'header_logo_url']);
        for (final row in settingsRows) {
          final k = (row['key'] ?? '').toString();
          final v = (row['value'] ?? '').toString().trim();
          if (k == 'urgent_banner') bannerText = v;
          if (k == 'header_logo_url') logoUrl = v;
          if (k == 'calendar_occasions' && v.isNotEmpty) {
            occMap = Map<String, String>.from(jsonDecode(v));
          }
        }
      } catch (_) {}

      bool cloudAdmin = _isAdmin;
      String cloudEmail = _universityEmail;
      String cloudAvatar = _profileAvatarUrl;
      List<dynamic> attendanceData = _myAttendance;
      if (_studentId.isNotEmpty) {
        try {
          final me = await client
              .from('students')
              .select('is_admin, university_email, avatar_url')
              .eq('student_id', _studentId)
              .maybeSingle();
          if (me != null) {
            cloudAdmin = me['is_admin'] ?? false;
            if (me['university_email'] != null) {
              cloudEmail = me['university_email'].toString();
            }
            if (me['avatar_url'] != null) {
              cloudAvatar = me['avatar_url'].toString();
            }
          }
        } catch (_) {
          try {
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
          } catch (_) {}
        }
        try {
          attendanceData = await client
              .from('attendance')
              .select()
              .eq('student_id', _studentId)
              .order('created_at', ascending: false);
        } catch (_) {}
      }

      final now = DateTime.now();
      final syncStamp =
          '${now.day}/${now.month} - ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      await prefs.setBool('is_admin', cloudAdmin);
      await prefs.setString('university_email', cloudEmail);
      await prefs.setString('profile_avatar_url', cloudAvatar);
      await prefs.setString('last_sync_time', syncStamp);
      await prefs.setString('cache_urgent_banner', bannerText);
      await prefs.setString('cache_header_logo_url', logoUrl);
      await prefs.setString('cache_calendar_occasions', jsonEncode(occMap));
      await prefs.setString('cache_subjects', jsonEncode(subjectsData));
      await prefs.setString('cache_schedule', jsonEncode(scheduleData));
      await prefs.setString('cache_assignments', jsonEncode(assignmentsData));
      await prefs.setString('cache_notifications', jsonEncode(notificationsData));
      await prefs.setString('cache_my_attendance', jsonEncode(attendanceData));
      await prefs.setString('cache_announcements', jsonEncode(announcementsData));
      await prefs.setString('cache_subject_references', jsonEncode(refsData));

      if (!mounted) return;
      setState(() {
        _isAdmin = cloudAdmin;
        _universityEmail = cloudEmail;
        _profileAvatarUrl = cloudAvatar;
        _lastSyncText = syncStamp;
        _urgentBanner = bannerText;
        _headerLogoUrl = logoUrl;
        _calendarOccasions = occMap;
        _subjects = subjectsData;
        _schedule = scheduleData;
        _assignments = assignmentsData;
        _notifications = notificationsData;
        _myAttendance = attendanceData;
        _announcements = announcementsData;
        _subjectReferences = refsData;
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

  Future<void> _pickAndUploadProfilePhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 400);
    if (picked == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_photo_path', picked.path);
    if (mounted) setState(() => _profilePhotoPath = picked.path);

    // رفع الصورة سحابياً ليراها بقية الطلاب في دردشة الدفعة بجانب رسائله
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last;
      final fileName = 'avatar_${_studentId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await Supabase.instance.client.storage.from('announcements').uploadBinary(fileName, bytes);
      final publicUrl = Supabase.instance.client.storage.from('announcements').getPublicUrl(fileName);

      await Supabase.instance.client
          .from('students')
          .update({'avatar_url': publicUrl})
          .eq('student_id', _studentId);

      await prefs.setString('profile_avatar_url', publicUrl);
      if (mounted) setState(() => _profileAvatarUrl = publicUrl);
    } catch (_) {}
  }

  Future<void> _deleteProfilePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('profile_photo_path');
    await prefs.remove('profile_avatar_url');
    if (mounted) {
      setState(() {
        _profilePhotoPath = '';
        _profileAvatarUrl = '';
      });
    }
    try {
      await Supabase.instance.client
          .from('students')
          .update({'avatar_url': null})
          .eq('student_id', _studentId);
    } catch (_) {}
  }

  void _showProfilePhotoOptions() {
    final hasAnyPhoto = (_profilePhotoPath.isNotEmpty && !kIsWeb && File(_profilePhotoPath).existsSync()) ||
        _profileAvatarUrl.isNotEmpty;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: Colors.teal),
                title: Text(AppPrefs.tr('تغيير الصورة الشخصية من المعرض', 'Change Profile Photo')),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadProfilePhoto();
                },
              ),
              if (hasAnyPhoto)
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                  title: Text(
                    AppPrefs.tr('حذف الصورة الشخصية نهائياً', 'Delete Profile Photo Permanently'),
                    style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteProfilePhoto();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _voteOnAnnouncementPoll(Map<String, dynamic> annItem, int optionIndex) async {
    if (_studentId.isEmpty) return;
    final annId = annItem['id'];
    final Map<String, dynamic> votes = Map<String, dynamic>.from(
      annItem['poll_votes'] is Map ? annItem['poll_votes'] : {},
    );
    votes[_studentId] = optionIndex;

    setState(() {
      annItem['poll_votes'] = votes;
    });

    try {
      await Supabase.instance.client
          .from('announcements')
          .update({'poll_votes': votes})
          .eq('id', annId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cache_announcements', jsonEncode(_announcements));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppPrefs.tr('تعذر إرسال صوتك، تحقق من الإنترنت', 'Failed to submit vote')),
            backgroundColor: Colors.orange,
          ),
        );
      }
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
            if (_scaffoldKey.currentState?.isEndDrawerOpen == true) {
              _scaffoldKey.currentState?.closeEndDrawer();
              return;
            }
            if (_currentIndex != 0) {
              setState(() => _currentIndex = 0);
              return;
            }
            await StartupManager.showExitDialog(context);
          },
          child: _wrapWithWallpaper(
            Scaffold(
              key: _scaffoldKey,
              endDrawer: _buildSideMenuDrawer(cardBg, accent),
              body: SafeArea(child: pages[_currentIndex]),
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: _currentIndex,
                type: BottomNavigationBarType.fixed,
                onTap: (index) {
                  if (index == 3) {
                    _openBatchChat();
                    return;
                  }
                  setState(() => _currentIndex = index);
                },
                backgroundColor: cardBg,
                selectedItemColor: accent,
                unselectedItemColor: Colors.grey,
                items: [
                  BottomNavigationBarItem(icon: const Icon(Icons.home_rounded), label: AppPrefs.tr('الرئيسية', 'Home')),
                  BottomNavigationBarItem(icon: const Icon(Icons.calendar_month_rounded), label: AppPrefs.tr('الجدول', 'Schedule')),
                  BottomNavigationBarItem(icon: const Icon(Icons.push_pin_rounded), label: AppPrefs.tr('التكاليف', 'Assignments')),
                  BottomNavigationBarItem(icon: const Icon(Icons.chat_rounded), label: AppPrefs.tr('الدردشة', 'Chat')),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSideMenuDrawer(Color cardBg, Color accent) {
    final isDark = AppPrefs.isDark;
    final hasLocalPhoto = _profilePhotoPath.isNotEmpty && !kIsWeb && File(_profilePhotoPath).existsSync();
    final hasNetPhoto = _profileAvatarUrl.isNotEmpty;

    ImageProvider? avatarImg;
    if (hasLocalPhoto) {
      avatarImg = FileImage(File(_profilePhotoPath));
    } else if (hasNetPhoto) {
      avatarImg = NetworkImage(_profileAvatarUrl);
    }

    return Drawer(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: isDark
                      ? [const Color(0xFF0F2927), const Color(0xFF16202A)]
                      : [accent.withOpacity(0.22), accent.withOpacity(0.06)],
                ),
                border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.18))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: _showProfilePhotoOptions,
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: accent.withOpacity(0.2),
                              backgroundImage: avatarImg,
                              child: avatarImg == null ? Icon(Icons.person_rounded, size: 32, color: accent) : null,
                            ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                                child: const Icon(Icons.edit_rounded, size: 12, color: Colors.black),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _studentName,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, height: 1.3),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${AppPrefs.tr('رقم القيد:', 'ID:')} $_studentId',
                              style: TextStyle(fontSize: 12.5, color: accent, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _universityEmail.isNotEmpty
                          ? Colors.green.withOpacity(0.16)
                          : Colors.orange.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _universityEmail.isNotEmpty ? Colors.green : Colors.orange,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _universityEmail.isNotEmpty ? Icons.verified_rounded : Icons.info_outline_rounded,
                          size: 14,
                          color: _universityEmail.isNotEmpty ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _universityEmail.isNotEmpty
                              ? AppPrefs.tr('البريد الجامعي: مرتبط ✓', 'University Email: Linked ✓')
                              : AppPrefs.tr('البريد الجامعي: غير مرتبط', 'University Email: Not Linked'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _universityEmail.isNotEmpty ? Colors.green : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      AppPrefs.tr('الأدوات الدراسية والدفعة', 'Academic & Batch Tools'),
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                  ),
                  _drawerToolTile(
                    icon: Icons.medical_services_rounded,
                    iconColor: Colors.tealAccent,
                    title: AppPrefs.tr('حقيبة الصيدلي الإكلينيكي', 'Clinical Pharmacist Kit'),
                    subtitle: AppPrefs.tr('الحاسبات السريرية، الجرعات، والقيم المخبرية', 'CrCl, pediatric doses & lab values'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ClinicalPharmacistBagScreen()));
                    },
                  ),
                  _drawerToolTile(
                    icon: Icons.auto_stories_rounded,
                    iconColor: Colors.amberAccent,
                    title: AppPrefs.tr('حقيبة المراجعة ليلة الامتحان', 'Exam Night Review Bag'),
                    subtitle: AppPrefs.tr('الأسئلة والملفات المفضلة + مرجع المواد', 'Starred items & subject references'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ExamNightReviewScreen(
                            subjects: _subjects,
                            references: _subjectReferences,
                          ),
                        ),
                      );
                    },
                  ),
                  _drawerToolTile(
                    icon: Icons.calculate_rounded,
                    iconColor: Colors.lightBlueAccent,
                    title: AppPrefs.tr('حاسبة المعدل التراكمي (GPA)', 'GPA Calculator'),
                    subtitle: AppPrefs.tr('حساب المعدل الفصلي والتراكمي بالساعات', 'Semester & cumulative GPA'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const GpaScreen()));
                    },
                  ),
                  _drawerToolTile(
                    icon: Icons.contact_phone_rounded,
                    iconColor: Colors.purpleAccent,
                    title: AppPrefs.tr('دليل الدفعة والمناديب', 'Batch Directory & Links'),
                    subtitle: AppPrefs.tr('أرقام التواصل والروابط المهمة للدفعة', 'Contacts & useful links'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const DirectoryScreen()));
                    },
                  ),

                  const Divider(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      AppPrefs.tr('التحكم والنظام', 'System & Control'),
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                  ),
                  _drawerToolTile(
                    icon: _isSyncing ? Icons.hourglass_top_rounded : Icons.sync_rounded,
                    iconColor: Colors.cyanAccent,
                    title: AppPrefs.tr('مزامنة وتحديث البيانات', 'Sync & Update Data'),
                    subtitle: _lastSyncText.isNotEmpty
                        ? '${AppPrefs.tr('آخر مزامنة:', 'Last sync:')} $_lastSyncText'
                        : AppPrefs.tr('اضغط لتحديث المواد والجدول', 'Tap to sync cloud data'),
                    onTap: () {
                      Navigator.pop(context);
                      _syncWithCloud(silent: false);
                    },
                  ),
                  _drawerToolTile(
                    icon: Icons.settings_rounded,
                    iconColor: Colors.orangeAccent,
                    title: AppPrefs.tr('الإعدادات والتخصيص', 'Settings & Customization'),
                    subtitle: AppPrefs.tr('السمات، الخطوط، الإشعارات، وتحديث البرنامج', 'Themes, fonts, alerts & software update'),
                    onTap: () {
                      Navigator.pop(context);
                      _openGeneralSettings();
                    },
                  ),
                  if (_isAdmin)
                    _drawerToolTile(
                      icon: Icons.admin_panel_settings_rounded,
                      iconColor: Colors.amber,
                      title: AppPrefs.tr('لوحة إدارة الدفعة', 'Admin Control Panel'),
                      subtitle: AppPrefs.tr('خاص بالمشرفين والمناديب', 'Admins & representatives only'),
                      highlight: true,
                      onTap: () {
                        Navigator.pop(context);
                        _promptAdminPassword();
                      },
                    ),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: cardBg,
                border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.18))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.language_rounded, size: 18, color: accent),
                      const SizedBox(width: 8),
                      Text(AppPrefs.tr('لغة التطبيق', 'Language'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  SegmentedButton<String>(
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const [
                      ButtonSegment(value: 'ar', label: Text('عربي', style: TextStyle(fontSize: 12))),
                      ButtonSegment(value: 'en', label: Text('English', style: TextStyle(fontSize: 12))),
                    ],
                    selected: {AppPrefs.isEnglish ? 'en' : 'ar'},
                    onSelectionChanged: (sel) async {
                      await AppPrefs.setLang(sel.first);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerToolTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool highlight = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: highlight
          ? BoxDecoration(
              color: Colors.amber.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.amber.withOpacity(0.45)),
            )
          : null,
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 21),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  /// بناء شعار التطبيق في وسط الترويسة كأنه مطبوع مباشرة بلا إطار أو خلفية دائرية
  Widget _buildCenterAppLogo(Color accent) {
    Widget fallbackAsset() {
      return Image.asset(
        'assets/logo.png',
        height: 46,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Image.asset(
          'logo.png',
          height: 46,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Image.asset(
            'assets/icon.png',
            height: 46,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Image.asset(
              'icon.png',
              height: 46,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                Icons.local_pharmacy_rounded,
                size: 38,
                color: accent,
              ),
            ),
          ),
        ),
      );
    }

    if (_headerLogoUrl.isNotEmpty) {
      return Image.network(
        _headerLogoUrl,
        height: 46,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => fallbackAsset(),
      );
    }
    return fallbackAsset();
  }

  Widget _buildDashboardTab(Color cardBg, Color accent) {
    final borderCol = Colors.grey.withOpacity(0.2);
    final radius = AppPrefs.cardRadius;
    final orderedSubjects = AppPrefs.applySubjectOrder(_subjects);
    final isDark = AppPrefs.isDark;

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
            const SizedBox(height: 12),
          ],

          // الصف الأول: الترحيب + الاسم الأول (يمين) | شعار التطبيق الرسمي (وسط) | التاريخ (يسار)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _smartGreetingText(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _firstName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _buildCenterAppLogo(accent),
              ),

              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: InkWell(
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
                          Icon(Icons.calendar_today_rounded, size: 12, color: accent),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              _formattedTodayDate(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // الصف الثاني: الأدوات الأربع مرتبة على سطر واحد متناسق (رادار، QR، الإشعارات، القائمة ☰)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _miniHeaderBtn(
                    icon: Icons.radar_rounded,
                    tooltip: AppPrefs.tr('رادار التحضير', 'Attendance Radar'),
                    onTap: _openFastRadarAttendance,
                    cardBg: cardBg,
                    accent: accent,
                  ),
                  const SizedBox(width: 10),
                  _miniHeaderBtn(
                    icon: Icons.qr_code_2_rounded,
                    tooltip: AppPrefs.tr('كودي (QR)', 'My QR'),
                    onTap: _showMyStudentQR,
                    cardBg: cardBg,
                    accent: accent,
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _miniHeaderBtn(
                    icon: Icons.notifications_active_rounded,
                    tooltip: AppPrefs.tr('الإشعارات', 'Alerts'),
                    onTap: _openNotifications,
                    cardBg: cardBg,
                    accent: accent,
                    badge: _notifications.length,
                  ),
                  const SizedBox(width: 10),
                  _miniHeaderBtn(
                    icon: Icons.menu_rounded,
                    tooltip: AppPrefs.tr('القائمة والأدوات', 'Menu'),
                    onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                    cardBg: cardBg,
                    accent: accent,
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),

          // شريط البحث الشامل بتصميم كبسولة واتساب
          InkWell(
            onTap: _openGlobalSearch,
            borderRadius: BorderRadius.circular(30),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F272E) : Colors.black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.grey.withOpacity(0.16)),
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 21, color: Colors.grey.shade400),
                  const SizedBox(width: 10),
                  Text(
                    AppPrefs.tr('بحث...', 'Search...'),
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                  ),
                ],
              ),
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

  Widget _miniHeaderBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required Color cardBg,
    required Color accent,
    int badge = 0,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
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
                  padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badge',
                    style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openFastRadarAttendance() {
    final cardBg = Theme.of(context).cardColor;
    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => StudentFastAttendanceSheet(
        studentId: _studentId,
        studentName: _studentName,
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
          label: Text(AppPrefs.tr('إظهار الإعلانات والتصويت (${_announcements.length})', 'Show Announcements (${_announcements.length})'), style: const TextStyle(fontSize: 12)),
          onPressed: () => setState(() => _bannerDismissed = false),
        ),
      );
    }

    final hasAnyPoll = _announcements.any((e) => (e['poll_options'] is List) && (e['poll_options'] as List).isNotEmpty);

    return SizedBox(
      height: hasAnyPoll ? 205 : 155,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: PageView.builder(
              controller: _bannerPageCtrl,
              itemCount: _announcements.length,
              onPageChanged: (idx) => setState(() => _currentBannerPage = idx),
              itemBuilder: (_, idx) {
                final item = Map<String, dynamic>.from(_announcements[idx]);
                final List<dynamic> pollOptions = (item['poll_options'] is List) ? item['poll_options'] : [];

                if (pollOptions.isNotEmpty) {
                  final Map<String, dynamic> votes = Map<String, dynamic>.from(
                    item['poll_votes'] is Map ? item['poll_votes'] : {},
                  );
                  final int totalVotes = votes.length;
                  final int? myVoteIdx = votes[_studentId] is int ? votes[_studentId] : int.tryParse('${votes[_studentId]}');

                  return Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [Color(0xFF0F172A), Color(0xFF134E4A)],
                      ),
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(color: accent.withOpacity(0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.poll_rounded, color: accent, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item['title'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                            ),
                            const SizedBox(width: 24),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: pollOptions.length,
                            itemBuilder: (_, optIdx) {
                              final optText = pollOptions[optIdx].toString();
                              final countForOpt = votes.values.where((v) => v.toString() == optIdx.toString()).length;
                              final pct = totalVotes == 0 ? 0.0 : countForOpt / totalVotes;
                              final isSelected = myVoteIdx == optIdx;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 5),
                                child: InkWell(
                                  onTap: () => _voteOnAnnouncementPoll(item, optIdx),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isSelected ? accent.withOpacity(0.28) : Colors.white.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: isSelected ? accent : Colors.white24),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                          size: 15,
                                          color: isSelected ? accent : Colors.white70,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            optText,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                        Text(
                                          '${(pct * 100).round()}% ($countForOpt)',
                                          style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                }

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
                Text(AppPrefs.tr('سجل الحضور الشخصي', 'My Attendance Log'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: accent)),
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
                      'لم يتم تسجيل أي حضور لك بعد. استخدم رادار التحضير أو اعرض كود QR للمندوب.',
                      'No attendance recorded yet.',
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

  Future<void> _openGlobalSearch() async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> allQuestions = [];
    final List<Map<String, dynamic>> allMaterials = [];

    for (final s in _subjects) {
      final sid = s['id'];
      final sname = (s['name'] ?? '').toString();
      final hex = (s['color_hex'] ?? '#2B6CB0').toString();

      final rawQ = prefs.getString('cache_questions_$sid');
      if (rawQ != null && rawQ.isNotEmpty) {
        try {
          for (final q in jsonDecode(rawQ)) {
            allQuestions.add({
              ...Map<String, dynamic>.from(q),
              '_subject': s,
              '_subjName': sname,
              '_colorHex': hex,
            });
          }
        } catch (_) {}
      }

      final rawM = prefs.getString('cache_materials_$sid');
      if (rawM != null && rawM.isNotEmpty) {
        try {
          for (final m in jsonDecode(rawM)) {
            allMaterials.add({
              ...Map<String, dynamic>.from(m),
              '_subject': s,
              '_subjName': sname,
              '_colorHex': hex,
            });
          }
        } catch (_) {}
      }
    }

    // محاولة جلب الأسئلة والملفات من السحابة إن لم تكن مخزنة محلياً بعد
    if (allQuestions.isEmpty || allMaterials.isEmpty) {
      try {
        final subjById = {for (final s in _subjects) s['id']: s};
        if (allQuestions.isEmpty) {
          final qRows = await Supabase.instance.client.from('questions').select().limit(500);
          for (final q in qRows) {
            final s = subjById[q['subject_id']];
            if (s != null) {
              allQuestions.add({
                ...Map<String, dynamic>.from(q),
                '_subject': s,
                '_subjName': (s['name'] ?? '').toString(),
                '_colorHex': (s['color_hex'] ?? '#2B6CB0').toString(),
              });
            }
          }
        }
        if (allMaterials.isEmpty) {
          final mRows = await Supabase.instance.client.from('materials').select().limit(500);
          for (final m in mRows) {
            final s = subjById[m['subject_id']];
            if (s != null) {
              allMaterials.add({
                ...Map<String, dynamic>.from(m),
                '_subject': s,
                '_subjName': (s['name'] ?? '').toString(),
                '_colorHex': (s['color_hex'] ?? '#2B6CB0').toString(),
              });
            }
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    showSearch(
      context: context,
      delegate: AppGlobalSearchDelegate(
        subjects: _subjects,
        schedule: _schedule,
        assignments: _assignments,
        notifications: _notifications,
        announcements: _announcements,
        references: _subjectReferences,
        questions: allQuestions,
        materials: allMaterials,
        onOpenAnnouncement: (item) => _showAnnouncementFullModal(item),
        onSwitchTab: (tabIdx) => setState(() => _currentIndex = tabIdx),
        onOpenRadar: _openFastRadarAttendance,
        onOpenQR: _showMyStudentQR,
        onOpenChat: _openBatchChat,
        onOpenNotifications: _openNotifications,
        onOpenSettings: _openGeneralSettings,
        onOpenAttendanceLog: _showMyAttendanceDetails,
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
        builder: (_) => BatchChatScreen(
          studentId: _studentId,
          defaultName: _studentName,
          isAdmin: _isAdmin,
          myLocalPhotoPath: _profilePhotoPath,
          myAvatarUrl: _profileAvatarUrl,
        ),
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
                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: Icon(Icons.system_update_rounded, color: accent),
                      title: Text(AppPrefs.tr('تحديث البرنامج', 'Software Update'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${AppPrefs.tr('الإصدار الحالي:', 'Current version:')} $currentAppVersion', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.push(
                          ctx,
                          MaterialPageRoute(
                            builder: (_) => const SoftwareUpdateScreen(currentVersion: currentAppVersion),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),

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
                          title: Text(AppPrefs.tr('إظهار شريط الإعلانات والتصويت في الرئيسية', 'Show Announcements Banner')),
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
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: Icon(Icons.fingerprint_rounded, color: accent),
                          title: Text(AppPrefs.tr('فتح قفل التطبيق بالبصمة', 'Unlock App with Fingerprint')),
                          subtitle: Text(AppPrefs.tr('استخدام بصمة الإصبع عند فتح التطبيق', 'Use fingerprint on app launch')),
                          value: AppPrefs.biometricEnabled,
                          onChanged: (val) async {
                            if (val) {
                              final ok = await BiometricHelper.authenticate(
                                reason: AppPrefs.tr('أكّد بصمتك لتفعيل قفل التطبيق بالبصمة', 'Confirm fingerprint to enable app lock'),
                              );
                              if (!ok) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text(AppPrefs.tr('تعذر التحقق من البصمة في جهازك', 'Biometric authentication failed')), backgroundColor: Colors.red),
                                  );
                                }
                                return;
                              }
                            }
                            await AppPrefs.setBiometricEnabled(val);
                            setSettingsState(() {});
                          },
                        ),
                        if (_isAdmin)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: const Icon(Icons.admin_panel_settings_rounded, color: Colors.amber),
                            title: Text(AppPrefs.tr('فتح لوحة الإدارة بالبصمة', 'Unlock Admin Panel with Fingerprint')),
                            subtitle: Text(AppPrefs.tr('الدخول السريع للوحة الإدارة ببصمتك بدلاً من الرمز', 'Quick admin login via fingerprint')),
                            value: AppPrefs.adminBiometricEnabled,
                            onChanged: (val) async {
                              if (val) {
                                final ok = await BiometricHelper.authenticate(
                                  reason: AppPrefs.tr('أكّد بصمتك لتفعيل الدخول السريع للوحة الإدارة', 'Confirm fingerprint for Admin Panel'),
                                );
                                if (!ok) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(content: Text(AppPrefs.tr('تعذر التحقق من البصمة', 'Biometric verification failed')), backgroundColor: Colors.red),
                                    );
                                  }
                                  return;
                                }
                              }
                              await AppPrefs.setAdminBiometricEnabled(val);
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
    if (AppPrefs.adminBiometricEnabled) {
      final bioOk = await BiometricHelper.authenticate(
        reason: AppPrefs.tr('ضع بصمتك لفتح لوحة إدارة الدفعة', 'Use fingerprint to open Admin Panel'),
      );
      if (bioOk && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AdminScreen(adminName: _studentName)),
        );
        return;
      }
    }

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
            const SizedBox(height: 10),
            TextButton.icon(
              icon: Icon(Icons.fingerprint_rounded, color: accent),
              label: Text(AppPrefs.tr('الدخول بالبصمة', 'Use Fingerprint'), style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
              onPressed: () async {
                final ok = await BiometricHelper.authenticate(
                  reason: AppPrefs.tr('ضع بصمتك لفتح لوحة إدارة الدفعة', 'Use fingerprint to open Admin Panel'),
                );
                if (ok && dialogCtx.mounted) {
                  Navigator.pop(dialogCtx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AdminScreen(adminName: _studentName)),
                  );
                }
              },
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

class SoftwareUpdateScreen extends StatefulWidget {
  final String currentVersion;
  const SoftwareUpdateScreen({super.key, required this.currentVersion});

  @override
  State<SoftwareUpdateScreen> createState() => _SoftwareUpdateScreenState();
}

class _SoftwareUpdateScreenState extends State<SoftwareUpdateScreen> {
  bool _checking = false;
  bool _autoWifi = true;
  String _lastChecked = '';
  String _latestVersion = '';
  String _updateUrl = '';
  String _updateNotes = '';

  @override
  void initState() {
    super.initState();
    _latestVersion = widget.currentVersion;
    _loadPrefsAndCheck();
  }

  Future<void> _loadPrefsAndCheck() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoWifi = prefs.getBool('update_auto_wifi') ?? true;
      _lastChecked = prefs.getString('update_last_checked') ?? '';
    });
    await _checkForUpdate();
  }

  int _compareVersions(String v1, String v2) {
    final p1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final p2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final a = i < p1.length ? p1[i] : 0;
      final b = i < p2.length ? p2[i] : 0;
      if (a > b) return 1;
      if (a < b) return -1;
    }
    return 0;
  }

  Future<void> _checkForUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final rows = await Supabase.instance.client
          .from('app_settings')
          .select('key, value')
          .inFilter('key', ['latest_version', 'update_url', 'update_notes']);

      String latest = widget.currentVersion;
      String url = 'https://github.com/780ramialhakami780-jpg/IQ_Pharmacy39/releases/latest/download/IQ_Pharmacy39.apk';
      String notes = '';

      for (final r in rows) {
        final k = (r['key'] ?? '').toString();
        final v = (r['value'] ?? '').toString().trim();
        if (k == 'latest_version' && v.isNotEmpty) latest = v;
        if (k == 'update_url' && v.isNotEmpty) url = v;
        if (k == 'update_notes' && v.isNotEmpty) notes = v;
      }

      final now = DateTime.now();
      final stamp = '${now.year}/${now.month}/${now.day} • ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('update_last_checked', stamp);

      if (!mounted) return;
      setState(() {
        _latestVersion = latest;
        _updateUrl = url;
        _updateNotes = notes;
        _lastChecked = stamp;
        _checking = false;
      });
    } catch (_) {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Theme.of(context).cardColor;
    final accent = Theme.of(context).colorScheme.primary;
    final hasNewer = _compareVersions(_latestVersion, widget.currentVersion) > 0;

    return Scaffold(
      appBar: AppBar(title: Text(AppPrefs.tr('تحديث البرنامج', 'Software Update'))),
      body: _checking
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: accent),
                  const SizedBox(height: 18),
                  Text(
                    AppPrefs.tr('يتم البحث عن تحديثات...', 'Checking for updates...'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: cardBg,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    leading: Icon(
                      hasNewer ? Icons.system_update_alt_rounded : Icons.verified_rounded,
                      color: hasNewer ? accent : Colors.green,
                      size: 30,
                    ),
                    title: Text(
                      hasNewer
                          ? AppPrefs.tr('يتوفر تحديث جديد ($_latestVersion)', 'Update available ($_latestVersion)')
                          : AppPrefs.tr('برنامجك محدّث.', 'Your software is up to date.'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    subtitle: Text(
                      _lastChecked.isNotEmpty
                          ? '${AppPrefs.tr('آخر فحص:', 'Last checked:')} $_lastChecked'
                          : AppPrefs.tr('اضغط للفحص اليدوي', 'Tap to check manually'),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    onTap: _checkForUpdate,
                  ),
                ),
                if (hasNewer) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
                      icon: const Icon(Icons.download_rounded),
                      label: Text(AppPrefs.tr('تنزيل وتثبيت التحديث الآن', 'Download and install'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () {
                        final uri = Uri.tryParse(_updateUrl);
                        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Card(
                  color: cardBg,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: SwitchListTile(
                    title: Text(AppPrefs.tr('التنزيل التلقائي عبر Wi-Fi', 'Auto download over Wi-Fi'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      AppPrefs.tr('البحث عن التحديثات تلقائياً عند الاتصال بشبكة Wi-Fi', 'Check updates automatically on Wi-Fi'),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    value: _autoWifi,
                    activeColor: accent,
                    onChanged: (v) async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('update_auto_wifi', v);
                      setState(() => _autoWifi = v);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: cardBg,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppPrefs.tr('تحديث المعلومات', 'Update information'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: accent)),
                        const SizedBox(height: 10),
                        Text('• ${AppPrefs.tr('إصدار التطبيق الحالي:', 'Current version:')} ${widget.currentVersion}'),
                        const SizedBox(height: 4),
                        Text('• ${AppPrefs.tr('أحدث إصدار على الخادم:', 'Latest server version:')} $_latestVersion'),
                        if (_updateNotes.isNotEmpty) ...[
                          const Divider(height: 20),
                          Text(AppPrefs.tr('ما الجديد في هذا الإصدار:', 'What is new:'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 6),
                          Text(_updateNotes, style: const TextStyle(fontSize: 13, height: 1.5, color: Colors.grey)),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class ClinicalPharmacistBagScreen extends StatefulWidget {
  const ClinicalPharmacistBagScreen({super.key});

  @override
  State<ClinicalPharmacistBagScreen> createState() => _ClinicalPharmacistBagScreenState();
}

class _ClinicalPharmacistBagScreenState extends State<ClinicalPharmacistBagScreen> {
  final _ageCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _scrCtrl = TextEditingController();
  bool _isFemale = false;
  double? _crclResult;

  final _pedWeightCtrl = TextEditingController();
  final _pedDosePerKgCtrl = TextEditingController();
  final _pedFreqCtrl = TextEditingController(text: '3');
  double? _pedTotalDaily;
  double? _pedSingleDose;

  @override
  void dispose() {
    _ageCtrl.dispose();
    _weightCtrl.dispose();
    _scrCtrl.dispose();
    _pedWeightCtrl.dispose();
    _pedDosePerKgCtrl.dispose();
    _pedFreqCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Theme.of(context).cardColor;
    final accent = Theme.of(context).colorScheme.primary;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppPrefs.tr('حقيبة الصيدلي الإكلينيكي', 'Clinical Pharmacist Kit')),
          bottom: TabBar(
            indicatorColor: accent,
            tabs: [
              Tab(text: AppPrefs.tr('تصفية الكرياتينين', 'CrCl Calc')),
              Tab(text: AppPrefs.tr('جرعات الأطفال', 'Pediatric Dose')),
              Tab(text: AppPrefs.tr('القيم المخبرية', 'Lab Values')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: cardBg,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Cockcroft-Gault Equation (CrCl)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: accent)),
                        const SizedBox(height: 12),
                        TextField(controller: _ageCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'العمر (سنة)', border: OutlineInputBorder())),
                        const SizedBox(height: 10),
                        TextField(controller: _weightCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الوزن (kg)', border: OutlineInputBorder())),
                        const SizedBox(height: 10),
                        TextField(controller: _scrCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Serum Creatinine (mg/dL)', border: OutlineInputBorder())),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('أنثى (Female × 0.85)'),
                          value: _isFemale,
                          onChanged: (v) => setState(() => _isFemale = v),
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
                            onPressed: () {
                              final age = double.tryParse(_ageCtrl.text.trim());
                              final wt = double.tryParse(_weightCtrl.text.trim());
                              final scr = double.tryParse(_scrCtrl.text.trim());
                              if (age != null && wt != null && scr != null && scr > 0) {
                                double val = ((140 - age) * wt) / (72 * scr);
                                if (_isFemale) val *= 0.85;
                                setState(() => _crclResult = val);
                              }
                            },
                            child: const Text('حساب تصفية الكرياتينين', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        if (_crclResult != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: accent.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                            child: Text(
                              'CrCl = ${_crclResult!.toStringAsFixed(1)} mL/min',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: accent),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),

            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: cardBg,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('حاسبة جرعات الأطفال حسب الوزن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: accent)),
                        const SizedBox(height: 12),
                        TextField(controller: _pedWeightCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'وزن الطفل (kg)', border: OutlineInputBorder())),
                        const SizedBox(height: 10),
                        TextField(controller: _pedDosePerKgCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الجرعة اليومية (mg/kg/day)', border: OutlineInputBorder())),
                        const SizedBox(height: 10),
                        TextField(controller: _pedFreqCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد الجرعات في اليوم (مثلاً: 3)', border: OutlineInputBorder())),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
                            onPressed: () {
                              final wt = double.tryParse(_pedWeightCtrl.text.trim());
                              final dose = double.tryParse(_pedDosePerKgCtrl.text.trim());
                              final freq = int.tryParse(_pedFreqCtrl.text.trim()) ?? 1;
                              if (wt != null && dose != null && freq > 0) {
                                final total = wt * dose;
                                setState(() {
                                  _pedTotalDaily = total;
                                  _pedSingleDose = total / freq;
                                });
                              }
                            },
                            child: const Text('حساب الجرعة', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        if (_pedTotalDaily != null && _pedSingleDose != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: accent.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                            child: Column(
                              children: [
                                Text('الجرعة اليومية الكلية: ${_pedTotalDaily!.toStringAsFixed(1)} mg/day', style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Text('الجرعة الواحدة: ${_pedSingleDose!.toStringAsFixed(1)} mg', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: accent)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),

            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _labTile(cardBg, accent, 'Sodium (Na+)', '135 – 145 mEq/L'),
                _labTile(cardBg, accent, 'Potassium (K+)', '3.5 – 5.0 mEq/L'),
                _labTile(cardBg, accent, 'Serum Creatinine (SCr)', '0.6 – 1.2 mg/dL'),
                _labTile(cardBg, accent, 'BUN', '7 – 20 mg/dL'),
                _labTile(cardBg, accent, 'Fasting Blood Glucose', '70 – 100 mg/dL'),
                _labTile(cardBg, accent, 'HbA1c (Normal)', 'Less than 5.7%'),
                _labTile(cardBg, accent, 'Hemoglobin (Hb)', 'Male: 13.5–17.5 | Female: 12.0–16.0 g/dL'),
                _labTile(cardBg, accent, 'WBC Count', '4,500 – 11,000 /µL'),
                _labTile(cardBg, accent, 'Platelets', '150,000 – 450,000 /µL'),
                _labTile(cardBg, accent, 'INR (Normal / Warfarin)', 'Normal: 0.8–1.1 | Therapeutic: 2.0–3.0'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _labTile(Color cardBg, Color accent, String name, String range) {
    return Card(
      color: cardBg,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        trailing: Text(range, style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 12.5)),
      ),
    );
  }
}

class ExamNightReviewScreen extends StatefulWidget {
  final List<dynamic> subjects;
  final List<dynamic> references;
  const ExamNightReviewScreen({super.key, required this.subjects, required this.references});

  @override
  State<ExamNightReviewScreen> createState() => _ExamNightReviewScreenState();
}

class _ExamNightReviewScreenState extends State<ExamNightReviewScreen> {
  List<Map<String, dynamic>> _favQuestions = [];
  List<Map<String, dynamic>> _favMaterials = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> qOut = [];
    final List<Map<String, dynamic>> mOut = [];

    for (final s in widget.subjects) {
      final sid = s['id'];
      final sname = (s['name'] ?? '').toString();
      final favQ = (prefs.getStringList('fav_q_$sid') ?? []).toSet();
      final favM = (prefs.getStringList('fav_m_$sid') ?? []).toSet();

      if (favQ.isNotEmpty) {
        final rawQ = prefs.getString('cache_questions_$sid');
        if (rawQ != null) {
          final List<dynamic> listQ = jsonDecode(rawQ);
          for (final q in listQ) {
            if (favQ.contains(q['id'].toString())) {
              qOut.add({...Map<String, dynamic>.from(q), '_subjName': sname});
            }
          }
        }
      }
      if (favM.isNotEmpty) {
        final rawM = prefs.getString('cache_materials_$sid');
        if (rawM != null) {
          final List<dynamic> listM = jsonDecode(rawM);
          for (final m in listM) {
            if (favM.contains(m['id'].toString())) {
              mOut.add({...Map<String, dynamic>.from(m), '_subjName': sname});
            }
          }
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _favQuestions = qOut;
      _favMaterials = mOut;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Theme.of(context).cardColor;
    final accent = Theme.of(context).colorScheme.primary;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppPrefs.tr('حقيبة المراجعة ليلة الامتحان', 'Exam Night Review Bag')),
          bottom: TabBar(
            indicatorColor: accent,
            tabs: [
              Tab(text: AppPrefs.tr('مرجع المواد', 'Subject Refs')),
              Tab(text: '${AppPrefs.tr('أسئلة مفضلة', 'Questions')} (${_favQuestions.length})'),
              Tab(text: '${AppPrefs.tr('ملفات مفضلة', 'Files')} (${_favMaterials.length})'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.subjects.length,
                    itemBuilder: (_, idx) {
                      final subj = widget.subjects[idx];
                      final sid = subj['id'];
                      final subjRefs = widget.references.where((r) => r['subject_id'] == sid).toList();

                      return Card(
                        color: cardBg,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: ExpansionTile(
                          leading: Icon(Icons.menu_book_rounded, color: accent),
                          title: Text(subj['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            subjRefs.isEmpty
                                ? AppPrefs.tr('لا توجد بطاقات مرجعية مضافة بعد', 'No reference cards yet')
                                : '${subjRefs.length} ${AppPrefs.tr('بطاقة مراجعة مركزة', 'reference cards')}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                          children: subjRefs.isEmpty
                              ? [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Text(
                                      AppPrefs.tr('سيتم عرض ملخصات وقوانين هذه المادة هنا فور إضافتها من الإدارة.', 'Reference cards will appear here once added.'),
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  )
                                ]
                              : subjRefs.map((ref) {
                                  return Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(top: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: accent.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: accent.withOpacity(0.3)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(ref['title'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, color: accent, fontSize: 14)),
                                        const SizedBox(height: 6),
                                        Text(ref['content'] ?? '', style: const TextStyle(fontSize: 13, height: 1.5)),
                                      ],
                                    ),
                                  );
                                }).toList(),
                        ),
                      );
                    },
                  ),

                  _favQuestions.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              AppPrefs.tr('اضغط على علامة النجمة ⭐ بجانب أي سؤال صعب في بنك الأسئلة ليظهر هنا ليلة الامتحان.', 'Tap ⭐ next to any question to save it here.'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _favQuestions.length,
                          itemBuilder: (_, idx) {
                            final q = _favQuestions[idx];
                            final List<dynamic> opts = q['options'] is String ? jsonDecode(q['options']) : (q['options'] ?? []);
                            final int cIdx = q['correct_index'] ?? 0;
                            final answerText = (cIdx >= 0 && cIdx < opts.length) ? opts[cIdx].toString() : '';
                            return Card(
                              color: cardBg,
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(q['_subjName'] ?? '', style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text(q['question_text'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    const SizedBox(height: 8),
                                    Text('✅ $answerText', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),

                  _favMaterials.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              AppPrefs.tr('اضغط على علامة النجمة ⭐ بجانب أي ملف مهم داخل المواد ليظهر هنا للمراجعة السريعة.', 'Tap ⭐ next to any important file to save it here.'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _favMaterials.length,
                          itemBuilder: (_, idx) {
                            final m = _favMaterials[idx];
                            return Card(
                              color: cardBg,
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                leading: const Icon(Icons.star_rounded, color: Colors.amber),
                                title: Text(m['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('${m['_subjName']} • المحاضرة ${m['lecture_number']}'),
                                trailing: const Icon(Icons.open_in_new_rounded),
                                onTap: () {
                                  final uri = Uri.tryParse((m['file_url'] ?? '').toString());
                                  if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
                                },
                              ),
                            );
                          },
                        ),
                ],
              ),
      ),
    );
  }
}

class AppGlobalSearchDelegate extends SearchDelegate {
  final List<dynamic> subjects;
  final List<dynamic> schedule;
  final List<dynamic> assignments;
  final List<dynamic> notifications;
  final List<dynamic> announcements;
  final List<dynamic> references;
  final List<Map<String, dynamic>> questions;
  final List<Map<String, dynamic>> materials;
  final void Function(Map<String, dynamic> item) onOpenAnnouncement;
  final void Function(int tabIndex) onSwitchTab;
  final VoidCallback onOpenRadar;
  final VoidCallback onOpenQR;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAttendanceLog;

  AppGlobalSearchDelegate({
    required this.subjects,
    required this.schedule,
    required this.assignments,
    required this.notifications,
    required this.announcements,
    required this.references,
    required this.questions,
    required this.materials,
    required this.onOpenAnnouncement,
    required this.onSwitchTab,
    required this.onOpenRadar,
    required this.onOpenQR,
    required this.onOpenChat,
    required this.onOpenNotifications,
    required this.onOpenSettings,
    required this.onOpenAttendanceLog,
  });

  @override
  String get searchFieldLabel => AppPrefs.tr(
        'ابحث في المواد، الأسئلة، الملفات، الإعلانات، والأدوات...',
        'Search subjects, questions, files, ads, tools...',
      );

  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
      ];

  @override
  Widget? buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults(context);

  Color _parseColor(String? hexStr) {
    try {
      final hex = (hexStr ?? '#2B6CB0').toString().replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFF2B6CB0);
    }
  }

  Widget _buildSearchResults(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final cardBg = Theme.of(context).cardColor;
    final cleanQ = query.trim().toLowerCase();

    final List<Map<String, dynamic>> appFeatures = [
      {
        'title': AppPrefs.tr('حقيبة الصيدلي الإكلينيكي', 'Clinical Pharmacist Kit'),
        'subtitle': AppPrefs.tr('تصفية الكرياتينين CrCl، جرعات الأطفال، والقيم المخبرية', 'CrCl, pediatric dose & normal lab values'),
        'keywords': 'حقيبة الصيدلي الاكلينيكي السريري كرياتينين تصفية جرعات اطفال قيم مخبرية مختبر crcl cockcroft pediatric lab',
        'icon': Icons.medical_services_rounded,
        'color': Colors.tealAccent,
        'action': () {
          close(context, null);
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ClinicalPharmacistBagScreen()));
        },
      },
      {
        'title': AppPrefs.tr('حقيبة المراجعة ليلة الامتحان', 'Exam Night Review Bag'),
        'subtitle': AppPrefs.tr('مرجع المواد، الأسئلة والملفات المفضلة بنجمة', 'Subject references, starred questions & files'),
        'keywords': 'حقيبة المراجعة ليلة الامتحان مرجع المواد مفضلة نجمة ملخصات exam review bag star',
        'icon': Icons.auto_stories_rounded,
        'color': Colors.amberAccent,
        'action': () {
          close(context, null);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ExamNightReviewScreen(subjects: subjects, references: references)),
          );
        },
      },
      {
        'title': AppPrefs.tr('حاسبة المعدل التراكمي (GPA)', 'GPA Calculator'),
        'subtitle': AppPrefs.tr('حساب المعدل الفصلي والتراكمي والساعات المعتمدة', 'Calculate semester & cumulative GPA'),
        'keywords': 'حاسبة المعدل التراكمي الفصلي درجات تقدير ساعات gpa calculator',
        'icon': Icons.calculate_rounded,
        'color': Colors.lightBlueAccent,
        'action': () {
          close(context, null);
          Navigator.push(context, MaterialPageRoute(builder: (_) => const GpaScreen()));
        },
      },
      {
        'title': AppPrefs.tr('رادار التحضير السريع (نظري / عملي)', 'Fast Attendance Radar'),
        'subtitle': AppPrefs.tr('تسجيل الحضور داخل القاعة أو مجموعات العملي A-D', 'In-class & practical lab attendance'),
        'keywords': 'رادار التحضير الحضور كود بلوتوث عملي نظري مجموعة attendance radar pin',
        'icon': Icons.radar_rounded,
        'color': accent,
        'action': () {
          close(context, null);
          onOpenRadar();
        },
      },
      {
        'title': AppPrefs.tr('بطاقة التحضير الذكية (QR)', 'Smart Attendance QR'),
        'subtitle': AppPrefs.tr('عرض كود QR الشخصي للمندوب', 'Show personal QR badge'),
        'keywords': 'كود باركود بطاقة التحضير qr code',
        'icon': Icons.qr_code_2_rounded,
        'color': accent,
        'action': () {
          close(context, null);
          onOpenQR();
        },
      },
      {
        'title': AppPrefs.tr('سجل حضوري الشخصي', 'My Attendance Log'),
        'subtitle': AppPrefs.tr('عرض عدد المحاضرات التي حضرتها في كل مادة', 'View attended lectures count'),
        'keywords': 'سجل حضوري غياب محاضرات attendance log',
        'icon': Icons.fact_check_rounded,
        'color': Colors.green,
        'action': () {
          close(context, null);
          onOpenAttendanceLog();
        },
      },
      {
        'title': AppPrefs.tr('دردشة الدفعة ودردشة البلوتوث', 'Batch & Offline Bluetooth Chat'),
        'subtitle': AppPrefs.tr('محادثة الدفعة أو التواصل بدون إنترنت داخل القاعة', 'Group chat & offline BLE chat'),
        'keywords': 'دردشة الدفعة محادثة بلوتوث بدون نت رسائل chat bluetooth',
        'icon': Icons.chat_rounded,
        'color': Colors.teal,
        'action': () {
          close(context, null);
          onOpenChat();
        },
      },
      {
        'title': AppPrefs.tr('دليل الدفعة والمناديب', 'Batch Directory & Links'),
        'subtitle': AppPrefs.tr('أرقام التواصل والروابط المهمة للدفعة', 'Contacts & useful batch links'),
        'keywords': 'دليل الدفعة المناديب ارقام روابط تواصل directory contacts links',
        'icon': Icons.contact_phone_rounded,
        'color': Colors.purpleAccent,
        'action': () {
          close(context, null);
          Navigator.push(context, MaterialPageRoute(builder: (_) => const DirectoryScreen()));
        },
      },
      {
        'title': AppPrefs.tr('الإشعارات والتعاميم', 'Notifications & Alerts'),
        'subtitle': AppPrefs.tr('عرض جميع إشعارات وتعاميم الدفعة', 'View all batch announcements & alerts'),
        'keywords': 'الاشعارات التعاميم تنبيهات notifications alerts',
        'icon': Icons.notifications_active_rounded,
        'color': Colors.amber,
        'action': () {
          close(context, null);
          onOpenNotifications();
        },
      },
      {
        'title': AppPrefs.tr('الإعدادات وتحديث البرنامج', 'Settings & Software Update'),
        'subtitle': AppPrefs.tr('تغيير الثيم، الخط، الخلفية، البريد الجامعي، وتحديث التطبيق', 'Themes, fonts, email & updates'),
        'keywords': 'الاعدادات التخصيص ثيم خط خلفية بريد جامعي تحديث البرنامج settings theme update',
        'icon': Icons.settings_rounded,
        'color': Colors.orangeAccent,
        'action': () {
          close(context, null);
          onOpenSettings();
        },
      },
    ];

    if (cleanQ.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            AppPrefs.tr('وصول سريع لأدوات وميزات التطبيق:', 'Quick Access to App Tools & Features:'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          ...appFeatures.map((f) => Card(
                color: cardBg,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: (f['color'] as Color).withOpacity(0.16),
                    child: Icon(f['icon'] as IconData, color: f['color'] as Color, size: 20),
                  ),
                  title: Text(f['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(f['subtitle'] as String, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey),
                  onTap: f['action'] as VoidCallback,
                ),
              )),
        ],
      );
    }

    final List<Widget> results = [];

    void addSectionHeader(String title, IconData icon) {
      results.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: accent)),
            ],
          ),
        ),
      );
    }

    // 1. الأدوات والميزات
    final matchedTools = appFeatures.where((f) {
      final hay = '${f['title']} ${f['subtitle']} ${f['keywords']}'.toLowerCase();
      return hay.contains(cleanQ);
    }).toList();

    if (matchedTools.isNotEmpty) {
      addSectionHeader(AppPrefs.tr('الأدوات والميزات (${matchedTools.length})', 'Tools & Features (${matchedTools.length})'), Icons.widgets_rounded);
      for (final f in matchedTools) {
        results.add(ListTile(
          leading: CircleAvatar(
            backgroundColor: (f['color'] as Color).withOpacity(0.18),
            child: Icon(f['icon'] as IconData, color: f['color'] as Color, size: 20),
          ),
          title: Text(f['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(f['subtitle'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.open_in_new_rounded, size: 18),
          onTap: f['action'] as VoidCallback,
        ));
      }
    }

    // 2. المواد الدراسية
    final matchedSubjects = subjects.where((s) {
      final hay = '${s['name'] ?? ''} ${s['subtitle'] ?? ''}'.toLowerCase();
      return hay.contains(cleanQ);
    }).toList();

    if (matchedSubjects.isNotEmpty) {
      addSectionHeader(AppPrefs.tr('المواد الدراسية (${matchedSubjects.length})', 'Subjects (${matchedSubjects.length})'), Icons.menu_book_rounded);
      for (final s in matchedSubjects) {
        final col = _parseColor(s['color_hex']?.toString());
        results.add(ListTile(
          leading: CircleAvatar(backgroundColor: col.withOpacity(0.2), child: Icon(Icons.menu_book_rounded, color: col)),
          title: Text(s['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text((s['subtitle'] ?? '').toString().isNotEmpty ? s['subtitle'] : AppPrefs.tr('فتح المادة والملفات وبنك الأسئلة', 'Open subject')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            close(context, null);
            Navigator.push(context, MaterialPageRoute(builder: (_) => SubjectScreen(subject: s, defaultColor: col)));
          },
        ));
      }
    }

    // 3. بنك الأسئلة (نص السؤال، الخيارات، أو التوضيح)
    final matchedQuestions = questions.where((q) {
      final optsStr = q['options'] is String ? q['options'] : jsonEncode(q['options'] ?? []);
      final hay = '${q['question_text'] ?? ''} $optsStr ${q['explanation'] ?? ''} ${q['_subjName'] ?? ''}'.toLowerCase();
      return hay.contains(cleanQ);
    }).toList();

    if (matchedQuestions.isNotEmpty) {
      addSectionHeader(AppPrefs.tr('بنك الأسئلة (${matchedQuestions.length})', 'Question Bank (${matchedQuestions.length})'), Icons.quiz_rounded);
      for (final q in matchedQuestions.take(30)) {
        final List<dynamic> opts = q['options'] is String ? jsonDecode(q['options']) : (q['options'] ?? []);
        final int cIdx = q['correct_index'] ?? 0;
        final correctText = (cIdx >= 0 && cIdx < opts.length) ? opts[cIdx].toString() : '';
        final subjObj = q['_subject'];
        final col = _parseColor(q['_colorHex']?.toString());

        results.add(ListTile(
          leading: CircleAvatar(backgroundColor: col.withOpacity(0.2), child: Icon(Icons.help_outline_rounded, color: col)),
          title: Text(q['question_text'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
          subtitle: Text(
            '${q['_subjName']}  •  ✅ $correctText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.greenAccent),
          ),
          onTap: subjObj == null
              ? null
              : () {
                  close(context, null);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => SubjectScreen(subject: subjObj, defaultColor: col)));
                },
        ));
      }
    }

    // 4. الملفات والمحاضرات
    final matchedMaterials = materials.where((m) {
      final hay = '${m['title'] ?? ''} ${m['_subjName'] ?? ''} ${m['file_type'] ?? ''}'.toLowerCase();
      return hay.contains(cleanQ);
    }).toList();

    if (matchedMaterials.isNotEmpty) {
      addSectionHeader(AppPrefs.tr('الملفات والمحاضرات (${matchedMaterials.length})', 'Files & Lectures (${matchedMaterials.length})'), Icons.folder_copy_rounded);
      for (final m in matchedMaterials.take(30)) {
        final subjObj = m['_subject'];
        final col = _parseColor(m['_colorHex']?.toString());
        results.add(ListTile(
          leading: CircleAvatar(backgroundColor: col.withOpacity(0.2), child: Icon(Icons.picture_as_pdf_rounded, color: col)),
          title: Text(m['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${m['_subjName']} • المحاضرة ${m['lecture_number']} (${m['file_type'] ?? 'PDF'})'),
          onTap: subjObj == null
              ? null
              : () {
                  close(context, null);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => SubjectScreen(subject: subjObj, defaultColor: col)));
                },
        ));
      }
    }

    // 5. بطاقات المرجع السريع للمواد (حقيبة المراجعة)
    final matchedRefs = references.where((r) {
      final hay = '${r['title'] ?? ''} ${r['content'] ?? ''}'.toLowerCase();
      return hay.contains(cleanQ);
    }).toList();

    if (matchedRefs.isNotEmpty) {
      addSectionHeader(AppPrefs.tr('مرجع المواد وحقيبة الامتحان (${matchedRefs.length})', 'Subject References (${matchedRefs.length})'), Icons.bookmark_rounded);
      for (final r in matchedRefs) {
        results.add(ListTile(
          leading: const CircleAvatar(backgroundColor: Colors.amber, child: Icon(Icons.bookmark_rounded, color: Colors.black)),
          title: Text(r['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(r['content'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () {
            close(context, null);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ExamNightReviewScreen(subjects: subjects, references: references)),
            );
          },
        ));
      }
    }

    // 6. الإعلانات والتصويتات
    final matchedAnnouncements = announcements.where((a) {
      final pollsStr = a['poll_options'] is List ? (a['poll_options'] as List).join(' ') : '';
      final hay = '${a['title'] ?? ''} ${a['description'] ?? ''} $pollsStr'.toLowerCase();
      return hay.contains(cleanQ);
    }).toList();

    if (matchedAnnouncements.isNotEmpty) {
      addSectionHeader(AppPrefs.tr('الإعلانات والتصويتات (${matchedAnnouncements.length})', 'Announcements & Polls (${matchedAnnouncements.length})'), Icons.campaign_rounded);
      for (final a in matchedAnnouncements) {
        final hasPoll = (a['poll_options'] is List) && (a['poll_options'] as List).isNotEmpty;
        results.add(ListTile(
          leading: CircleAvatar(
            backgroundColor: accent.withOpacity(0.2),
            child: Icon(hasPoll ? Icons.poll_rounded : Icons.campaign_rounded, color: accent),
          ),
          title: Text(a['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(
            hasPoll
                ? (a['poll_options'] as List).join(' • ')
                : ((a['description'] ?? '').toString().isNotEmpty ? a['description'] : AppPrefs.tr('إعلان للدفعة', 'Batch Announcement')),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () {
            close(context, null);
            onOpenAnnouncement(Map<String, dynamic>.from(a));
          },
        ));
      }
    }

    // 7. التكاليف والواجبات
    final matchedAssignments = assignments.where((t) {
      final hay = '${t['subject_name'] ?? ''} ${t['title'] ?? ''} ${t['details'] ?? ''}'.toLowerCase();
      return hay.contains(cleanQ);
    }).toList();

    if (matchedAssignments.isNotEmpty) {
      addSectionHeader(AppPrefs.tr('التكاليف والواجبات (${matchedAssignments.length})', 'Assignments (${matchedAssignments.length})'), Icons.push_pin_rounded);
      for (final t in matchedAssignments) {
        results.add(ListTile(
          leading: const CircleAvatar(backgroundColor: Colors.redAccent, child: Icon(Icons.push_pin_rounded, color: Colors.white)),
          title: Text('${t['subject_name']}: ${t['title']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(t['details'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () {
            close(context, null);
            onSwitchTab(2);
          },
        ));
      }
    }

    // 8. جدول المحاضرات
    final matchedSchedule = schedule.where((sc) {
      final hay = '${sc['subject_name'] ?? ''} ${sc['doctor_name'] ?? ''} ${sc['day_name'] ?? ''} ${sc['hall'] ?? ''}'.toLowerCase();
      return hay.contains(cleanQ);
    }).toList();

    if (matchedSchedule.isNotEmpty) {
      addSectionHeader(AppPrefs.tr('جدول المحاضرات (${matchedSchedule.length})', 'Schedule (${matchedSchedule.length})'), Icons.calendar_today_rounded);
      for (final sc in matchedSchedule) {
        results.add(ListTile(
          leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.calendar_today_rounded, color: Colors.white, size: 18)),
          title: Text('${sc['subject_name']} (${sc['day_name']})', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${sc['time_range']} • ${sc['hall']} • ${sc['doctor_name']}'),
          onTap: () {
            close(context, null);
            onSwitchTab(1);
          },
        ));
      }
    }

    // 9. الإشعارات والتعاميم
    final matchedNotifs = notifications.where((n) {
      final hay = '${n['title'] ?? ''} ${n['body'] ?? ''} ${n['sender_name'] ?? ''}'.toLowerCase();
      return hay.contains(cleanQ);
    }).toList();

    if (matchedNotifs.isNotEmpty) {
      addSectionHeader(AppPrefs.tr('الإشعارات والتعاميم (${matchedNotifs.length})', 'Notifications (${matchedNotifs.length})'), Icons.notifications_rounded);
      for (final n in matchedNotifs) {
        results.add(ListTile(
          leading: const CircleAvatar(backgroundColor: Colors.amber, child: Icon(Icons.notifications_rounded, color: Colors.black)),
          title: Text(n['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(n['body'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () {
            close(context, null);
            onOpenNotifications();
          },
        ));
      }
    }

    return results.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                AppPrefs.tr('لا توجد نتائج مطابقة لـ "$query" في أي قسم من التطبيق', 'No matching results for "$query"'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          )
        : ListView(children: results);
  }
}

/// دردشة الدفعة السريعة (تحديث لحظي فوري بدون تعليق + عرض صورة الملف الشخصي بجانب الرسائل مثل واتساب)
class BatchChatScreen extends StatefulWidget {
  final String studentId;
  final String defaultName;
  final bool isAdmin;
  final String myLocalPhotoPath;
  final String myAvatarUrl;

  const BatchChatScreen({
    super.key,
    required this.studentId,
    required this.defaultName,
    this.isAdmin = false,
    this.myLocalPhotoPath = '',
    this.myAvatarUrl = '',
  });

  @override
  State<BatchChatScreen> createState() => _BatchChatScreenState();
}

class _BatchChatScreenState extends State<BatchChatScreen> {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  late String _nickname;
  bool _isChatMuted = false;
  bool _isLoadingMsgs = true;
  List<Map<String, dynamic>> _messages = [];
  Map<String, String> _avatarsMap = {};
  Map<String, dynamic>? _replyingTo;
  Timer? _chatPollTimer;

  @override
  void initState() {
    super.initState();
    _nickname = widget.defaultName.split(' ').take(2).join(' ');
    _loadMuteState();
    _loadAvatarsMap();
    _fetchMessages(initial: true);
    _chatPollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchMessages());
  }

  @override
  void dispose() {
    _chatPollTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMuteState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isChatMuted = prefs.getBool('notif_batch_chat_muted') ?? false;
    });
  }

  Future<void> _loadAvatarsMap() async {
    try {
      final rows = await Supabase.instance.client.from('students').select('student_id, avatar_url');
      final Map<String, String> map = {};
      for (final r in rows) {
        final sid = (r['student_id'] ?? '').toString();
        final url = (r['avatar_url'] ?? '').toString();
        if (sid.isNotEmpty && url.isNotEmpty) {
          map[sid] = url;
        }
      }
      if (mounted) setState(() => _avatarsMap = map);
    } catch (_) {}
  }

  Future<void> _fetchMessages({bool initial = false}) async {
    try {
      final rows = await Supabase.instance.client
          .from('chat_messages')
          .select()
          .order('created_at', ascending: true)
          .limit(150);

      if (!mounted) return;
      final list = rows.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();
      final hadDifferentLen = list.length != _messages.length;

      setState(() {
        _messages = list;
        _isLoadingMsgs = false;
      });

      if ((initial || hadDifferentLen) && _scrollCtrl.hasClients) {
        Future.delayed(const Duration(milliseconds: 120), () {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
          }
        });
      }
    } catch (_) {
      if (mounted && _isLoadingMsgs) {
        setState(() => _isLoadingMsgs = false);
      }
    }
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

  String _formatMsgTime(dynamic rawDate) {
    if (rawDate == null) return '';
    try {
      final dt = DateTime.parse(rawDate.toString()).toLocal();
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final min = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'م' : 'ص';
      return '$hour:$min $period';
    } catch (_) {
      return '';
    }
  }

  Future<void> _toggleReaction(Map<String, dynamic> msg, String emoji) async {
    try {
      final Map<String, dynamic> current = Map<String, dynamic>.from(msg['reactions'] ?? {});
      final List<dynamic> users = List<dynamic>.from(current[emoji] ?? []);
      if (users.contains(widget.studentId)) {
        users.remove(widget.studentId);
      } else {
        users.add(widget.studentId);
      }
      if (users.isEmpty) {
        current.remove(emoji);
      } else {
        current[emoji] = users;
      }
      await Supabase.instance.client
          .from('chat_messages')
          .update({'reactions': current})
          .eq('id', msg['id']);
      await _fetchMessages();
    } catch (_) {}
  }

  Future<void> _deleteMessage(dynamic msgId) async {
    try {
      await Supabase.instance.client.from('chat_messages').delete().eq('id', msgId);
      await _fetchMessages();
    } catch (_) {}
  }

  void _showMessageOptions(Map<String, dynamic> msg, bool isMe) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ['👍', '❤️', '😂', '🙏', '🔥'].map((em) {
                return InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleReaction(msg, em);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(em, style: const TextStyle(fontSize: 28)),
                  ),
                );
              }).toList(),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.reply_rounded, color: Colors.teal),
              title: Text(AppPrefs.tr('رد على الرسالة', 'Reply')),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _replyingTo = msg);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text(AppPrefs.tr('نسخ النص', 'Copy Text')),
              onTap: () {
                Clipboard.setData(ClipboardData(text: (msg['message'] ?? '').toString()));
                Navigator.pop(ctx);
              },
            ),
            if (isMe || widget.isAdmin)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                title: Text(AppPrefs.tr('حذف الرسالة', 'Delete Message'), style: const TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMessage(msg['id']);
                },
              ),
          ],
        ),
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

    final replySnapshot = _replyingTo;
    _msgCtrl.clear();
    setState(() {
      _replyingTo = null;
      _messages.add({
        'student_id': widget.studentId,
        'nickname': _nickname,
        'message': text,
        'created_at': DateTime.now().toIso8601String(),
        if (replySnapshot != null) 'reply_to_name': replySnapshot['nickname'],
        if (replySnapshot != null) 'reply_to_text': replySnapshot['message'],
      });
    });

    if (_scrollCtrl.hasClients) {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        }
      });
    }

    final payload = <String, dynamic>{
      'student_id': widget.studentId,
      'nickname': _nickname,
      'message': text,
    };

    if (replySnapshot != null) {
      payload['reply_to_id'] = replySnapshot['id'];
      payload['reply_to_name'] = replySnapshot['nickname'];
      payload['reply_to_text'] = replySnapshot['message'];
    }

    try {
      await Supabase.instance.client.from('chat_messages').insert(payload);
    } catch (_) {
      try {
        await Supabase.instance.client.from('chat_messages').insert({
          'student_id': widget.studentId,
          'nickname': _nickname,
          'message': text,
        });
      } catch (_) {}
    }
    await _fetchMessages();
  }

  Widget _buildSenderAvatar(String senderId, String senderName, Color accent, bool isMe) {
    ImageProvider? img;
    if (isMe && widget.myLocalPhotoPath.isNotEmpty && !kIsWeb && File(widget.myLocalPhotoPath).existsSync()) {
      img = FileImage(File(widget.myLocalPhotoPath));
    } else if (isMe && widget.myAvatarUrl.isNotEmpty) {
      img = NetworkImage(widget.myAvatarUrl);
    } else if (_avatarsMap.containsKey(senderId) && _avatarsMap[senderId]!.isNotEmpty) {
      img = NetworkImage(_avatarsMap[senderId]!);
    }

    final initial = senderName.trim().isNotEmpty ? senderName.trim().characters.first : '؟';

    return CircleAvatar(
      radius: 16,
      backgroundColor: accent.withOpacity(0.2),
      backgroundImage: img,
      child: img == null
          ? Text(initial, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accent))
          : null,
    );
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
            Text(AppPrefs.tr('دردشة الدفعة', 'Batch Chat'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              AppPrefs.tr('اضغط مطولاً على أي رسالة للرد أو التفاعل', 'Long-press any message to reply or react'),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: AppPrefs.tr('وضع البلوتوث (بدون إنترنت داخل القاعة)', 'Offline Bluetooth Chat'),
            icon: Icon(Icons.bluetooth_audio_rounded, color: accent),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OfflineBluetoothChatScreen(
                    studentId: widget.studentId,
                    nickname: _nickname,
                  ),
                ),
              );
            },
          ),
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
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'name') {
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
              } else if (val == 'ble') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OfflineBluetoothChatScreen(
                      studentId: widget.studentId,
                      nickname: _nickname,
                    ),
                  ),
                );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'ble', child: Text(AppPrefs.tr('📡 دردشة البلوتوث (بدون نت)', '📡 Offline Bluetooth Chat'))),
              PopupMenuItem(value: 'name', child: Text(AppPrefs.tr('✏️ تغيير الاسم المستعار', '✏️ Edit Nickname'))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoadingMsgs
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          AppPrefs.tr('لا توجد رسائل بعد. ابدأ المحادثة مع دفعتك الآن!', 'No messages yet. Say hi to your batch!'),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) {
                          final m = _messages[i];
                          final senderId = (m['student_id'] ?? '').toString();
                          final senderName = (m['nickname'] ?? '').toString();
                          final isMe = senderId == widget.studentId;
                          final replyName = (m['reply_to_name'] ?? '').toString();
                          final replyText = (m['reply_to_text'] ?? '').toString();
                          final Map<String, dynamic> reactions = Map<String, dynamic>.from(m['reactions'] ?? {});

                          final bubbleColor = isMe
                              ? (isDark ? const Color(0xFF005C4B) : const Color(0xFFD9FDD3))
                              : cardBg;

                          final bubble = Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                            decoration: BoxDecoration(
                              color: bubbleColor,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(isMe ? 16 : 4),
                                bottomRight: Radius.circular(isMe ? 4 : 16),
                              ),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 3, offset: const Offset(0, 1)),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!isMe)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: Text(
                                      senderName,
                                      style: TextStyle(fontSize: 11.5, color: accent, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                if (replyText.isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border(right: BorderSide(color: accent, width: 3)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(replyName, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: accent)),
                                        Text(replyText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
                                      ],
                                    ),
                                  ),
                                Text(
                                  m['message'] ?? '',
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    height: 1.35,
                                    color: isMe && !isDark ? Colors.black87 : null,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _formatMsgTime(m['created_at']),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isMe && !isDark ? Colors.black54 : Colors.grey,
                                      ),
                                    ),
                                    if (isMe) ...[
                                      const SizedBox(width: 4),
                                      Icon(Icons.done_all_rounded, size: 14, color: isDark ? Colors.lightBlueAccent : Colors.blue),
                                    ],
                                  ],
                                ),
                                if (reactions.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Wrap(
                                      spacing: 4,
                                      children: reactions.entries.map((e) {
                                        final count = (e.value as List).length;
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.18),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text('${e.key} $count', style: const TextStyle(fontSize: 11)),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                              ],
                            ),
                          );

                          return GestureDetector(
                            onLongPress: () => _showMessageOptions(m, isMe),
                            onHorizontalDragEnd: (_) => setState(() => _replyingTo = m),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(
                                mainAxisAlignment: isMe ? MainAxisAlignment.start : MainAxisAlignment.end,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: isMe
                                    ? [
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 10, left: 6),
                                          child: _buildSenderAvatar(senderId, senderName, accent, true),
                                        ),
                                        bubble,
                                      ]
                                    : [
                                        bubble,
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 10, right: 6),
                                          child: _buildSenderAvatar(senderId, senderName, accent, false),
                                        ),
                                      ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: cardBg,
              child: Row(
                children: [
                  Container(width: 4, height: 34, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${AppPrefs.tr('الرد على', 'Replying to')} ${_replyingTo!['nickname']}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accent),
                        ),
                        Text(
                          (_replyingTo!['message'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() => _replyingTo = null),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: cardBg,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _msgCtrl,
                      decoration: InputDecoration(
                        hintText: AppPrefs.tr('اكتب رسالة...', 'Type a message...'),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                CircleAvatar(
                  backgroundColor: accent,
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded, color: Colors.black, size: 20),
                    onPressed: _sendMessage,
                  ),
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
