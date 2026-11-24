import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_prefs.dart';

typedef RadarStudentRecord = Map<String, String>;
typedef BleChatMessage = Map<String, String>;

class RadarCrypto {
  static const int _secretSeed = 3970241;
  static const int slotDurationMs = 10000; // يتغير الكود كل 10 ثوانٍ

  static int currentSlot() => DateTime.now().millisecondsSinceEpoch ~/ slotDurationMs;

  static String generatePinForSlot(String sessionCode, int slot) {
    int hash = _secretSeed ^ (slot * 2654435761);
    for (int i = 0; i < sessionCode.length; i++) {
      hash = ((hash << 5) - hash) + sessionCode.codeUnitAt(i);
      hash &= 0x7FFFFFFF;
    }
    final code = (hash % 9000) + 1000;
    return code.toString();
  }

  static String currentPin(String sessionCode) =>
      generatePinForSlot(sessionCode, currentSlot());

  static bool verifyPin(String sessionCode, String inputPin) {
    final clean = inputPin.trim();
    if (clean.length != 4) return false;
    final slot = currentSlot();
    // يقبل الكود الحالي أو الكود السابق مباشرة (فترة سماح 10 ثوانٍ إضافية أثناء الكتابة)
    return clean == generatePinForSlot(sessionCode, slot) ||
        clean == generatePinForSlot(sessionCode, slot - 1);
  }

  static int secondsRemainingInSlot() {
    final ms = DateTime.now().millisecondsSinceEpoch % slotDurationMs;
    return 10 - (ms ~/ 1000);
  }
}

