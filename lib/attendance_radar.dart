import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_prefs.dart';

typedef RadarStudentRecord = Map<String, String>;
typedef BleChatMessage = Map<String, String>;

class CourseCatalogItem {
  final String code;
  final String nameAr;
  final String nameEn;
  final bool hasTheory;
  final bool hasPractical;
  final int startHour24;
  final int endHour24;

  const CourseCatalogItem({
    required this.code,
    required this.nameAr,
    required this.nameEn,
    this.hasTheory = true,
    this.hasPractical = false,
    this.startHour24 = 8,
    this.endHour24 = 10,
  });

  String displayLabel(String type) {
    final effectiveCode = (type == 'عملي' && hasPractical && !code.endsWith('L')) ? '${code}L' : code;
    return '$effectiveCode - $nameAr';
  }
}

class CourseCatalog {
  static const List<CourseCatalogItem> courses = [
    CourseCatalogItem(
      code: 'PHAR-101',
      nameAr: 'صيدلة فيزيائية (Physical Pharmacy)',
      nameEn: 'Physical Pharmacy',
      hasTheory: true,
      hasPractical: true,
      startHour24: 10,
      endHour24: 12,
    ),
    CourseCatalogItem(
      code: 'ENGL-102',
      nameAr: 'لغة إنجليزية 2 (English Language II)',
      nameEn: 'English Language II',
      hasTheory: true,
      hasPractical: false,
      startHour24: 8,
      endHour24: 10,
    ),
    CourseCatalogItem(
      code: 'ANAT-103',
      nameAr: 'تشريح وأنسجة (Anatomy & Histology)',
      nameEn: 'Anatomy & Histology',
      hasTheory: true,
      hasPractical: false,
      startHour24: 8,
      endHour24: 10,
    ),
    CourseCatalogItem(
      code: 'COMP-104',
      nameAr: 'مهارات حاسوب (Computer Skills)',
      nameEn: 'Computer Skills',
      hasTheory: true,
      hasPractical: true,
      startHour24: 10,
      endHour24: 12,
    ),
    CourseCatalogItem(
      code: 'CALC-105',
      nameAr: 'حسابات صيدلانية (Pharmaceutical Calculations)',
      nameEn: 'Pharmaceutical Calculations',
      hasTheory: true,
      hasPractical: false,
      startHour24: 12,
      endHour24: 14,
    ),
    CourseCatalogItem(
      code: 'ARAB-106',
      nameAr: 'لغة عربية 2 (Arabic Language 2)',
      nameEn: 'Arabic Language 2',
      hasTheory: true,
      hasPractical: false,
      startHour24: 14,
      endHour24: 16,
    ),
  ];

  static CourseCatalogItem? findByCode(String code) {
    final clean = code.replaceAll(RegExp(r'L$'), '').trim().toUpperCase();
    for (final c in courses) {
      if (c.code == clean) return c;
    }
    return null;
  }

  /// نافذة تحضير النظري: تبدأ بعد 30 دقيقة من بداية المحاضرة وتنتهي قبل نهايتها بـ 30 دقيقة
  static Map<String, dynamic> evaluateTheoryWindow(CourseCatalogItem? item) {
    final now = DateTime.now();
    final startH = item?.startHour24 ?? 8;
    final endH = item?.endHour24 ?? 10;

    final lecStart = DateTime(now.year, now.month, now.day, startH, 0);
    final lecEnd = DateTime(now.year, now.month, now.day, endH, 0);
    final winStart = lecStart.add(const Duration(minutes: 30));
    final winEnd = lecEnd.subtract(const Duration(minutes: 30));

    final inWindow = !now.isBefore(winStart) && now.isBefore(winEnd);
    final fmt = (DateTime dt) =>
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return {
      'inWindow': inWindow,
      'winStart': winStart,
      'winEnd': winEnd,
      'windowLabel': '${fmt(winStart)} - ${fmt(winEnd)}',
      'secondsToEnd': inWindow ? winEnd.difference(now).inSeconds : 3600,
    };
  }
}

class RadarCrypto {
  static const int _secretSeed = 3970241;
  static const int slotDurationMs = 10000;

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
    return clean == generatePinForSlot(sessionCode, slot) ||
        clean == generatePinForSlot(sessionCode, slot - 1);
  }

  static int secondsRemainingInSlot() {
    final ms = DateTime.now().millisecondsSinceEpoch % slotDurationMs;
    return 10 - (ms ~/ 1000);
  }
}

