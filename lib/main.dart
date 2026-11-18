import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_prefs.dart';
import 'home_screen.dart';

const String supabaseUrl = 'https://stvavavzjrcxcivxykfv.supabase.co';
const String supabaseAnonKey = 'sb_publishable_2D5B4SJgPAwqZqqgpiFaMA_HzTlka-k';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  await AppPrefs.load();
  final prefs = await SharedPreferences.getInstance();
  final bool isRegistered = prefs.getBool('is_registered') ?? false;

  runApp(IQPharmacyApp(isRegistered: isRegistered));
}

class IQPharmacyApp extends StatelessWidget {
  final bool isRegistered;
  const IQPharmacyApp({super.key, required this.isRegistered});

  ThemeData _buildTheme() {
    final preset = AppPrefs.themePreset;
    final hasWallpaper = AppPrefs.wallpaperType != 'none';

    if (preset == 'light') {
      final base = ThemeData.light(useMaterial3: true);
      return base.copyWith(
        scaffoldBackgroundColor: hasWallpaper ? Colors.transparent : const Color(0xFFF3F5F8),
        primaryColor: const Color(0xFF0D9488),
        cardColor: hasWallpaper ? Colors.white.withOpacity(0.92) : Colors.white,
        textTheme: AppPrefs.applyFontToTextTheme(base.textTheme),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0D9488),
          secondary: Color(0xFF2B6CB0),
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
        ),
      );
    }

    if (preset == 'amoled') {
      final base = ThemeData.dark(useMaterial3: true);
      return base.copyWith(
        scaffoldBackgroundColor: hasWallpaper ? Colors.transparent : Colors.black,
        primaryColor: const Color(0xFF4FD1C5),
        cardColor: hasWallpaper ? const Color(0xFF111317).withOpacity(0.88) : const Color(0xFF111317),
        textTheme: AppPrefs.applyFontToTextTheme(base.textTheme),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4FD1C5),
          secondary: Color(0xFF38B2AC),
          surface: Color(0xFF111317),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      );
    }

    if (preset == 'pharmacy') {
      final base = ThemeData.dark(useMaterial3: true);
      return base.copyWith(
        scaffoldBackgroundColor: hasWallpaper ? Colors.transparent : const Color(0xFF071A19),
        primaryColor: const Color(0xFF2DD4BF),
        cardColor: hasWallpaper ? const Color(0xFF0F2927).withOpacity(0.88) : const Color(0xFF0F2927),
        textTheme: AppPrefs.applyFontToTextTheme(base.textTheme),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2DD4BF),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF0F2927),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B2220),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      );
    }

    // الافتراضي: dark
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: hasWallpaper ? Colors.transparent : const Color(0xFF0F1115),
      primaryColor: const Color(0xFF2B6CB0),
      cardColor: hasWallpaper ? const Color(0xFF181B20).withOpacity(0.88) : const Color(0xFF181B20),
      textTheme: AppPrefs.applyFontToTextTheme(base.textTheme),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF4FD1C5),
        secondary: Color(0xFF2B6CB0),
        surface: Color(0xFF181B20),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF181B20),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppPrefs.settingsNotifier,
      builder: (_, __, ___) {
        return ValueListenableBuilder<Locale>(
          valueListenable: AppPrefs.localeNotifier,
          builder: (_, currentLocale, __) {
            final activeTheme = _buildTheme();
            final Widget initialPage = !isRegistered
                ? const StudentRegistrationScreen()
                : (AppPrefs.pinEnabled && AppPrefs.appPin.isNotEmpty)
                    ? const PinLockScreen()
                    : const HomeScreen();

            return MaterialApp(
              title: 'IQ_Pharmacy39',
              debugShowCheckedModeBanner: false,
              themeMode: AppPrefs.isDark ? ThemeMode.dark : ThemeMode.light,
              locale: currentLocale,
              supportedLocales: const [Locale('ar'), Locale('en')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: activeTheme,
              darkTheme: activeTheme,
              builder: (context, child) {
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(AppPrefs.fontScale),
                  ),
                  child: child ?? const SizedBox.shrink(),
                );
              },
              home: initialPage,
            );
          },
        );
      },
    );
  }
}

