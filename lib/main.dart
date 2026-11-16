import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// بيانات الربط الخاصة بمشروعك في Supabase
const String supabaseUrl = 'https://stvavavzjrcxcivxykfv.supabase.co';
const String supabaseAnonKey = 'sb_publishable_2D5B4SJgPAwqZqqgpiFaMA_HzTlka-k';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  final prefs = await SharedPreferences.getInstance();
  final bool isRegistered = prefs.getBool('is_registered') ?? false;

  runApp(IQPharmacyApp(isRegistered: isRegistered));
}

class IQPharmacyApp extends StatelessWidget {
  final bool isRegistered;
  const IQPharmacyApp({super.key, required this.isRegistered});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IQ_Pharmacy39',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'YE'),
      supportedLocales: const [Locale('ar', 'YE'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        primaryColor: const Color(0xFF2B6CB0),
        cardColor: const Color(0xFF181B20),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4FD1C5),
          secondary: Color(0xFF2B6CB0),
        ),
      ),
      home: isRegistered ? const MainDashboardPlaceholder() : const StudentRegistrationScreen(),
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

  // طلب أذونات الإشعارات والتخزين عند فتح التطبيق
  Future<void> _requestAppPermissions() async {
    await [
      Permission.notification,
      Permission.storage,
    ].request();
  }

  // الحصول على بصمة الجهاز الفريدة لقفل الحساب
  Future<String> _getDeviceId() async {
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

  // البحث عن رقم القيد في قاعدة البيانات (يتطلب إنترنت)
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

      // التحقق مما إذا كان رقم القيد مرتبطاً بجهاز آخر مسبقاً
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

  // تأكيد الهوية وقفل رقم القيد بالجهاز نهائياً
  Future<void> _confirmAndLockAccount() async {
    if (_foundStudent == null) return;
    setState(() => _isLoading = true);

    try {
      final String currentDeviceId = await _getDeviceId();
      final String studentId = _foundStudent!['student_id'];

      // تحديث قاعدة البيانات لقفل الرقم بهذا الجهاز
      await Supabase.instance.client
          .from('students')
          .update({'device_id': currentDeviceId})
          .eq('student_id', studentId);

      // حفظ البيانات محلياً للعمل بدون إنترنت مستقبلاً
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_registered', true);
      await prefs.setString('student_id', studentId);
      await prefs.setString('full_name', _foundStudent!['full_name']);
      await prefs.setBool('is_admin', _foundStudent!['is_admin'] ?? false);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainDashboardPlaceholder()),
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: _foundStudent == null ? _buildInputStep() : _buildConfirmationStep(),
          ),
        ),
      ),
    );
  }

  // واجهة إدخال رقم القيد
  Widget _buildInputStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF181B20),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF4FD1C5), width: 2),
          ),
          child: const Icon(Icons.school_rounded, size: 60, color: Color(0xFF4FD1C5)),
        ),
        const SizedBox(height: 24),
        const Text(
          'IQ_Pharmacy39',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
        ),
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
            fillColor: const Color(0xFF181B20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF4FD1C5), width: 1.5),
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
            child: Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyStudentId,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4FD1C5),
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

  // واجهة الترحيب وخياري (متابعة للتطبيق / لست أنا)
  Widget _buildConfirmationStep() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF181B20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          const Icon(Icons.verified_user_rounded, size: 64, color: Color(0xFF4FD1C5)),
          const SizedBox(height: 16),
          const Text('مرحباً بك', style: TextStyle(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 8),
          Text(
            _foundStudent!['full_name'],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'رقم القيد: ${_foundStudent!['student_id']}',
            style: const TextStyle(fontSize: 14, color: Color(0xFF4FD1C5)),
          ),
          const SizedBox(height: 20),
          const Text(
            'تنبيه: عند الضغط على "متابعة للتطبيق" سيتم ربط رقم قيدك بهذا الهاتف نهائياً ولن يتمكن أي شخص آخر من استخدامه.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.amberAccent, height: 1.4),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _confirmAndLockAccount,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4FD1C5),
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

// شاشة مؤقتة سنستبدلها في المرحلة الثالثة بالواجهة الرئيسية الكاملة
class MainDashboardPlaceholder extends StatelessWidget {
  const MainDashboardPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('تم الدخول بنجاح! جاهز للمرحلة الثالثة')),
    );
  }
}