class BleSafeHelper {
  static Future<bool> prepareBluetooth() async {
    if (kIsWeb) return false;
    try {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      final hasPerm = statuses[Permission.bluetoothScan]?.isGranted == true ||
          statuses[Permission.bluetooth]?.isGranted == true ||
          statuses[Permission.locationWhenInUse]?.isGranted == true;
      if (!hasPerm) return false;

      final state = await FlutterBluePlus.adapterState.first
          .timeout(const Duration(seconds: 2), onTimeout: () => BluetoothAdapterState.unknown);
      return state == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  static Uint8List safeAsciiBytes(String text, {int maxBytes = 20}) {
    final clean = text.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
    final bytes = utf8.encode(clean);
    if (bytes.length <= maxBytes) return Uint8List.fromList(bytes);
    return Uint8List.fromList(bytes.sublist(0, maxBytes));
  }

  static Uint8List safeUtf8Bytes(String text, {int maxBytes = 22}) {
    final bytes = utf8.encode(text);
    if (bytes.length <= maxBytes) return Uint8List.fromList(bytes);
    return Uint8List.fromList(bytes.sublist(0, maxBytes));
  }
}

class AdminRadarScreen extends StatefulWidget {
  final String adminName;
  const AdminRadarScreen({super.key, required this.adminName});

  @override
  State<AdminRadarScreen> createState() => _AdminRadarScreenState();
}

class _AdminRadarScreenState extends State<AdminRadarScreen> {
  static const int _attManufacturerId = 0x3939;
  static const List<String> _practicalGroups = ['مجموعة A', 'مجموعة B', 'مجموعة C', 'مجموعة D'];

  final TextEditingController _subjectCtrl = TextEditingController();
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  String _lectureType = 'نظري';
  String _selectedGroup = 'مجموعة A';
  int _selectedMinutes = 5;
  bool _isRadarActive = false;
  int _remainingSeconds = 300;
  String _activePin = '----';
  int _pinSecondsLeft = 10;
  bool _bleAdvertising = false;

  Timer? _mainTimer;
  StreamSubscription<List<ScanResult>>? _scanSub;
  final Map<String, RadarStudentRecord> _capturedStudents = {};
  Map<String, String> _studentsDirectory = {};
  bool _isUploading = false;

  String get _fullSessionLabel {
    final base = _subjectCtrl.text.trim();
    if (base.isEmpty) return '';
    if (_lectureType == 'عملي') {
      return '$base - عملي ($_selectedGroup)';
    }
    return '$base - نظري';
  }

  @override
  void initState() {
    super.initState();
    _loadStudentsDirectory();
  }

  @override
  void dispose() {
    _stopRadar(silent: true);
    _subjectCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStudentsDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('cache_students_dir');
    if (cached != null && cached.isNotEmpty) {
      try {
        _studentsDirectory = Map<String, String>.from(jsonDecode(cached));
      } catch (_) {}
    }
    try {
      final rows = await Supabase.instance.client.from('students').select('student_id, full_name');
      final Map<String, String> fresh = {};
      for (final r in rows) {
        final id = (r['student_id'] ?? '').toString().trim();
        final name = (r['full_name'] ?? '').toString().trim();
        if (id.isNotEmpty && name.isNotEmpty) fresh[id] = name;
      }
      if (fresh.isNotEmpty) {
        _studentsDirectory = fresh;
        await prefs.setString('cache_students_dir', jsonEncode(fresh));
      }
    } catch (_) {}
  }

  Future<void> _startRadar() async {
    final session = _fullSessionLabel;
    if (session.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى كتابة اسم المادة أولاً'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    final btReady = await BleSafeHelper.prepareBluetooth();
    if (!btReady && !kIsWeb && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('زر البلوتوث مغلق في هاتفك: تم تشغيل الكود الرباعي، وشغّل البلوتوث للالتقاط التلقائي.'),
          backgroundColor: Colors.orange,
        ),
      );
    }

    setState(() {
      _isRadarActive = true;
      _remainingSeconds = _selectedMinutes == 0 ? 86400 : _selectedMinutes * 60;
      _activePin = RadarCrypto.currentPin(session);
      _pinSecondsLeft = RadarCrypto.secondsRemainingInSlot();
    });

    if (btReady) {
      try {
        final supported = await _peripheral.isSupported;
        if (supported) {
          final advData = AdvertiseData(
            includeDeviceName: false,
            manufacturerId: _attManufacturerId,
            manufacturerData: BleSafeHelper.safeAsciiBytes('ADM|${session.hashCode.abs() % 99999}'),
          );
          await _peripheral.start(advertiseData: advData);
          if (mounted) setState(() => _bleAdvertising = true);
        }
      } catch (_) {}

      try {
        await FlutterBluePlus.startScan(continuousUpdates: true);
        _scanSub = FlutterBluePlus.scanResults.listen((results) {
          for (final r in results) {
            final rawBytes = r.advertisementData.manufacturerData[_attManufacturerId];
            if (rawBytes != null) {
              final payload = utf8.decode(rawBytes, allowMalformed: true);
              if (payload.startsWith('S|')) {
                final sid = payload.substring(2).trim();
                if (sid.isNotEmpty && !_capturedStudents.containsKey(sid) && mounted) {
                  final fullName = _studentsDirectory[sid] ?? 'طالب ($sid)';
                  setState(() {
                    _capturedStudents[sid] = {
                      'student_id': sid,
                      'full_name': fullName,
                      'method': 'رادار بلوتوث 📡',
                    };
                  });
                }
              }
            }
          }
        });
      } catch (_) {}
    }

    _mainTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final newPin = RadarCrypto.currentPin(session);
      final pinLeft = RadarCrypto.secondsRemainingInSlot();

      setState(() {
        _activePin = newPin;
        _pinSecondsLeft = pinLeft;
        if (_selectedMinutes > 0) {
          _remainingSeconds--;
          if (_remainingSeconds <= 0) {
            _stopRadar();
          }
        }
      });
    });
  }

  Future<void> _stopRadar({bool silent = false}) async {
    _mainTimer?.cancel();
    _scanSub?.cancel();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    try {
      await _peripheral.stop();
    } catch (_) {}

    if (!silent && mounted) {
      setState(() {
        _isRadarActive = false;
        _bleAdvertising = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إيقاف رادار التحضير'), backgroundColor: Colors.teal),
      );
    }
  }

  Future<void> _syncCapturedToCloud() async {
    if (_capturedStudents.isEmpty || _isUploading) return;
    setState(() => _isUploading = true);
    final session = _fullSessionLabel;

    try {
      final rows = _capturedStudents.values
          .map((e) => {
                'student_id': e['student_id'],
                'full_name': e['full_name'],
                'session_code': session,
              })
          .toList();

      await Supabase.instance.client.from('attendance').insert(rows);
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم رفع واعتماد حضور (${rows.length}) طالب في ($session) بنجاح ✓'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر الرفع حالياً (لا يوجد إنترنت). أبقِ الشاشة مفتوحة وارفع الكشف فور توفر الشبكة.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  String _formatCountdown(int totalSec) {
    final m = (totalSec ~/ 60).toString().padLeft(2, '0');
    final s = (totalSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Theme.of(context).cardColor;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('رادار التحضير الفائق (نظري / عملي)'),
      ),
      body: ListView(
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
                  const Text('إعداد جلسة التحضير داخل القاعة أو المعمل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _subjectCtrl,
                    enabled: !_isRadarActive,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'اسم المادة (مثلاً: Pharmacology)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('نوع المحاضرة:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('محاضرة نظري (الدفعة)')),
                          selected: _lectureType == 'نظري',
                          onSelected: _isRadarActive ? null : (_) => setState(() => _lectureType = 'نظري'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('معمل عملي (مجموعات)')),
                          selected: _lectureType == 'عملي',
                          onSelected: _isRadarActive ? null : (_) => setState(() => _lectureType = 'عملي'),
                        ),
                      ),
                    ],
                  ),
                  if (_lectureType == 'عملي') ...[
                    const SizedBox(height: 12),
                    const Text('تحديد مجموعة العملي (A - D):', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: _practicalGroups.map((grp) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: ChoiceChip(
                              label: Center(child: Text(grp, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                              selected: _selectedGroup == grp,
                              onSelected: _isRadarActive ? null : (_) => setState(() => _selectedGroup = grp),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  if (_fullSessionLabel.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'عنوان الكشف المعتمد: $_fullSessionLabel',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accent),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text('مدة عمل الرادار:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('دقيقتان'),
                        selected: _selectedMinutes == 2,
                        onSelected: _isRadarActive ? null : (_) => setState(() => _selectedMinutes = 2),
                      ),
                      ChoiceChip(
                        label: const Text('5 دقائق (موصى به)'),
                        selected: _selectedMinutes == 5,
                        onSelected: _isRadarActive ? null : (_) => setState(() => _selectedMinutes = 5),
                      ),
                      ChoiceChip(
                        label: const Text('10 دقائق'),
                        selected: _selectedMinutes == 10,
                        onSelected: _isRadarActive ? null : (_) => setState(() => _selectedMinutes = 10),
                      ),
                      ChoiceChip(
                        label: const Text('مفتوح (إيقاف يدوي)'),
                        selected: _selectedMinutes == 0,
                        onSelected: _isRadarActive ? null : (_) => setState(() => _selectedMinutes = 0),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isRadarActive ? Colors.redAccent : accent,
                        foregroundColor: _isRadarActive ? Colors.white : Colors.black,
                      ),
                      icon: Icon(_isRadarActive ? Icons.stop_circle_rounded : Icons.radar_rounded),
                      label: Text(
                        _isRadarActive ? 'إيقاف الرادار الآن' : 'تشغيل رادار التحضير الآن',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      onPressed: _isRadarActive ? () => _stopRadar() : _startRadar,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isRadarActive) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF115E59)]),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent, width: 1.5),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.bluetooth_searching_rounded, color: _bleAdvertising ? Colors.greenAccent : Colors.amber),
                          const SizedBox(width: 6),
                          Text(
                            _bleAdvertising ? 'رادار البلوتوث نشط 📡' : 'وضع الكود السريع نشط',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                      if (_selectedMinutes > 0)
                        Chip(
                          backgroundColor: Colors.black45,
                          label: Text(
                            'المتبقي: ${_formatCountdown(_remainingSeconds)}',
                            style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 24),
                  const Text(
                    'الكود السريع المتغيّر كل 10 ثوانٍ (للطلاب يدوياً):',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _activePin,
                    style: TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 12,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: _pinSecondsLeft / 10.0,
                    backgroundColor: Colors.white12,
                    color: accent,
                  ),
                  const SizedBox(height: 4),
                  Text('يتجدد الكود خلال $_pinSecondsLeft ثانية', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الطلاب الملتقطون (${_capturedStudents.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                icon: _isUploading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload_rounded, size: 18),
                label: const Text('اعتماد ورفع الكشف'),
                onPressed: _capturedStudents.isEmpty ? null : _syncCapturedToCloud,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_capturedStudents.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'بمجرد تشغيل الرادار، سيظهر هنا الطلاب الموجودون في القاعة أو المعمل تلقائياً.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ..._capturedStudents.values.map((st) => Card(
                  color: cardBg,
                  child: ListTile(
                    leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.check, color: Colors.white)),
                    title: Text(st['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('رقم القيد: ${st['student_id']} • ${st['method']}'),
                  ),
                )),
        ],
      ),
    );
  }
}