// شاشة القفل برمز PIN مع ميزة استعادة الرمز
class PinLockScreen extends StatefulWidget {
  const PinLockScreen({super.key});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  final TextEditingController _pinCtrl = TextEditingController();
  String? _error;

  void _checkPin() {
    if (_pinCtrl.text.trim() == AppPrefs.appPin) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      setState(() {
        _error = AppPrefs.tr('رمز المرور غير صحيح', 'Incorrect PIN');
        _pinCtrl.clear();
      });
    }
  }

  Future<void> _openForgotPinDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final savedStudentId = prefs.getString('student_id') ?? '';
    final idCtrl = TextEditingController();
    final newPinCtrl = TextEditingController();
    bool verifying = false;
    String? dialogError;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(AppPrefs.tr('استعادة رمز المرور (PIN)', 'Reset App PIN')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppPrefs.tr(
                  'أدخل رقم قيدك الجامعي المسجل على هذا الهاتف للتحقق من هويتك وتعيين رمز جديد:',
                  'Enter your registered student ID to verify identity and set a new PIN:',
                ),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: idCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: AppPrefs.tr('رقم القيد الجامعي', 'Student ID'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newPinCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: AppPrefs.tr('رمز المرور الجديد (4-6 أرقام)', 'New PIN (4-6 digits)'),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (dialogError != null) ...[
                const SizedBox(height: 6),
                Text(dialogError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: verifying ? null : () => Navigator.pop(ctx),
              child: Text(AppPrefs.tr('إلغاء', 'Cancel')),
            ),
            ElevatedButton(
              onPressed: verifying
                  ? null
                  : () async {
                      final enteredId = idCtrl.text.trim();
                      final newPin = newPinCtrl.text.trim();
                      if (enteredId.isEmpty || newPin.length < 4) {
                        setDialogState(() => dialogError = AppPrefs.tr('أدخل رقم القيد ورمزاً من 4 أرقام على الأقل', 'Enter valid ID and 4+ digit PIN'));
                        return;
                      }
                      if (savedStudentId.isNotEmpty && enteredId != savedStudentId) {
                        setDialogState(() => dialogError = AppPrefs.tr('رقم القيد لا يطابق الحساب المسجل في هذا الهاتف', 'Student ID does not match this device'));
                        return;
                      }
                      setDialogState(() {
                        verifying = true;
                        dialogError = null;
                      });
                      try {
                        final res = await Supabase.instance.client
                            .from('students')
                            .select('student_id')
                            .eq('student_id', enteredId)
                            .maybeSingle();
                        if (res == null) {
                          setDialogState(() {
                            verifying = false;
                            dialogError = AppPrefs.tr('رقم القيد غير موجود في قاعدة البيانات', 'Student ID not found');
                          });
                          return;
                        }
                        await AppPrefs.setAppPin(true, newPin);
                        if (!mounted) return;
                        Navigator.pop(ctx);
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const HomeScreen()),
                        );
                      } catch (_) {
                        setDialogState(() {
                          verifying = false;
                          dialogError = AppPrefs.tr('تعذر التحقق، تأكد من اتصالك بالإنترنت', 'Connection failed, check internet');
                        });
                      }
                    },
              child: verifying
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(AppPrefs.tr('تأكيد وتغيير الرمز', 'Verify & Reset')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final cardBg = Theme.of(context).cardColor;

    return Scaffold(
      backgroundColor: AppPrefs.isDark ? const Color(0xFF0F1115) : const Color(0xFFF3F5F8),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_rounded, size: 64, color: accent),
                const SizedBox(height: 16),
                Text(
                  AppPrefs.tr('التطبيق مقفل', 'App Locked'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  AppPrefs.tr('أدخل رمز المرور (PIN) للمتابعة', 'Enter your PIN to continue'),
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _pinCtrl,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    style: const TextStyle(fontSize: 24, letterSpacing: 6, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '••••',
                      filled: true,
                      fillColor: cardBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onSubmitted: (_) => _checkPin(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: 220,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _checkPin,
                    child: Text(AppPrefs.tr('دخول', 'Unlock'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: _openForgotPinDialog,
                  child: Text(
                    AppPrefs.tr('نسيت رمز المرور؟', 'Forgot PIN?'),
                    style: TextStyle(color: accent, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StudentRegistrationScreen extends StatefulWidget {
  const StudentRegistrationScreen({super.key});

  @override
  State<StudentRegistrationScreen> createState() => _StudentRegistrationScreenState();
}

class _StudentRegistrationScreenState extends State<StudentRegistrationScreen> {
  final TextEditingController _idController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _foundStudent;

  @override
  void initState() {
    super.initState();
    _requestAppPermissions();
  }

  Future<void> _requestAppPermissions() async {
    if (kIsWeb) return;
    await [Permission.notification, Permission.storage].request();
  }

  Future<String> _getDeviceId() async {
    if (kIsWeb) return 'web_browser_device';
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id;
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? 'ios_unknown';
    }
    return 'unknown_device';
  }

  Future<void> _showAboutAppDialog() async {
    String aboutText = 'تطبيق IQ_Pharmacy39 هو البوابة الدراسية المتكاملة لطلاب الدفعة 39 صيدلة إكلينيكية - جامعة صنعاء، ويشمل المحاضرات، الجداول، التكاليف، التحضير الذكي، وبنوك الأسئلة.';
    String devName = 'فريق التطوير - دفعة 39 صيدلة';
    String whatsappUrl = '';
    String telegramUrl = '';

    try {
      final res = await Supabase.instance.client
          .from('app_settings')
          .select('value')
          .eq('key', 'about_app_info')
          .maybeSingle();
      if (res != null && res['value'] != null && res['value'].toString().isNotEmpty) {
        final data = jsonDecode(res['value']);
        if ((data['about'] ?? '').toString().isNotEmpty) aboutText = data['about'];
        if ((data['developer'] ?? '').toString().isNotEmpty) devName = data['developer'];
        whatsappUrl = (data['whatsapp'] ?? '').toString();
        telegramUrl = (data['telegram'] ?? '').toString();
      }
    } catch (_) {}

    if (!mounted) return;
    final accent = Theme.of(context).colorScheme.primary;
    final cardBg = Theme.of(context).cardColor;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: accent),
            const SizedBox(width: 8),
            const Text('نبذة عن التطبيق والمطور', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(aboutText, style: const TextStyle(fontSize: 13, height: 1.6)),
            const Divider(height: 24),
            Text('تطوير وإشراف:', style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(devName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            if (whatsappUrl.isNotEmpty || telegramUrl.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  if (whatsappUrl.isNotEmpty)
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        icon: const Icon(Icons.chat, size: 16),
                        label: const Text('واتساب', style: TextStyle(fontSize: 12)),
                        onPressed: () => launchUrl(Uri.parse(whatsappUrl), mode: LaunchMode.externalApplication),
                      ),
                    ),
                  if (whatsappUrl.isNotEmpty && telegramUrl.isNotEmpty) const SizedBox(width: 8),
                  if (telegramUrl.isNotEmpty)
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                        icon: const Icon(Icons.send, size: 16),
                        label: const Text('تيليجرام', style: TextStyle(fontSize: 12)),
                        onPressed: () => launchUrl(Uri.parse(telegramUrl), mode: LaunchMode.externalApplication),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyStudentId() async {
    final studentId = _idController.text.trim();
    if (studentId.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال رقم القيد الجامعي أولاً');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await Supabase.instance.client
          .from('students')
          .select()
          .eq('student_id', studentId)
          .maybeSingle();

      if (response == null) {
        setState(() {
          _errorMessage = 'رقم القيد غير مسجل في كشوفات الدفعة، تأكد من الرقم أو تواصل مع المندوب.';
          _isLoading = false;
        });
        return;
      }

      final String currentDeviceId = await _getDeviceId();
      final String? registeredDevice = response['device_id'];

      if (registeredDevice != null && registeredDevice != currentDeviceId) {
        setState(() {
          _errorMessage = 'عذراً، هذا الرقم مرتبط بهاتف آخر مسبقاً ولا يمكن استخدامه مرتين.';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _foundStudent = response;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'تعذر الاتصال بالخادم. يرجى التأكد من اتصالك بالإنترنت للمرة الأولى.';
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmAndLockAccount() async {
    if (_foundStudent == null) return;
    setState(() => _isLoading = true);

    try {
      final String currentDeviceId = await _getDeviceId();
      final String studentId = _foundStudent!['student_id'];

      await Supabase.instance.client
          .from('students')
          .update({'device_id': currentDeviceId})
          .eq('student_id', studentId);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_registered', true);
      await prefs.setString('student_id', studentId);
      await prefs.setString('full_name', _foundStudent!['full_name']);
      await prefs.setBool('is_admin', _foundStudent!['is_admin'] ?? false);
      if (_foundStudent!['university_email'] != null) {
        await prefs.setString('university_email', _foundStudent!['university_email'].toString());
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ أثناء تثبيت الحساب، تأكد من الإنترنت وحاول مجدداً.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Theme.of(context).cardColor;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      body: SafeArea(
        child: Column(
          children: [
            // زر نبذة عن التطبيق والمطور في الأعلى
            Padding(
              padding: const EdgeInsets.only(top: 12, left: 16, right: 16),
              child: Align(
                alignment: Alignment.topRight,
                child: InkWell(
                  onTap: _showAboutAppDialog,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: accent.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: accent),
                        const SizedBox(width: 6),
                        Text(
                          'نبذة عن التطبيق • المطور',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accent),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: _foundStudent == null
                      ? _buildInputStep(cardBg, accent)
                      : _buildConfirmationStep(cardBg, accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputStep(Color cardBg, Color accent) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardBg,
            shape: BoxShape.circle,
            border: Border.all(color: accent, width: 2),
          ),
          child: Icon(Icons.school_rounded, size: 60, color: accent),
        ),
        const SizedBox(height: 24),
        const Text('IQ_Pharmacy39', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          'أدخل رقم قيدك الجامعي للتعرف على حسابك\n(تتطلب هذه الخطوة اتصالاً بالإنترنت لمرة واحدة فقط)',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.5),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _idController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, letterSpacing: 2, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: 'رقم القيد الجامعي',
            filled: true,
            fillColor: cardBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: accent, width: 1.5),
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.redAccent),
            ),
            child: Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyStudentId,
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.black)
                : const Text('تحقق من رقم القيد', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmationStep(Color cardBg, Color accent) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(Icons.verified_user_rounded, size: 64, color: accent),
          const SizedBox(height: 16),
          const Text('مرحباً بك', style: TextStyle(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 8),
          Text(_foundStudent!['full_name'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('رقم القيد: ${_foundStudent!['student_id']}', style: TextStyle(fontSize: 14, color: accent, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          const Text(
            'تنبيه: عند الضغط على "متابعة للتطبيق" سيتم ربط رقم قيدك بهذا الهاتف نهائياً ولن يتمكن أي شخص آخر من استخدامه.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.orange, height: 1.4),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _confirmAndLockAccount,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.black)
                  : const Text('متابعة للتطبيق', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      setState(() {
                        _foundStudent = null;
                        _idController.clear();
                        _errorMessage = null;
                      });
                    },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('لست أنا', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