class BleSafeHelper {
  static Future<bool> prepareBluetooth({bool promptTurnOn = false}) async {
    if (kIsWeb) return false;
    try {
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) return false;

      final permList = <Permission>[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.locationWhenInUse,
      ];

      for (final p in permList) {
        try {
          await p.request();
        } catch (_) {}
      }

      final scanGranted = await Permission.bluetoothScan.isGranted ||
          await Permission.bluetooth.isGranted ||
          await Permission.locationWhenInUse.isGranted;
      if (!scanGranted) return false;

      var state = await FlutterBluePlus.adapterState.first
          .timeout(const Duration(seconds: 2), onTimeout: () => BluetoothAdapterState.unknown);

      if (state != BluetoothAdapterState.on && promptTurnOn) {
        try {
          await FlutterBluePlus.turnOn();
          await Future.delayed(const Duration(milliseconds: 900));
          state = await FlutterBluePlus.adapterState.first
              .timeout(const Duration(seconds: 2), onTimeout: () => BluetoothAdapterState.unknown);
        } catch (_) {}
      }

      return state == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  static Future<void> safeStopAll(FlutterBlePeripheral peripheral) async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    try {
      await peripheral.stop();
    } catch (_) {}
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

class _AdminRadarScreenState extends State<AdminRadarScreen> with SingleTickerProviderStateMixin {
  static const int _attManufacturerId = 0x3939;
  static const List<String> _practicalGroups = ['مجموعة A', 'مجموعة B', 'مجموعة C', 'مجموعة D'];

  final TextEditingController _customCodeCtrl = TextEditingController();
  final TextEditingController _lectureNumCtrl = TextEditingController(text: '1');
  final TextEditingController _rosterSearchCtrl = TextEditingController();
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  late TabController _tabController;

  String _selectedCourseCode = 'PHAR-101';
  bool _useCustomCode = false;
  String _lectureType = 'نظري';
  String _selectedGroup = 'مجموعة A';
  bool _overrideTheoryWindow = false;

  bool _isRadarActive = false;
  bool _isPaused = false;
  bool _sessionFinished = false;
  DateTime? _sessionEndsAt;
  int _remainingSeconds = 0;

  String _activePin = '----';
  int _pinSecondsLeft = 10;
  bool _bleAdvertising = false;
  String _adminGender = 'male';

  Timer? _mainTimer;
  Timer? _cloudSyncTimer;
  StreamSubscription<List<ScanResult>>? _scanSub;

  // status: 'present' | 'absent' | 'excused'
  final Map<String, RadarStudentRecord> _sessionRecords = {};
  List<Map<String, String>> _sectionRoster = [];
  bool _isUploading = false;
  String? _lastScannedQrId;

  String get _effectiveCourseCode {
    if (_useCustomCode) {
      return _customCodeCtrl.text.trim().toUpperCase();
    }
    final item = CourseCatalog.findByCode(_selectedCourseCode);
    if (_lectureType == 'عملي' && item != null && item.hasPractical && !_selectedCourseCode.endsWith('L')) {
      return '${_selectedCourseCode}L';
    }
    return _selectedCourseCode;
  }

  String get _effectiveLectureNum {
    final n = _lectureNumCtrl.text.trim();
    return n.isEmpty ? '1' : n;
  }

  String get _todayDateStr {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String get _fullSessionLabel {
    final code = _effectiveCourseCode;
    if (code.isEmpty) return '';
    final lec = 'محاضرة $_effectiveLectureNum';
    if (_lectureType == 'عملي') {
      return '$code | $lec | عملي ($_selectedGroup)';
    }
    return '$code | $lec | نظري';
  }

  String get _unifiedSessionKey {
    final code = _effectiveCourseCode;
    final grp = _lectureType == 'عملي' ? _selectedGroup.replaceAll(' ', '') : 'ALL';
    return '${_adminGender}_${code}_L${_effectiveLectureNum}_${grp}_$_todayDateStr';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadRosterAndGender();
  }

  @override
  void dispose() {
    _stopRadarHardwareOnly();
    _mainTimer?.cancel();
    _cloudSyncTimer?.cancel();
    _tabController.dispose();
    _customCodeCtrl.dispose();
    _lectureNumCtrl.dispose();
    _rosterSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRosterAndGender() async {
    final prefs = await SharedPreferences.getInstance();
    _adminGender = prefs.getString('student_gender') ?? 'male';

    final cachedRoster = prefs.getString('cache_roster_$_adminGender');
    if (cachedRoster != null && cachedRoster.isNotEmpty) {
      try {
        final decoded = jsonDecode(cachedRoster) as List<dynamic>;
        _sectionRoster = decoded.map((e) => Map<String, String>.from(e as Map)).toList();
      } catch (_) {}
    }

    try {
      final rows = await Supabase.instance.client
          .from('students')
          .select('student_id, full_name, gender')
          .eq('gender', _adminGender)
          .order('full_name');
      final List<Map<String, String>> fresh = [];
      for (final r in rows) {
        final id = (r['student_id'] ?? '').toString().trim();
        final name = (r['full_name'] ?? '').toString().trim();
        if (id.isNotEmpty && name.isNotEmpty) {
          fresh.add({'student_id': id, 'full_name': name});
        }
      }
      if (fresh.isNotEmpty) {
        _sectionRoster = fresh;
        await prefs.setString('cache_roster_$_adminGender', jsonEncode(fresh));
      }
    } catch (_) {}

    if (mounted) setState(() {});
  }

  String _lookupStudentName(String sid) {
    for (final st in _sectionRoster) {
      if (st['student_id'] == sid) return st['full_name'] ?? 'طالب ($sid)';
    }
    return 'طالب ($sid)';
  }

  Future<void> _startRadar() async {
    final code = _effectiveCourseCode;
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تحديد كود المقرر أولاً'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    DateTime endsAt;
    if (_lectureType == 'نظري') {
      final item = CourseCatalog.findByCode(code);
      final win = CourseCatalog.evaluateTheoryWindow(item);
      if (win['inWindow'] != true && !_overrideTheoryWindow) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'التحضير التلقائي للمقرر متاح فقط بين (${win['windowLabel']}) بعد مرور نصف ساعة من البداية وقبل النهاية بنصف ساعة. فعّل خيار (تجاوز الوقت) للفتح الاستثنائي.',
            ),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }
      endsAt = win['inWindow'] == true
          ? (win['winEnd'] as DateTime)
          : DateTime.now().add(const Duration(minutes: 60));
    } else {
      // العملي: بدء اختياري لمدة ربع ساعة (15 دقيقة)
      endsAt = DateTime.now().add(const Duration(minutes: 15));
    }

    final sessionLabel = _fullSessionLabel;
    final remSec = endsAt.difference(DateTime.now()).inSeconds.clamp(60, 7200);

    setState(() {
      _isRadarActive = true;
      _isPaused = false;
      _sessionFinished = false;
      _sessionEndsAt = endsAt;
      _remainingSeconds = remSec;
      _activePin = RadarCrypto.currentPin(sessionLabel);
      _pinSecondsLeft = RadarCrypto.secondsRemainingInSlot();
    });

    await _upsertUnifiedSessionState(isActive: true, isPaused: false, endsAt: endsAt);
    await _pullUnifiedAttendanceFromCloud();
    await _startRadarHardware();

    _mainTimer?.cancel();
    _mainTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final left = _sessionEndsAt != null ? _sessionEndsAt!.difference(now).inSeconds : 0;
      if (left <= 0) {
        _finishSession();
        return;
      }
      setState(() {
        _remainingSeconds = left;
        if (!_isPaused) {
          _activePin = RadarCrypto.currentPin(sessionLabel);
          _pinSecondsLeft = RadarCrypto.secondsRemainingInSlot();
        }
      });
    });

    _cloudSyncTimer?.cancel();
    _cloudSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && _isRadarActive) {
        _pullUnifiedAttendanceFromCloud();
      }
    });
  }

  Future<void> _startRadarHardware() async {
    final sessionLabel = _fullSessionLabel;
    final btReady = await BleSafeHelper.prepareBluetooth(promptTurnOn: false);
    if (!btReady) {
      if (mounted) setState(() => _bleAdvertising = false);
      return;
    }

    try {
      final supported = await _peripheral.isSupported;
      if (supported) {
        final advData = AdvertiseData(
          includeDeviceName: false,
          manufacturerId: _attManufacturerId,
          manufacturerData: BleSafeHelper.safeAsciiBytes('ADM|${sessionLabel.hashCode.abs() % 99999}'),
        );
        await _peripheral.start(advertiseData: advData);
        if (mounted) setState(() => _bleAdvertising = true);
      }
    } catch (_) {}

    try {
      await FlutterBluePlus.startScan(continuousUpdates: true);
      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        if (_isPaused || !_isRadarActive) return;
        for (final r in results) {
          final rawBytes = r.advertisementData.manufacturerData[_attManufacturerId];
          if (rawBytes != null) {
            final payload = utf8.decode(rawBytes, allowMalformed: true);
            if (payload.startsWith('S|')) {
              final sid = payload.substring(2).trim();
              if (sid.isNotEmpty && _sessionRecords[sid]?['status'] != 'present') {
                _recordStudentStatus(
                  studentId: sid,
                  fullName: _lookupStudentName(sid),
                  status: 'present',
                  method: 'رادار بلوتوث 📡',
                );
              }
            }
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _stopRadarHardwareOnly() async {
    _scanSub?.cancel();
    await BleSafeHelper.safeStopAll(_peripheral);
    if (mounted) {
      setState(() => _bleAdvertising = false);
    }
  }

  Future<void> _togglePauseResume() async {
    if (!_isRadarActive) return;
    final nextPaused = !_isPaused;
    setState(() => _isPaused = nextPaused);

    if (nextPaused) {
      await _stopRadarHardwareOnly();
      await _upsertUnifiedSessionState(isActive: true, isPaused: true, endsAt: _sessionEndsAt);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⏸️ تم إيقاف التحضير مؤقتاً. اضغط (استئناف) لتحضير بقية الطلاب قبل انتهاء الوقت.'),
            backgroundColor: Colors.amber,
          ),
        );
      }
    } else {
      await _upsertUnifiedSessionState(isActive: true, isPaused: false, endsAt: _sessionEndsAt);
      await _startRadarHardware();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('▶️ تم استئناف التحضير بنجاح'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    }
  }

  Future<void> _finishSession() async {
    _mainTimer?.cancel();
    _cloudSyncTimer?.cancel();
    await _stopRadarHardwareOnly();
    await _upsertUnifiedSessionState(isActive: false, isPaused: false, endsAt: DateTime.now());
    await _syncAllRecordsToCloud(silent: true);

    if (mounted) {
      setState(() {
        _isRadarActive = false;
        _isPaused = false;
        _sessionFinished = true;
      });
    }
  }

  Future<void> _upsertUnifiedSessionState({
    required bool isActive,
    required bool isPaused,
    DateTime? endsAt,
  }) async {
    try {
      await Supabase.instance.client.from('attendance_sessions').upsert({
        'session_key': _unifiedSessionKey,
        'session_code': _fullSessionLabel,
        'course_code': _effectiveCourseCode,
        'lecture_num': _effectiveLectureNum,
        'lecture_type': _lectureType,
        'group_name': _lectureType == 'عملي' ? _selectedGroup : 'الكل',
        'target_gender': _adminGender,
        'is_active': isActive,
        'is_paused': isPaused,
        'ends_at': (endsAt ?? DateTime.now()).toUtc().toIso8601String(),
        'updated_by': widget.adminName,
      }, onConflict: 'session_key');
    } catch (_) {}
  }

  Future<void> _pullUnifiedAttendanceFromCloud() async {
    try {
      final rows = await Supabase.instance.client
          .from('attendance')
          .select()
          .eq('session_code', _fullSessionLabel);
      if (!mounted) return;
      bool changed = false;
      for (final r in rows) {
        final sid = (r['student_id'] ?? '').toString().trim();
        if (sid.isEmpty) continue;
        final st = (r['status'] ?? 'present').toString();
        final by = (r['recorded_by'] ?? widget.adminName).toString();
        final name = (r['full_name'] ?? _lookupStudentName(sid)).toString();
        if (_sessionRecords[sid]?['status'] != st) {
          _sessionRecords[sid] = {
            'student_id': sid,
            'full_name': name,
            'status': st,
            'method': 'مزامنة موحدة ($by)',
            'recorded_by': by,
          };
          changed = true;
        }
      }
      if (changed && mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _recordStudentStatus({
    required String studentId,
    required String fullName,
    required String status,
    required String method,
  }) async {
    final cleanId = studentId.trim();
    if (cleanId.isEmpty) return;
    final cleanName = fullName.trim().isEmpty ? _lookupStudentName(cleanId) : fullName.trim();

    setState(() {
      _sessionRecords[cleanId] = {
        'student_id': cleanId,
        'full_name': cleanName,
        'status': status,
        'method': method,
        'recorded_by': widget.adminName,
      };
    });

    try {
      final existing = await Supabase.instance.client
          .from('attendance')
          .select('id')
          .eq('student_id', cleanId)
          .eq('session_code', _fullSessionLabel)
          .maybeSingle();

      if (existing != null) {
        await Supabase.instance.client.from('attendance').update({
          'status': status,
          'recorded_by': widget.adminName,
          'course_code': _effectiveCourseCode,
          'lecture_num': _effectiveLectureNum,
          'session_key': _unifiedSessionKey,
        }).eq('id', existing['id']);
      } else {
        await Supabase.instance.client.from('attendance').insert({
          'student_id': cleanId,
          'full_name': cleanName,
          'session_code': _fullSessionLabel,
          'course_code': _effectiveCourseCode,
          'lecture_num': _effectiveLectureNum,
          'session_key': _unifiedSessionKey,
          'status': status,
          'recorded_by': widget.adminName,
        });
      }
    } catch (_) {}
  }

  Future<void> _syncAllRecordsToCloud({bool silent = false}) async {
    if (_isUploading) return;
    setState(() => _isUploading = true);
    final sessionLabel = _fullSessionLabel;

    try {
      // تأكد من تسجيل غير المحضّرين كـ مغيبين إن لم يكن لديهم حالة مسجلة
      for (final st in _sectionRoster) {
        final sid = st['student_id']!;
        if (!_sessionRecords.containsKey(sid)) {
          _sessionRecords[sid] = {
            'student_id': sid,
            'full_name': st['full_name']!,
            'status': 'absent',
            'method': 'رصد تلقائي',
            'recorded_by': widget.adminName,
          };
        }
      }

      final existingRows = await Supabase.instance.client
          .from('attendance')
          .select('id, student_id')
          .eq('session_code', sessionLabel);
      final Map<String, dynamic> existingBySid = {
        for (final r in existingRows) (r['student_id'] ?? '').toString(): r['id']
      };

      final List<Map<String, dynamic>> toInsert = [];
      for (final rec in _sessionRecords.values) {
        final sid = rec['student_id']!;
        if (existingBySid.containsKey(sid)) {
          await Supabase.instance.client.from('attendance').update({
            'status': rec['status'],
            'recorded_by': rec['recorded_by'] ?? widget.adminName,
          }).eq('id', existingBySid[sid]);
        } else {
          toInsert.add({
            'student_id': sid,
            'full_name': rec['full_name'],
            'session_code': sessionLabel,
            'course_code': _effectiveCourseCode,
            'lecture_num': _effectiveLectureNum,
            'session_key': _unifiedSessionKey,
            'status': rec['status'],
            'recorded_by': rec['recorded_by'] ?? widget.adminName,
          });
        }
      }

      if (toInsert.isNotEmpty) {
        await Supabase.instance.client.from('attendance').insert(toInsert);
      }

      if (!mounted) return;
      setState(() => _isUploading = false);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم اعتماد ورفع الكشف الموحد لـ ($sessionLabel) بنجاح ✓'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر الرفع حالياً (لا يوجد إنترنت). أبقِ الشاشة مفتوحة وارفع الكشف فور توفر الشبكة.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _onQrDetected(BarcodeCapture capture) {
    if (!_isRadarActive || _isPaused) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.trim().isEmpty) continue;
      String sid = raw.trim();
      String name = '';
      try {
        final parsed = jsonDecode(raw);
        if (parsed is Map) {
          sid = (parsed['id'] ?? parsed['student_id'] ?? '').toString().trim();
          name = (parsed['name'] ?? parsed['full_name'] ?? '').toString().trim();
        }
      } catch (_) {}

      if (sid.isEmpty || sid == _lastScannedQrId) continue;
      _lastScannedQrId = sid;
      Future.delayed(const Duration(seconds: 2), () {
        if (_lastScannedQrId == sid) _lastScannedQrId = null;
      });

      final finalName = name.isNotEmpty ? name : _lookupStudentName(sid);
      _recordStudentStatus(
        studentId: sid,
        fullName: finalName,
        status: 'present',
        method: 'مسح كود QR 📷',
      );
      HapticFeedback.mediumImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ تم تحضير: $finalName ($sid)'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      break;
    }
  }

  String _formatCountdown(int totalSec) {
    final safe = totalSec < 0 ? 0 : totalSec;
    final m = (safe ~/ 60).toString().padLeft(2, '0');
    final s = (safe % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Map<String, int> get _statsCounts {
    int present = 0;
    int excused = 0;
    for (final r in _sessionRecords.values) {
      if (r['status'] == 'present') present++;
      if (r['status'] == 'excused') excused++;
    }
    final total = _sectionRoster.isNotEmpty ? _sectionRoster.length : _sessionRecords.length;
    final absent = (total - present - excused) < 0 ? 0 : (total - present - excused);
    return {'total': total, 'present': present, 'absent': absent, 'excused': excused};
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = Theme.of(context).cardColor;
    final accent = Theme.of(context).colorScheme.primary;
    final selectedItem = CourseCatalog.findByCode(_selectedCourseCode);
    final theoryWin = CourseCatalog.evaluateTheoryWindow(selectedItem);
    final stats = _statsCounts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('رادار التحضير الموحد (نظري / عملي)'),
        bottom: _isRadarActive
            ? TabBar(
                controller: _tabController,
                indicatorColor: accent,
                labelColor: isDark ? Colors.white : Colors.black,
                tabs: [
                  Tab(icon: const Icon(Icons.radar_rounded, size: 18), text: 'الرادار (${stats['present']})'),
                  const Tab(icon: Icon(Icons.qr_code_scanner_rounded, size: 18), text: 'مسح QR'),
                  Tab(icon: const Icon(Icons.fact_check_rounded, size: 18), text: 'كشف الدفعة (${stats['total']})'),
                ],
              )
            : null,
      ),
      body: _isRadarActive
          ? TabBarView(
              controller: _tabController,
              children: [
                _buildActiveRadarTab(cardBg, accent, stats),
                _buildQrScannerTab(cardBg, accent),
                _buildFullRosterTab(cardBg, accent, isDark),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_sessionFinished) ...[
                  _buildFinalStatsCard(cardBg, accent, stats),
                  const SizedBox(height: 16),
                ],
                Card(
                  color: cardBg,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('إعداد جلسة التحضير الموحدة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            Chip(
                              label: Text(_adminGender == 'female' ? 'شطر الطالبات' : 'شطر الطلاب', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              backgroundColor: accent.withOpacity(0.15),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (!_useCustomCode)
                          DropdownButtonFormField<String>(
                            value: _selectedCourseCode,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'كود واسم المقرر',
                              border: OutlineInputBorder(),
                            ),
                            items: CourseCatalog.courses
                                .map((c) => DropdownMenuItem(
                                      value: c.code,
                                      child: Text(c.displayLabel(_lectureType), overflow: TextOverflow.ellipsis),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _selectedCourseCode = v);
                            },
                          )
                        else
                          TextField(
                            controller: _customCodeCtrl,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'اكتب كود المقرر (مثلاً: PHAR-201)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: Icon(_useCustomCode ? Icons.list_alt_rounded : Icons.edit_rounded, size: 16),
                            label: Text(_useCustomCode ? 'الاختيار من قائمة المقررات المعتمدة' : 'إدخال كود مقرر مخصص'),
                            onPressed: () => setState(() => _useCustomCode = !_useCustomCode),
                          ),
                        ),
                        TextField(
                          controller: _lectureNumCtrl,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'رقم المحاضرة (مثال: 1، 2، 3...)',
                            prefixIcon: Icon(Icons.format_list_numbered_rtl_rounded),
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
                                label: Center(
                                  child: Text(
                                    'محاضرة نظري (الدفعة)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _lectureType == 'نظري' ? Colors.black : null,
                                    ),
                                  ),
                                ),
                                selectedColor: accent,
                                selected: _lectureType == 'نظري',
                                onSelected: (_) => setState(() => _lectureType = 'نظري'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ChoiceChip(
                                label: Center(
                                  child: Text(
                                    'معمل عملي (15 دقيقة)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _lectureType == 'عملي' ? Colors.black : null,
                                    ),
                                  ),
                                ),
                                selectedColor: accent,
                                selected: _lectureType == 'عملي',
                                onSelected: (_) => setState(() => _lectureType = 'عملي'),
                              ),
                            ),
                          ],
                        ),
                        if (_lectureType == 'نظري') ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: (theoryWin['inWindow'] == true ? Colors.green : Colors.orange).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: theoryWin['inWindow'] == true ? Colors.green : Colors.orange),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '⏱️ نافذة التحضير التلقائية للمقرر: (${theoryWin['windowLabel']})',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'تبدأ بعد مرور نصف ساعة من بداية المحاضرة وتنتهي قبل نهايتها بنصف ساعة.',
                                  style: TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                                if (theoryWin['inWindow'] != true)
                                  SwitchListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('تجاوز الوقت (فتح استثنائي للمحاضرة الآن)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    value: _overrideTheoryWindow,
                                    onChanged: (v) => setState(() => _overrideTheoryWindow = v),
                                  ),
                              ],
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 12),
                          const Text('تحديد مجموعة العملي (بدء اختياري لمدة 15 دقيقة):', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Row(
                            children: _practicalGroups.map((grp) {
                              final sel = _selectedGroup == grp;
                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 3),
                                  child: ChoiceChip(
                                    selectedColor: accent,
                                    label: Center(
                                      child: Text(
                                        grp,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: sel ? Colors.black : null,
                                        ),
                                      ),
                                    ),
                                    selected: sel,
                                    onSelected: (_) => setState(() => _selectedGroup = grp),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                        if (_fullSessionLabel.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'الكشف الموحد: $_fullSessionLabel',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? accent : Colors.teal.shade800),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
                            icon: const Icon(Icons.radar_rounded),
                            label: Text(
                              _lectureType == 'عملي'
                                  ? 'بدء تحضير المعمل الآن (15 دقيقة)'
                                  : 'تشغيل رادار التحضير الموحد الآن',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            onPressed: _startRadar,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildActiveRadarTab(Color cardBg, Color accent, Map<String, int> stats) {
    final presentList = _sessionRecords.values.where((e) => e['status'] == 'present').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _isPaused
                  ? [const Color(0xFF451A03), const Color(0xFF78350F)]
                  : [const Color(0xFF0F172A), const Color(0xFF115E59)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _isPaused ? Colors.amber : accent, width: 1.5),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          _isPaused
                              ? Icons.pause_circle_filled_rounded
                              : (_bleAdvertising ? Icons.bluetooth_searching_rounded : Icons.radar_rounded),
                          color: _isPaused ? Colors.amberAccent : Colors.greenAccent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _isPaused
                                ? 'التحضير متوقف مؤقتاً ⏸️'
                                : (_bleAdvertising ? 'الرادار والكود نشطان 📡' : 'الكود وماسح QR نشطان'),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Chip(
                    backgroundColor: Colors.black45,
                    label: Text(
                      'المتبقي: ${_formatCountdown(_remainingSeconds)}',
                      style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _fullSessionLabel,
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const Divider(color: Colors.white24, height: 20),
              if (_isPaused)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'تم إيقاف استقبال التحضير مؤقتاً.\nاضغط على (استئناف التحضير) بالأسفل عند وصول طلاب جدد.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                )
              else ...[
                const Text(
                  'الكود المتغيّر كل 10 ثوانٍ (للطلاب):',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  _activePin,
                  style: TextStyle(
                    fontSize: 42,
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
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isPaused ? Colors.green : Colors.amber,
                        foregroundColor: Colors.black,
                      ),
                      icon: Icon(_isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                      label: Text(
                        _isPaused ? 'استئناف التحضير' : 'إيقاف مؤقت',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _togglePauseResume,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.stop_circle_rounded),
                      label: const Text('إنهاء واعتماد', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: _finishSession,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('الحاضرون الموحدون (${presentList.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              icon: _isUploading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cloud_upload_rounded, size: 18),
              label: const Text('مزامنة الكشف الموحد'),
              onPressed: () => _syncAllRecordsToCloud(silent: false),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (presentList.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'سيظهر هنا تلقائياً كل طالب يُحضَّر عبر الرادار أو الكود أو ماسح QR لدى أي مشرف في القاعة.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ...presentList.map((st) => Card(
                color: cardBg,
                child: ListTile(
                  leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.check, color: Colors.white)),
                  title: Text(st['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('رقم القيد: ${st['student_id']} • ${st['method']}'),
                ),
              )),
      ],
    );
  }

  Widget _buildQrScannerTab(Color cardBg, Color accent) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: accent.withOpacity(0.14),
          child: Text(
            _isPaused
                ? '⏸️ التحضير متوقف مؤقتاً — اضغط استئناف من تبويب الرادار لمسح الأكواد'
                : '📷 وجّه الكاميرا نحو بطاقة QR الخاصة بالطالب لتسجيل حضوره فوراً في الكشف الموحد',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: _isPaused
              ? const Center(child: Icon(Icons.pause_circle_outline_rounded, size: 80, color: Colors.amber))
              : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: MobileScanner(onDetect: _onQrDetected),
                ),
        ),
      ],
    );
  }

  Widget _buildFullRosterTab(Color cardBg, Color accent, bool isDark) {
    final query = _rosterSearchCtrl.text.trim().toLowerCase();
    final filtered = _sectionRoster.where((st) {
      if (query.isEmpty) return true;
      final name = (st['full_name'] ?? '').toLowerCase();
      final id = (st['student_id'] ?? '').toLowerCase();
      return name.contains(query) || id.contains(query);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            controller: _rosterSearchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'بحث باسم الطالب أو رقم القيد...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _rosterSearchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _rosterSearchCtrl.clear();
                        setState(() {});
                      },
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('لا توجد نتائج مطابقة في كشف الشطر'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final st = filtered[i];
                    final sid = st['student_id']!;
                    final name = st['full_name']!;
                    final status = _sessionRecords[sid]?['status'] ?? 'absent';

                    return Card(
                      color: cardBg,
                      margin: const EdgeInsets.only(bottom: 6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text('رقم القيد: $sid', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                            _statusPillBtn(
                              label: '✅',
                              tooltip: 'محضر',
                              active: status == 'present',
                              activeColor: Colors.green,
                              onTap: () => _recordStudentStatus(
                                studentId: sid,
                                fullName: name,
                                status: 'present',
                                method: 'رصد يدوي من الكشف',
                              ),
                            ),
                            const SizedBox(width: 4),
                            _statusPillBtn(
                              label: '❌',
                              tooltip: 'مغيب',
                              active: status == 'absent',
                              activeColor: Colors.redAccent,
                              onTap: () => _recordStudentStatus(
                                studentId: sid,
                                fullName: name,
                                status: 'absent',
                                method: 'رصد غياب',
                              ),
                            ),
                            const SizedBox(width: 4),
                            _statusPillBtn(
                              label: '🟡',
                              tooltip: 'غائب بعذر',
                              active: status == 'excused',
                              activeColor: Colors.amber.shade700,
                              onTap: () => _recordStudentStatus(
                                studentId: sid,
                                fullName: name,
                                status: 'excused',
                                method: 'غائب بعذر معتمد',
                              ),
                            ),
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

  Widget _statusPillBtn({
    required String label,
    required String tooltip,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: active ? activeColor.withOpacity(0.22) : Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? activeColor : Colors.transparent, width: 1.5),
          ),
          child: Text(label, style: const TextStyle(fontSize: 14)),
        ),
      ),
    );
  }

  Widget _buildFinalStatsCard(Color cardBg, Color accent, Map<String, int> stats) {
    final total = stats['total'] ?? 0;
    final present = stats['present'] ?? 0;
    final absent = stats['absent'] ?? 0;
    final excused = stats['excused'] ?? 0;
    final pct = total > 0 ? ((present / total) * 100).toStringAsFixed(1) : '0.0';

    return Card(
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.green, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('📊 إحصائيات التحضير الختامية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                Chip(label: Text('نسبة الحضور: $pct%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
              ],
            ),
            Text(_fullSessionLabel, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _statBox('الحاضرون ✅', '$present', Colors.green)),
                const SizedBox(width: 8),
                Expanded(child: _statBox('المتغيبون ❌', '$absent', Colors.redAccent)),
                const SizedBox(width: 8),
                Expanded(child: _statBox('بعذر 🟡', '$excused', Colors.amber.shade700)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('نسخ ملخص الإحصائيات'),
                onPressed: () {
                  final summary =
                      '📊 إحصائيات التحضير\nالمقرر: $_fullSessionLabel\n✅ الحاضرون: $present\n❌ المتغيبون: $absent\n🟡 غائبون بعذر: $excused\nالإجمالي: $total ($pct%)';
                  Clipboard.setData(ClipboardData(text: summary));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ ملخص الإحصائيات ✓')),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBox(String title, String count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Text(count, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 2),
          Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class StudentFastAttendanceSheet extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String studentGender;
  const StudentFastAttendanceSheet({
    super.key,
    required this.studentId,
    required this.studentName,
    this.studentGender = 'male',
  });

  @override
  State<StudentFastAttendanceSheet> createState() => _StudentFastAttendanceSheetState();
}

class _StudentFastAttendanceSheetState extends State<StudentFastAttendanceSheet> {
  static const int _attManufacturerId = 0x3939;
  static const List<String> _practicalGroups = ['مجموعة A', 'مجموعة B', 'مجموعة C', 'مجموعة D'];

  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  final TextEditingController _pinCtrl = TextEditingController();

  String _selectedCourseCode = 'PHAR-101';
  String _lectureType = 'نظري';
  String _selectedGroup = 'مجموعة A';
  bool _broadcasting = false;
  bool _radarNearby = false;
  bool _submitting = false;
  StreamSubscription<List<ScanResult>>? _scanSub;

  Map<String, dynamic>? _verifiedRecord;
  Map<String, dynamic>? _activeSession;
  bool _sessionPausedByAdmin = false;

  String get _effectiveCourseCode {
    final item = CourseCatalog.findByCode(_selectedCourseCode);
    if (_lectureType == 'عملي' && item != null && item.hasPractical && !_selectedCourseCode.endsWith('L')) {
      return '${_selectedCourseCode}L';
    }
    return _selectedCourseCode;
  }

  String _buildSessionLabelForLec(String lecNum) {
    final code = _effectiveCourseCode;
    final cleanLec = lecNum.trim().isEmpty ? '1' : lecNum.trim();
    if (_lectureType == 'عملي') {
      return '$code | محاضرة $cleanLec | عملي ($_selectedGroup)';
    }
    return '$code | محاضرة $cleanLec | نظري';
  }

  String get _detectedLectureNum {
    if (_verifiedRecord != null && (_verifiedRecord!['lecture_num'] ?? '').toString().trim().isNotEmpty) {
      return _verifiedRecord!['lecture_num'].toString().trim();
    }
    if (_activeSession != null && (_activeSession!['lecture_num'] ?? '').toString().trim().isNotEmpty) {
      return _activeSession!['lecture_num'].toString().trim();
    }
    return '';
  }

  String get _computedSessionLabel {
    if (_verifiedRecord != null && (_verifiedRecord!['session_code'] ?? '').toString().trim().isNotEmpty) {
      return _verifiedRecord!['session_code'].toString().trim();
    }
    if (_activeSession != null && (_activeSession!['session_code'] ?? '').toString().trim().isNotEmpty) {
      return _activeSession!['session_code'].toString().trim();
    }
    return _buildSessionLabelForLec(_detectedLectureNum.isNotEmpty ? _detectedLectureNum : '1');
  }

  @override
  void initState() {
    super.initState();
    _checkVerifiedAttendanceStatus();
    _startAutoBluetoothPresence();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    BleSafeHelper.safeStopAll(_peripheral);
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkVerifiedAttendanceStatus() async {
    try {
      final code = _effectiveCourseCode;
      final grp = _lectureType == 'عملي' ? _selectedGroup : 'الكل';

      // 1. البحث عن الجلسة النشطة المفتوحة حالياً من قبل المشرف/المندوب لهذه المادة
      final sessList = await Supabase.instance.client
          .from('attendance_sessions')
          .select()
          .eq('course_code', code)
          .eq('lecture_type', _lectureType)
          .eq('group_name', grp)
          .eq('target_gender', widget.studentGender)
          .order('updated_at', ascending: false)
          .limit(1);

      Map<String, dynamic>? latestSess;
      if (sessList.isNotEmpty) {
        latestSess = Map<String, dynamic>.from(sessList.first);
      }

      // 2. التحقق هل تم تحضير الطالب في الجلسة النشطة أو في أحدث محاضرة مسجلة له في هذا المقرر
      Map<String, dynamic>? matchedRec;
      if (latestSess != null && (latestSess['session_code'] ?? '').toString().isNotEmpty) {
        final rec = await Supabase.instance.client
            .from('attendance')
            .select()
            .eq('student_id', widget.studentId)
            .eq('session_code', latestSess['session_code'])
            .maybeSingle();
        if (rec != null && (rec['status'] == 'present' || rec['status'] == 'excused')) {
          matchedRec = Map<String, dynamic>.from(rec);
        }
      }

      if (matchedRec == null) {
        final recentList = await Supabase.instance.client
            .from('attendance')
            .select()
            .eq('student_id', widget.studentId)
            .eq('course_code', code)
            .order('created_at', ascending: false)
            .limit(1);
        if (recentList.isNotEmpty) {
          final r = Map<String, dynamic>.from(recentList.first);
          final sc = (r['session_code'] ?? '').toString();
          final typeMatches = _lectureType == 'عملي' ? sc.contains(_selectedGroup) : sc.contains('نظري');
          if (typeMatches && (r['status'] == 'present' || r['status'] == 'excused')) {
            matchedRec = r;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _activeSession = latestSess;
        _verifiedRecord = matchedRec;
        _sessionPausedByAdmin = latestSess != null &&
            latestSess['is_active'] == true &&
            latestSess['is_paused'] == true;
      });
    } catch (_) {}
  }

  Future<void> _startAutoBluetoothPresence() async {
    final btReady = await BleSafeHelper.prepareBluetooth(promptTurnOn: false);
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
    final pin = _pinCtrl.text.trim();

    if (pin.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppPrefs.tr('أدخل الكود المكون من 4 أرقام', 'Enter 4-digit PIN')), backgroundColor: Colors.redAccent),
      );
      return;
    }

    await _checkVerifiedAttendanceStatus();

    if (_sessionPausedByAdmin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏸️ التحضير متوقف مؤقتاً من قِبل المندوب حالياً.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    // تحديد الجلسة ورقم المحاضرة تلقائياً من الجلسة النشطة للمشرف أو مطابقة الكود
    String matchedSession = '';
    String matchedLecNum = '';

    if (_activeSession != null && (_activeSession!['session_code'] ?? '').toString().isNotEmpty) {
      final candidateSession = _activeSession!['session_code'].toString();
      if (RadarCrypto.verifyPin(candidateSession, pin)) {
        matchedSession = candidateSession;
        matchedLecNum = (_activeSession!['lecture_num'] ?? '1').toString();
      }
    }

    // في حال عدم توفر إنترنت لجلب الجلسة النشطة، نطابق الكود تلقائياً مع أرقام المحاضرات (1..30)
    if (matchedSession.isEmpty) {
      for (int i = 1; i <= 30; i++) {
        final candidate = _buildSessionLabelForLec('$i');
        if (RadarCrypto.verifyPin(candidate, pin)) {
          matchedSession = candidate;
          matchedLecNum = '$i';
          break;
        }
      }
    }

    if (matchedSession.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppPrefs.tr('الكود غير صحيح أو انتهت مدته (تأكد من المقرر ونوع المحاضرة)', 'Invalid or expired PIN')),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final existing = await Supabase.instance.client
          .from('attendance')
          .select()
          .eq('student_id', widget.studentId)
          .eq('session_code', matchedSession)
          .maybeSingle();

      Map<String, dynamic> savedRow;
      if (existing != null) {
        savedRow = await Supabase.instance.client
            .from('attendance')
            .update({
              'status': 'present',
              'lecture_num': matchedLecNum,
              'recorded_by': 'تحضير ذاتي بالكود',
            })
            .eq('id', existing['id'])
            .select()
            .single();
      } else {
        savedRow = await Supabase.instance.client
            .from('attendance')
            .insert({
              'student_id': widget.studentId,
              'full_name': widget.studentName,
              'session_code': matchedSession,
              'course_code': _effectiveCourseCode,
              'lecture_num': matchedLecNum,
              'status': 'present',
              'recorded_by': 'تحضير ذاتي بالكود',
            })
            .select()
            .single();
      }

      // تحديث الذاكرة المحلية لسجل حضور الطالب ليظهر فوراً في "سجل حضوري"
      final prefs = await SharedPreferences.getInstance();
      final cachedList = jsonDecode(prefs.getString('cache_my_attendance') ?? '[]') as List<dynamic>;
      cachedList.removeWhere((e) => (e['session_code'] ?? '') == matchedSession);
      cachedList.insert(0, savedRow);
      await prefs.setString('cache_my_attendance', jsonEncode(cachedList));

      if (!mounted) return;
      setState(() {
        _submitting = false;
        _verifiedRecord = savedRow;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppPrefs.tr('تم تسجيل حضورك في المحاضرة رقم ($matchedLecNum) بنجاح ✓', 'Attendance recorded for Lecture #$matchedLecNum ✓')),
          backgroundColor: Colors.green,
        ),
      );
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getStringList('pending_offline_attendance') ?? [];
      final offlineRow = {
        'student_id': widget.studentId,
        'full_name': widget.studentName,
        'session_code': matchedSession,
        'course_code': _effectiveCourseCode,
        'lecture_num': matchedLecNum,
        'status': 'present',
        'recorded_by': 'تحضير ذاتي (أوفلاين)',
      };
      pending.add(jsonEncode(offlineRow));
      await prefs.setStringList('pending_offline_attendance', pending);

      final cachedList = jsonDecode(prefs.getString('cache_my_attendance') ?? '[]') as List<dynamic>;
      cachedList.removeWhere((e) => (e['session_code'] ?? '') == matchedSession);
      cachedList.insert(0, offlineRow);
      await prefs.setString('cache_my_attendance', jsonEncode(cachedList));

      if (!mounted) return;
      setState(() {
        _submitting = false;
        _verifiedRecord = offlineRow;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final lecNumDisplay = _detectedLectureNum;

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
                IconButton(
                  tooltip: 'تحديث حالة التحضير',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _checkVerifiedAttendanceStatus,
                ),
              ],
            ),
            if (_verifiedRecord != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF065F46), Color(0xFF047857)]),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.greenAccent, width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_rounded, color: Colors.greenAccent, size: 34),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _verifiedRecord!['status'] == 'excused'
                                ? 'تم اعتماد عذرك الرسمي 🟡'
                                : 'تم تحضيرك بنجاح وموثّق ✓',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'المقرر: ${_verifiedRecord!['session_code'] ?? _computedSessionLabel}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          if (lecNumDisplay.isNotEmpty)
                            Text(
                              'رقم المحاضرة المعتمد: محاضرة رقم ($lecNumDisplay)',
                              style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          Text(
                            'بواسطة: ${_verifiedRecord!['recorded_by'] ?? 'المندوب'}',
                            style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
                  Icon(
                    _broadcasting ? Icons.bluetooth_connected_rounded : Icons.bluetooth_disabled_rounded,
                    color: _broadcasting ? Colors.teal : Colors.orange,
                  ),
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
            DropdownButtonFormField<String>(
              value: _selectedCourseCode,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: AppPrefs.tr('كود واسم المقرر', 'Course Code'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: CourseCatalog.courses
                  .map((c) => DropdownMenuItem(
                        value: c.code,
                        child: Text(c.displayLabel(_lectureType), overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => _selectedCourseCode = v);
                  _checkVerifiedAttendanceStatus();
                }
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('نظري')),
                    selected: _lectureType == 'نظري',
                    onSelected: (_) {
                      setState(() => _lectureType = 'نظري');
                      _checkVerifiedAttendanceStatus();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('عملي')),
                    selected: _lectureType == 'عملي',
                    onSelected: (_) {
                      setState(() => _lectureType = 'عملي');
                      _checkVerifiedAttendanceStatus();
                    },
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
                        onSelected: (_) {
                          setState(() => _selectedGroup = grp);
                          _checkVerifiedAttendanceStatus();
                        },
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
    BleSafeHelper.safeStopAll(_peripheral);
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _initOfflineBleChat() async {
    final btReady = await BleSafeHelper.prepareBluetooth(promptTurnOn: false);
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