class StudentFastAttendanceSheet extends StatefulWidget {
  final String studentId;
  final String studentName;
  const StudentFastAttendanceSheet({super.key, required this.studentId, required this.studentName});

  @override
  State<StudentFastAttendanceSheet> createState() => _StudentFastAttendanceSheetState();
}

class _StudentFastAttendanceSheetState extends State<StudentFastAttendanceSheet> {
  static const int _attManufacturerId = 0x3939;
  static const List<String> _practicalGroups = ['مجموعة A', 'مجموعة B', 'مجموعة C', 'مجموعة D'];

  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  final TextEditingController _subjectCtrl = TextEditingController();
  final TextEditingController _pinCtrl = TextEditingController();

  String _lectureType = 'نظري';
  String _selectedGroup = 'مجموعة A';
  bool _broadcasting = false;
  bool _radarNearby = false;
  bool _submitting = false;
  StreamSubscription<List<ScanResult>>? _scanSub;

  String get _computedSessionLabel {
    final base = _subjectCtrl.text.trim();
    if (base.isEmpty) return '';
    if (_lectureType == 'عملي') {
      return '$base - عملي ($_selectedGroup)';
    }
    return '$base - نظري';
  }

  @override
  void initState() {
    super.initState();
    _startAutoBluetoothPresence();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    try {
      FlutterBluePlus.stopScan();
    } catch (_) {}
    try {
      _peripheral.stop();
    } catch (_) {}
    _subjectCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _startAutoBluetoothPresence() async {
    final btReady = await BleSafeHelper.prepareBluetooth();
    if (!btReady || !mounted) return;

    try {
      final supported = await _peripheral.isSupported;
      if (supported) {
        final advData = AdvertiseData(
          includeDeviceName: false,
          manufacturerId: _attManufacturerId,
          manufacturerData: BleSafeHelper.safeAsciiBytes('S|${widget.studentId}'),
        );
        await _peripheral.start(advertiseData: advData);
        if (mounted) setState(() => _broadcasting = true);
      }
    } catch (_) {}

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final raw = r.advertisementData.manufacturerData[_attManufacturerId];
          if (raw != null) {
            final text = utf8.decode(raw, allowMalformed: true);
            if (text.startsWith('ADM|') && mounted) {
              setState(() => _radarNearby = true);
            }
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _submitPinAttendance() async {
    final session = _computedSessionLabel;
    final pin = _pinCtrl.text.trim();

    if (session.isEmpty || pin.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppPrefs.tr('أدخل اسم المادة والكود المكون من 4 أرقام', 'Enter subject & 4-digit PIN')), backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (!RadarCrypto.verifyPin(session, pin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppPrefs.tr('الكود غير صحيح أو انتهت مدته (تأكد من نوع المحاضرة والمجموعة)', 'Invalid or expired PIN')), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await Supabase.instance.client.from('attendance').insert({
        'student_id': widget.studentId,
        'full_name': widget.studentName,
        'session_code': session,
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppPrefs.tr('تم تسجيل حضورك في ($session) بنجاح ✓', 'Attendance recorded ✓')), backgroundColor: Colors.green),
      );
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getStringList('pending_offline_attendance') ?? [];
      pending.add(jsonEncode({
        'student_id': widget.studentId,
        'full_name': widget.studentName,
        'session_code': session,
      }));
      await prefs.setStringList('pending_offline_attendance', pending);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppPrefs.tr('تم التحقق من الكود وحفظ حضورك محلياً وسيُرفع تلقائياً عند توفر الإنترنت ✓', 'PIN verified & saved offline ✓')),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.radar_rounded, color: accent, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AppPrefs.tr('التحضير السريع داخل القاعة أو المعمل', 'Fast In-Class Attendance'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _broadcasting ? Colors.teal.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _broadcasting ? Colors.teal : Colors.orange),
              ),
              child: Row(
                children: [
                  Icon(_broadcasting ? Icons.bluetooth_connected_rounded : Icons.bluetooth_disabled_rounded,
                      color: _broadcasting ? Colors.teal : Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _radarNearby
                          ? 'تم التقاط رادار المندوب داخل القاعة ✓ (أنت ظاهر في القائمة الآن)'
                          : (_broadcasting
                              ? 'إشارتك نشطة الآن بالبلوتوث، سيظهر اسمك في رادار المندوب تلقائياً.'
                              : 'شغّل زر البلوتوث في هاتفك للالتقاط التلقائي، أو أدخل الكود الرباعي بالأسفل.'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subjectCtrl,
              decoration: InputDecoration(
                labelText: AppPrefs.tr('اسم المادة (كما كتبها المندوب)', 'Subject Name'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('نظري')),
                    selected: _lectureType == 'نظري',
                    onSelected: (_) => setState(() => _lectureType = 'نظري'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('عملي')),
                    selected: _lectureType == 'عملي',
                    onSelected: (_) => setState(() => _lectureType = 'عملي'),
                  ),
                ),
              ],
            ),
            if (_lectureType == 'عملي') ...[
              const SizedBox(height: 8),
              Row(
                children: _practicalGroups.map((grp) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: ChoiceChip(
                        label: Center(child: Text(grp, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold))),
                        selected: _selectedGroup == grp,
                        onSelected: (_) => setState(() => _selectedGroup = grp),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _pinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 10),
              decoration: InputDecoration(
                hintText: '••••',
                labelText: AppPrefs.tr('الكود المتغيّر (4 أرقام)', '4-Digit Rolling PIN'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
                icon: _submitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check_circle_rounded),
                label: Text(AppPrefs.tr('تأكيد الحضور بالكود', 'Confirm Attendance'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                onPressed: _submitting ? null : _submitPinAttendance,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OfflineBluetoothChatScreen extends StatefulWidget {
  final String studentId;
  final String nickname;
  const OfflineBluetoothChatScreen({super.key, required this.studentId, required this.nickname});

  @override
  State<OfflineBluetoothChatScreen> createState() => _OfflineBluetoothChatScreenState();
}

class _OfflineBluetoothChatScreenState extends State<OfflineBluetoothChatScreen> {
  static const int _chatManufacturerId = 0x3940;
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  final TextEditingController _msgCtrl = TextEditingController();
  final List<BleChatMessage> _bleMessages = [];
  final Set<String> _seenPacketIds = {};
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _initOfflineBleChat();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    try {
      FlutterBluePlus.stopScan();
    } catch (_) {}
    try {
      _peripheral.stop();
    } catch (_) {}
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _initOfflineBleChat() async {
    final btReady = await BleSafeHelper.prepareBluetooth();
    if (!btReady || !mounted) return;

    try {
      await FlutterBluePlus.startScan(continuousUpdates: true);
      if (mounted) setState(() => _isScanning = true);
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final raw = r.advertisementData.manufacturerData[_chatManufacturerId];
          if (raw != null) {
            final packet = utf8.decode(raw, allowMalformed: true);
            final parts = packet.split('|');
            if (parts.length >= 3) {
              final pktId = parts[0];
              final sender = parts[1];
              final body = parts.sublist(2).join('|');
              if (!_seenPacketIds.contains(pktId) && mounted) {
                _seenPacketIds.add(pktId);
                setState(() {
                  _bleMessages.add({
                    'sender': sender,
                    'body': body,
                    'isMe': 'false',
                    'time': '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                  });
                });
              }
            }
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _broadcastBleMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();

    final pktId = (DateTime.now().millisecondsSinceEpoch % 9999).toString();
    final shortNick = widget.nickname.split(' ').first;
    final packet = '$pktId|$shortNick|$text';

    _seenPacketIds.add(pktId);
    setState(() {
      _bleMessages.add({
        'sender': widget.nickname,
        'body': text,
        'isMe': 'true',
        'time': '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      });
    });

    try {
      final supported = await _peripheral.isSupported;
      if (!supported) return;
      await _peripheral.stop();
      await _peripheral.start(
        advertiseData: AdvertiseData(
          includeDeviceName: false,
          manufacturerId: _chatManufacturerId,
          manufacturerData: BleSafeHelper.safeUtf8Bytes(packet, maxBytes: 22),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Theme.of(context).cardColor;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('دردشة القاعة بالبلوتوث (بدون إنترنت)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            Text(
              _isScanning ? 'متصل بالرادار المحيط 📡' : 'شغّل زر البلوتوث في هاتفك للاتصال',
              style: TextStyle(fontSize: 11, color: _isScanning ? Colors.greenAccent : Colors.orange),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: Colors.teal.withOpacity(0.15),
            child: const Text(
              '💡 يعمل هذا الوضع بدون إنترنت بين الطلاب داخل القاعة عبر موجات البلوتوث.',
              style: TextStyle(fontSize: 11, color: Colors.tealAccent),
            ),
          ),
          Expanded(
            child: _bleMessages.isEmpty
                ? const Center(
                    child: Text(
                      'لا توجد رسائل بلوتوث محيطة بعد.\nاكتب رسالة قصيرة وسيستلمها زملاؤك في القاعة فوراً.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _bleMessages.length,
                    itemBuilder: (_, i) {
                      final m = _bleMessages[i];
                      final isMe = m['isMe'] == 'true';
                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isMe ? const Color(0xFF005C4B) : cardBg,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isMe)
                                Text(m['sender'] ?? '', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accent)),
                              Text(m['body'] ?? '', style: TextStyle(color: isMe ? Colors.white : null)),
                              const SizedBox(height: 2),
                              Text(m['time'] ?? '', style: const TextStyle(fontSize: 9, color: Colors.white60)),
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
                    maxLength: 14,
                    decoration: const InputDecoration(
                      counterText: '',
                      hintText: 'رسالة قصيرة (حتى 14 حرف)...',
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _broadcastBleMessage(),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.bluetooth_audio_rounded, color: accent),
                  onPressed: _broadcastBleMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
