import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'attendance_radar.dart';
import 'main.dart';

class AdminScreen extends StatefulWidget {
  final String adminName;
  final List<int> allowedTabs;
  final bool isFullAccess;

  const AdminScreen({
    super.key,
    required this.adminName,
    this.allowedTabs = const [0, 1, 2, 3, 4],
    this.isFullAccess = true,
  });

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  static const String _ownerId = '27094070';
  final _client = Supabase.instance.client;
  String _myStudentId = '';
  List<dynamic> _subjects = [];
  List<dynamic> _attendance = [];
  List<dynamic> _announcements = [];
  List<dynamic> _assignmentsList = [];
  List<dynamic> _recentMaterials = [];
  List<dynamic> _recentQuestions = [];
  List<dynamic> _scheduleList = [];
  List<dynamic> _supportContacts = [];
  List<dynamic> _subjectRefs = [];
  Map<String, String> _calendarOccasions = {};
  List> _batchDirectory = [];
  Map<String, String> _studentEmails = {};
  bool _isLoading = false;

  // --- التبويب 1: حقول ثابتة للإعلانات والتصويت والمناسبات والتنبيهات والتكاليف ---
  final TextEditingController _annTitleCtrl = TextEditingController();
  final TextEditingController _annDescCtrl = TextEditingController();
  final TextEditingController _annImgUrlCtrl = TextEditingController();
  final TextEditingController _annActionUrlCtrl = TextEditingController();
  final TextEditingController _annPollOptionsCtrl = TextEditingController();
  String _annTargetGender = 'all';

  final TextEditingController _occDateCtrl = TextEditingController();
  final TextEditingController _occTitleCtrl = TextEditingController();

  final TextEditingController _urgentCtrl = TextEditingController();
  final TextEditingController _notifTitleCtrl = TextEditingController();
  final TextEditingController _notifBodyCtrl = TextEditingController();
  String _notifTargetGender = 'all';

  final TextEditingController _taskSubjCtrl = TextEditingController();
  final TextEditingController _taskTitleCtrl = TextEditingController();
  final TextEditingController _taskDetailsCtrl = TextEditingController();
  final TextEditingController _taskDateCtrl = TextEditingController(text: '2026-12-05');
  String _taskTargetGender = 'all';

  // --- التبويب 2: حقول ثابتة للمواد والملفات والمرجع ---
  static const List<String> _fileTypeOptions = ['mp3', 'mp4', 'jpg', 'pdf', 'docx', 'xlsx', 'pptx', 'أخرى'];
  final TextEditingController _subjNameCtrl = TextEditingController();
  final TextEditingController _subjDescCtrl = TextEditingController();
  dynamic _selectedFileSubjId;
  final TextEditingController _lecNumCtrl = TextEditingController(text: '1');
  final TextEditingController _fileTitleCtrl = TextEditingController();
  String _selectedFileType = 'pdf';
  final TextEditingController _fileUrlCtrl = TextEditingController();

  bool _isUploadingFile = false;
  double _uploadProgress = 0.0;
  String _uploadingFileName = '';
  int _uploadingFileSizeBytes = 0;
  Map<String, dynamic>? _uploadedFilePreview;

  dynamic _selectedRefSubjId;
  final TextEditingController _refTitleCtrl = TextEditingController();
  final TextEditingController _refContentCtrl = TextEditingController();

  // --- التبويب 3: حقول ثابتة لبنك الأسئلة ---
  dynamic _selectedQSubjId;
  final TextEditingController _qTextCtrl = TextEditingController();
  final TextEditingController _opt1Ctrl = TextEditingController();
  final TextEditingController _opt2Ctrl = TextEditingController();
  final TextEditingController _opt3Ctrl = TextEditingController();
  final TextEditingController _opt4Ctrl = TextEditingController();
  int _qCorrectIdx = 0;
  final TextEditingController _qExpCtrl = TextEditingController();

  // --- التبويب 4: حقول ثابتة للجدول وكشف الحضور ---
  String _schedSelectedDay = 'السبت';
  String _schedTargetGender = 'male';
  final TextEditingController _orderCtrl = TextEditingController(text: 'المحاضرة الأولى');
  final TextEditingController _timeCtrl = TextEditingController(text: '08:00 - 10:00');
  final TextEditingController _schedSubjCtrl = TextEditingController();
  final TextEditingController _hallCtrl = TextEditingController();
  final TextEditingController _docCtrl = TextEditingController();
  String _selectedAttendanceSession = 'الكل';

  // --- التبويب 5: حقول ثابتة للدعم والأجهزة والتحديث ---
  final TextEditingController _latestVerCtrl = TextEditingController(text: '1.3.0');
  final TextEditingController _minVerCtrl = TextEditingController(text: '1.0.0');
  final TextEditingController _updateUrlCtrl = TextEditingController(
    text: 'https://github.com/780ramialhakami780-jpg/IQ_Pharmacy39/releases/latest/download/IQ_Pharmacy39.apk',
  );
  final TextEditingController _releaseNotesCtrl = TextEditingController();

  final TextEditingController _suppIdCtrl = TextEditingController();
  final TextEditingController _suppNameCtrl = TextEditingController();
  final TextEditingController _suppRoleCtrl = TextEditingController();

  final TextEditingController _aboutTextCtrl = TextEditingController();
  final TextEditingController _devNameCtrl = TextEditingController();
  final TextEditingController _devWaCtrl = TextEditingController();
  final TextEditingController _devTgCtrl = TextEditingController();

  final TextEditingController _studentSearchCtrl = TextEditingController();
  List<dynamic> _foundStudents = [];

  final TextEditingController _dirTitleCtrl = TextEditingController();
  final TextEditingController _dirValueCtrl = TextEditingController();
  String _dirType = 'رابط';
  String _dirTargetGender = 'all';

  bool get _isOwner => _myStudentId.trim() == _ownerId;

  List<int> get _effectiveAllowedTabs {
    final valid = widget.allowedTabs.where((i) => i >= 0 && i <= 4).toSet().toList()..sort();
    return valid.isEmpty ? [0, 1, 2, 3, 4] : valid;
  }

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  @override
  void dispose() {
    _annTitleCtrl.dispose();
    _annDescCtrl.dispose();
    _annImgUrlCtrl.dispose();
    _annActionUrlCtrl.dispose();
    _annPollOptionsCtrl.dispose();
    _occDateCtrl.dispose();
    _occTitleCtrl.dispose();
    _urgentCtrl.dispose();
    _notifTitleCtrl.dispose();
    _notifBodyCtrl.dispose();
    _taskSubjCtrl.dispose();
    _taskTitleCtrl.dispose();
    _taskDetailsCtrl.dispose();
    _taskDateCtrl.dispose();

    _subjNameCtrl.dispose();
    _subjDescCtrl.dispose();
    _lecNumCtrl.dispose();
    _fileTitleCtrl.dispose();
    _fileUrlCtrl.dispose();
    _refTitleCtrl.dispose();
    _refContentCtrl.dispose();

    _qTextCtrl.dispose();
    _opt1Ctrl.dispose();
    _opt2Ctrl.dispose();
    _opt3Ctrl.dispose();
    _opt4Ctrl.dispose();
    _qExpCtrl.dispose();

    _orderCtrl.dispose();
    _timeCtrl.dispose();
    _schedSubjCtrl.dispose();
    _hallCtrl.dispose();
    _docCtrl.dispose();

    _latestVerCtrl.dispose();
    _minVerCtrl.dispose();
    _updateUrlCtrl.dispose();
    _releaseNotesCtrl.dispose();
    _suppIdCtrl.dispose();
    _suppNameCtrl.dispose();
    _suppRoleCtrl.dispose();
    _aboutTextCtrl.dispose();
    _devNameCtrl.dispose();
    _devWaCtrl.dispose();
    _devTgCtrl.dispose();
    _studentSearchCtrl.dispose();
    _dirTitleCtrl.dispose();
    _dirValueCtrl.dispose();
    super.dispose();
  }

  dynamic _parseSubjId(dynamic rawId) {
    if (rawId == null) return null;
    if (rawId is int) return rawId;
    return int.tryParse(rawId.toString()) ?? rawId;
  }

  String _formatBytesSize(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _mapExtToStandardType(String rawExt) {
    final ext = rawExt.toLowerCase().replaceAll('.', '').trim();
    if (ext == 'mp3' || ext == 'm4a' || ext == 'wav' || ext == 'ogg' || ext == 'aac') return 'mp3';
    if (ext == 'mp4' || ext == 'mkv' || ext == 'mov' || ext == 'avi' || ext == 'webm') return 'mp4';
    if (ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'webp' || ext == 'gif') return 'jpg';
    if (ext == 'pdf') return 'pdf';
    if (ext == 'docx' || ext == 'doc') return 'docx';
    if (ext == 'xlsx' || ext == 'xls' || ext == 'csv') return 'xlsx';
    if (ext == 'pptx' || ext == 'ppt') return 'pptx';
    return 'أخرى';
  }

  String _mimeTypeForExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'mp3':
      case 'm4a':
        return 'audio/mpeg';
      case 'mp4':
        return 'video/mp4';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      default:
        return 'application/octet-stream';
    }
  }

  Future<String> _uploadBytesWithRealProgress({
    required String bucket,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
    bool updateFileProgressUi = true,
  }) async {
    if (kIsWeb) {
      if (updateFileProgressUi && mounted) setState(() => _uploadProgress = 0.35);
      await _client.storage.from(bucket).uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
      if (updateFileProgressUi && mounted) setState(() => _uploadProgress = 1.0);
      return _client.storage.from(bucket).getPublicUrl(fileName);
    }

    final rawStorageUrl = _client.storage.url.trim();
    final String endpointUrl = rawStorageUrl.startsWith('http')
        ? (rawStorageUrl.endsWith('/')
            ? '${rawStorageUrl}object/$bucket/$fileName'
            : '$rawStorageUrl/object/$bucket/$fileName')
        : 'https://stvavavzjrcxcivxykfv.supabase.co/storage/v1/object/$bucket/$fileName';

    final uploadUri = Uri.parse(endpointUrl);
    final httpClient = HttpClient();
    httpClient.connectionTimeout = const Duration(seconds: 25);
    try {
      final request = await httpClient.postUrl(uploadUri);
      _client.headers.forEach((key, value) {
        if (value.isNotEmpty) {
          request.headers.set(key, value);
        }
      });
      if (request.headers.value('apikey') == null) {
        request.headers.set('apikey', 'sb_publishable_2D5B4SJgPAwqZqqgpiFaMA_HzTlka-k');
      }
      if (request.headers.value(HttpHeaders.authorizationHeader) == null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer sb_publishable_2D5B4SJgPAwqZqqgpiFaMA_HzTlka-k',
        );
      }
      request.headers.set(HttpHeaders.contentTypeHeader, contentType);
      request.headers.set('x-upsert', 'true');
      request.contentLength = bytes.length;

      const int chunkSize = 16384;
      int sent = 0;
      while (sent < bytes.length) {
        final end = (sent + chunkSize < bytes.length) ? sent + chunkSize : bytes.length;
        request.add(bytes.sublist(sent, end));
        await request.flush();
        sent = end;
        if (updateFileProgressUi && mounted) {
          setState(() {
            _uploadProgress = (sent / bytes.length) * 0.95;
          });
        }
      }

      final response = await request.close();
      final respBody = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (updateFileProgressUi && mounted) setState(() => _uploadProgress = 1.0);
        return _client.storage.from(bucket).getPublicUrl(fileName);
      } else {
        throw Exception('Upload failed (${response.statusCode}): $respBody');
      }
    } catch (_) {
      if (updateFileProgressUi && mounted) setState(() => _uploadProgress = 0.65);
      await _client.storage.from(bucket).uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
      if (updateFileProgressUi && mounted) setState(() => _uploadProgress = 1.0);
      return _client.storage.from(bucket).getPublicUrl(fileName);
    } finally {
      httpClient.close();
    }
  }

  Future<String> _uploadImageToAnyPublicBucket(String fileName, Uint8List bytes, String ext) async {
    final mime = _mimeTypeForExt(ext);
    for (final bucketName in ['announcements', 'announcement', 'materials']) {
      try {
        return await _uploadBytesWithRealProgress(
          bucket: bucketName,
          fileName: fileName,
          bytes: bytes,
          contentType: mime,
          updateFileProgressUi: false,
        );
      } catch (_) {}
    }
    throw Exception('فشل الرفع إلى جميع مخازن الصور');
  }

  Future<void> _fetchInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    final myId = prefs.getString('student_id') ?? '';

    List<dynamic> subjs = [];
    try {
      final cachedRaw = prefs.getString('cache_subjects');
      if (cachedRaw != null && cachedRaw.isNotEmpty) {
        subjs = jsonDecode(cachedRaw) as List<dynamic>;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _myStudentId = myId;
        if (subjs.isNotEmpty && _subjects.isEmpty) {
          _subjects = subjs;
        }
      });
    }

    try {
      subjs = await _client.from('subjects').select().order('sort_order');
      await prefs.setString('cache_subjects', jsonEncode(subjs));
    } catch (_) {
      try {
        subjs = await _client.from('subjects').select();
        await prefs.setString('cache_subjects', jsonEncode(subjs));
      } catch (_) {}
    }

    List<dynamic> att = _attendance;
    try {
      att = await _client.from('attendance').select().order('created_at', ascending: false).limit(500);
    } catch (_) {}

    List<dynamic> anns = _announcements;
    List<dynamic> assigns = _assignmentsList;
    List<dynamic> mats = _recentMaterials;
    List<dynamic> qs = _recentQuestions;
    List<dynamic> scheds = _scheduleList;
    List<dynamic> supps = _supportContacts;
    List<dynamic> refs = _subjectRefs;
    final Map<String, String> emailMap = Map<String, String>.from(_studentEmails);

    try {
      anns = await _client.from('announcements').select().order('created_at', ascending: false);
    } catch (_) {}

    try {
      assigns = await _client.from('assignments').select().order('id', ascending: false).limit(30);
    } catch (_) {}

    try {
      mats = await _client.from('materials').select().order('id', ascending: false).limit(25);
    } catch (_) {}

    try {
      qs = await _client.from('questions').select().order('id', ascending: false).limit(20);
    } catch (_) {}

    try {
      scheds = await _client.from('schedule').select().order('id', ascending: false).limit(40);
    } catch (_) {}

    try {
      supps = await _client.from('support_contacts').select().order('sort_order');
    } catch (_) {}

    try {
      refs = await _client.from('subject_references').select().order('id', ascending: false);
    } catch (_) {}

    try {
      final studs = await _client.from('students').select('student_id, university_email');
      for (var s in studs) {
        if (s['university_email'] != null && s['university_email'].toString().isNotEmpty) {
          emailMap[s['student_id'].toString()] = s['university_email'].toString();
        }
      }
    } catch (_) {}

    try {
      final settingsRows = await _client.from('app_settings').select('key, value');
      for (final row in settingsRows) {
        final k = (row['key'] ?? '').toString();
        final v = (row['value'] ?? '').toString();
        if (k == 'urgent_banner' && _urgentCtrl.text.isEmpty && v.isNotEmpty) {
          _urgentCtrl.text = v;
        } else if (k == 'calendar_occasions' && v.isNotEmpty) {
          try {
            _calendarOccasions = Map<String, String>.from(jsonDecode(v));
          } catch (_) {}
        } else if (k == 'batch_directory' && v.isNotEmpty) {
          try {
            final decoded = jsonDecode(v) as List<dynamic>;
            _batchDirectory = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          } catch (_) {}
        } else if (k == 'latest_version' && v.isNotEmpty) {
          _latestVerCtrl.text = v;
        } else if (k == 'min_version' && v.isNotEmpty) {
          _minVerCtrl.text = v;
        } else if (k == 'update_url' && v.isNotEmpty) {
          _updateUrlCtrl.text = v;
        } else if (k == 'update_notes' && v.isNotEmpty) {
          _releaseNotesCtrl.text = v;
        } else if (k == 'about_app_info' && v.isNotEmpty) {
          try {
            final info = jsonDecode(v) as Map<String, dynamic>;
            if (_aboutTextCtrl.text.isEmpty) _aboutTextCtrl.text = (info['about'] ?? '').toString();
            if (_devNameCtrl.text.isEmpty) _devNameCtrl.text = (info['developer'] ?? '').toString();
            if (_devWaCtrl.text.isEmpty) _devWaCtrl.text = (info['whatsapp'] ?? '').toString();
            if (_devTgCtrl.text.isEmpty) _devTgCtrl.text = (info['telegram'] ?? '').toString();
          } catch (_) {}
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _myStudentId = myId;
      _subjects = subjs;
      _attendance = att;
      _announcements = anns;
      _assignmentsList = assigns;
      _recentMaterials = mats;
      _recentQuestions = qs;
      _scheduleList = scheds;
      _supportContacts = supps;
      _subjectRefs = refs;
      _studentEmails = emailMap;
    });
  }

  void _showMsg(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: isError ? Colors.redAccent : Colors.teal),
    );
  }

  Future<void> _promptAndUnlinkDevice(Map<String, dynamic> st, VoidCallback onUnlinked) async {
    final targetId = (st['student_id'] ?? '').toString().trim();
    final targetName = (st['full_name'] ?? '').toString();
    final targetIsAdmin = st['is_admin'] == true;

    if (targetId == _ownerId || targetIsAdmin) {
      _showMsg('حساب المالك والمشرفين محمي ولا يمكن فك ارتباطه نهائياً', isError: true);
      return;
    }

    String requiredPin = '9988';
    try {
      final res = await _client
          .from('app_settings')
          .select('value')
          .eq('key', 'unlink_pin')
          .maybeSingle();
      if (res != null && res['value'] != null && res['value'].toString().trim().isNotEmpty) {
        requiredPin = res['value'].toString().trim();
      }
    } catch (_) {}

    if (!mounted) return;
    final pinCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('تأكيد فك ارتباط الجهاز'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الطالب: $targetName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text('رقم القيد: $targetId', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 14),
            const Text('أدخل كلمة مرور فك الارتباط للمتابعة:', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: pinCtrl,
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
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.black),
            onPressed: () async {
              if (pinCtrl.text.trim() != requiredPin) {
                _showMsg('كلمة مرور فك الارتباط غير صحيحة!', isError: true);
                return;
              }
              Navigator.pop(dialogCtx);
              try {
                await _client.from('students').update({'device_id': null}).eq('student_id', targetId);
                onUnlinked();
                _showMsg('تم فك ارتباط الجهاز بنجاح، يمكن للطالب الدخول من هاتفه الجديد الآن');
              } on PostgrestException catch (pe) {
                _showMsg('خطأ قاعدة البيانات: ${pe.message}', isError: true);
              } catch (_) {
                _showMsg('فشل فك الارتباط من قاعدة البيانات', isError: true);
              }
            },
            child: const Text('تأكيد وفك القفل', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _tabTitleForIndex(int idx) {
    switch (idx) {
      case 0:
        return 'الإعلانات والتصويت';
      case 1:
        return 'المواد والمرجع';
      case 2:
        return 'بنك الأسئلة';
      case 3:
        return 'الجدول وكشف الحضور';
      case 4:
        return 'الدعم والأجهزة والتحديث';
      default:
        return 'إدارة الدفعة';
    }
  }

  Widget _tabBodyForIndex(int idx) {
    switch (idx) {
      case 0:
        return _buildNotificationsAndTasksTab();
      case 1:
        return _buildSubjectsAndFilesTab();
      case 2:
        return _buildAddQuestionTab();
      case 3:
        return _buildScheduleAndAttendanceTab();
      case 4:
        return _buildDevicesAndDirectoryTab();
      default:
        return _buildNotificationsAndTasksTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allowed = _effectiveAllowedTabs;
    final isSingleRole = allowed.length == 1;

    if (isSingleRole) {
      final singleIdx = allowed.first;
      return Scaffold(
        appBar: AppBar(
          title: Text('إدارة • ${_tabTitleForIndex(singleIdx)}', style: const TextStyle(fontSize: 17)),
          backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFF0F766E),
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'تحديث البيانات',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _fetchInitialData,
            ),
          ],
        ),
        body: _isLoading ? const Center(child: CircularProgressIndicator()) : _tabBodyForIndex(singleIdx),
      );
    }

    return DefaultTabController(
      length: allowed.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isFullAccess ? 'لوحة إدارة الدفعة السرية' : 'لوحة إدارة الدفعة (صلاحية مخصصة)'),
          backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFF0F766E),
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'تحديث البيانات',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _fetchInitialData,
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: isDark ? const Color(0xFF4FD1C5) : Colors.amberAccent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: allowed.map((idx) => Tab(text: _tabTitleForIndex(idx))).toList(),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: allowed.map((idx) => _tabBodyForIndex(idx)).toList(),
              ),
      ),
    );
  }

  Widget _buildNotificationsAndTasksTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('🖼️ نشر إعلان أو تصويت دفعة في الشريط العلوي', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
        const SizedBox(height: 6),
        const Text('يمكنك نشر إعلان مصوّر، أو طرح تصويت بخيارات متعددة ليصوّت الطلاب فور دخولهم التطبيق.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 10),
        TextField(controller: _annTitleCtrl, decoration: const InputDecoration(labelText: 'عنوان الإعلان أو سؤال التصويت (إلزامي)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(
          controller: _annPollOptionsCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'خيارات التصويت (اختياري - اكتب كل خيار في سطر مستقل)',
            hintText: 'مثال:\nتأجيل المحاضرة ليوم الثلاثاء\nإبقاء الموعد كما هو',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(controller: _annDescCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'وصف تفصيلي (اختياري)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _annImgUrlCtrl,
                decoration: const InputDecoration(labelText: 'رابط الصورة (اختياري للتصويت)', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12)),
              icon: const Icon(Icons.upload_rounded),
              label: const Text('رفع صورة'),
              onPressed: () async {
                AppLockGuard.isPickingExternalFile = true;
                XFile? picked;
                try {
                  final picker = ImagePicker();
                  picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                } finally {
                  AppLockGuard.isPickingExternalFile = false;
                }
                if (picked == null) return;
                setState(() => _isLoading = true);
                try {
                  final bytes = await picked.readAsBytes();
                  final ext = picked.name.split('.').last.toLowerCase();
                  final fileName = 'ann_${DateTime.now().millisecondsSinceEpoch}.$ext';
                  final publicUrl = await _uploadImageToAnyPublicBucket(fileName, bytes, ext);
                  if (mounted) {
                    setState(() => _annImgUrlCtrl.text = publicUrl);
                  }
                  _showMsg('تم رفع الصورة بنجاح ✓');
                } catch (e) {
                  _showMsg('تعذر رفع الصورة: $e', isError: true);
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(controller: _annActionUrlCtrl, decoration: const InputDecoration(labelText: 'رابط خارجي لزر "فتح الرابط" (اختياري)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _annTargetGender,
          decoration: const InputDecoration(labelText: 'الفئة المستهدفة', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('عام للدفعة (طلاب وطالبات)')),
            DropdownMenuItem(value: 'male', child: Text('شطر الطلاب فقط (بنين)')),
            DropdownMenuItem(value: 'female', child: Text('شطر الطالبات فقط (بنات)')),
          ],
          onChanged: (v) => setState(() => _annTargetGender = v ?? 'all'),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FD1C5), foregroundColor: Colors.black),
          icon: const Icon(Icons.publish_rounded),
          label: const Text('نشر الإعلان / التصويت الآن', style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: () async {
            final title = _annTitleCtrl.text.trim();
            final pollLines = _annPollOptionsCtrl.text
                .split('\n')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();

            if (title.isEmpty) {
              _showMsg('يرجى إدخال عنوان الإعلان أو سؤال التصويت', isError: true);
              return;
            }
            if (pollLines.isEmpty && _annImgUrlCtrl.text.trim().isEmpty) {
              _showMsg('يرجى رفع صورة للإعلان أو إدخال خيارين للتصويت', isError: true);
              return;
            }
            setState(() => _isLoading = true);
            try {
              try {
                await _client.from('announcements').insert({
                  'title': title,
                  'description': _annDescCtrl.text.trim(),
                  'image_url': _annImgUrlCtrl.text.trim(),
                  'action_url': _annActionUrlCtrl.text.trim(),
                  'poll_options': pollLines,
                  'poll_votes': {},
                  'target_gender': _annTargetGender,
                  'is_active': true,
                });
              } catch (_) {
                await _client.from('announcements').insert({
                  'title': title,
                  'description': _annDescCtrl.text.trim(),
                  'image_url': _annImgUrlCtrl.text.trim(),
                  'action_url': _annActionUrlCtrl.text.trim(),
                  'is_active': true,
                });
              }
              _annTitleCtrl.clear();
              _annDescCtrl.clear();
              _annImgUrlCtrl.clear();
              _annActionUrlCtrl.clear();
              _annPollOptionsCtrl.clear();
              await _fetchInitialData();
              _showMsg('تم النشر للدفعة بنجاح ✓');
            } on PostgrestException catch (pe) {
              _showMsg('فشل النشر: ${pe.message}', isError: true);
            } catch (e) {
              _showMsg('فشل النشر: $e', isError: true);
            } finally {
              if (mounted) setState(() => _isLoading = false);
            }
          },
        ),
        if (_announcements.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('الإعلانات والتصويتات النشطة حالياً:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ..._announcements.map((a) {
            final polls = (a['poll_options'] is List) ? (a['poll_options'] as List) : [];
            final votes = (a['poll_votes'] is Map) ? (a['poll_votes'] as Map) : {};
            return ListTile(
              dense: true,
              leading: Icon(polls.isNotEmpty ? Icons.poll_rounded : Icons.image_rounded, color: const Color(0xFF4FD1C5)),
              title: Text(a['title'] ?? ''),
              subtitle: polls.isNotEmpty ? Text('تصويت تفاعلي • إجمالي الأصوات: ${votes.length}') : null,
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                onPressed: () async {
                  await _client.from('announcements').delete().eq('id', a['id']);
                  await _fetchInitialData();
                  _showMsg('تم الحذف ✓');
                },
              ),
            );
          }),
        ],
        const Divider(height: 36),
        const Text('🎉 إضافة مناسبة للتقويم الميلادي (تظهر مكان الترحيب)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
        const SizedBox(height: 6),
        const Text('تظهر تلقائياً في اليوم المحدد (مثال: عيد الفطر، بداية الاختبارات، تخرج الدفعة).', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _occDateCtrl,
                decoration: const InputDecoration(labelText: 'التاريخ (YYYY-MM-DD)', hintText: '2026-12-01', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _occTitleCtrl,
                decoration: const InputDecoration(labelText: 'نص المناسبة', hintText: 'بالتوفيق في الاختبارات 🎓', border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          icon: const Icon(Icons.event_available_rounded),
          label: const Text('حفظ المناسبة في تقويم التطبيق'),
          onPressed: () async {
            final d = _occDateCtrl.text.trim();
            final t = _occTitleCtrl.text.trim();
            if (d.isEmpty || t.isEmpty) {
              _showMsg('يرجى إدخال التاريخ ونص المناسبة', isError: true);
              return;
            }
            setState(() => _isLoading = true);
            try {
              final updatedEvents = Map<String, String>.from(_calendarOccasions);
              updatedEvents[d] = t;
              await _client.from('app_settings').upsert({'key': 'calendar_occasions', 'value': jsonEncode(updatedEvents)});
              _calendarOccasions = updatedEvents;
              _occDateCtrl.clear();
              _occTitleCtrl.clear();
              _showMsg('تمت إضافة المناسبة ليوم $d بنجاح ✓');
            } on PostgrestException catch (pe) {
              _showMsg('خطأ قاعدة البيانات: ${pe.message}', isError: true);
            } catch (_) {
              _showMsg('فشل حفظ المناسبة', isError: true);
            } finally {
              if (mounted) setState(() => _isLoading = false);
            }
          },
        ),
        if (_calendarOccasions.isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._calendarOccasions.entries.map((entry) => ListTile(
                dense: true,
                leading: const Icon(Icons.celebration_rounded, color: Colors.amberAccent, size: 20),
                title: Text(entry.value, style: const TextStyle(fontSize: 13)),
                subtitle: Text('التاريخ: ${entry.key}', style: const TextStyle(fontSize: 11)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                  onPressed: () async {
                    final updatedEvents = Map<String, String>.from(_calendarOccasions)..remove(entry.key);
                    await _client.from('app_settings').upsert({'key': 'calendar_occasions', 'value': jsonEncode(updatedEvents)});
                    setState(() => _calendarOccasions = updatedEvents);
                    _showMsg('تم حذف المناسبة');
                  },
                ),
              )),
        ],
        const Divider(height: 36),
        const Text('🚨 شريط التنبيه العاجل أعلى الرئيسية', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.redAccent)),
        const SizedBox(height: 10),
        TextField(
          controller: _urgentCtrl,
          decoration: const InputDecoration(labelText: 'نص التنبيه العاجل', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.campaign),
                label: const Text('تثبيت التنبيه'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                onPressed: () async {
                  if (_urgentCtrl.text.trim().isEmpty) return;
                  setState(() => _isLoading = true);
                  try {
                    await _client.from('app_settings').upsert({'key': 'urgent_banner', 'value': _urgentCtrl.text.trim()});
                    _showMsg('تم تفعيل الشريط العاجل لجميع الطلاب ✓');
                  } on PostgrestException catch (pe) {
                    _showMsg('فشل التحديث: ${pe.message}', isError: true);
                  } catch (_) {
                    _showMsg('فشل التحديث', isError: true);
                  } finally {
                    if (mounted) setState(() => _isLoading = false);
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.visibility_off),
              label: const Text('إخفاء الشريط'),
              onPressed: () async {
                setState(() => _isLoading = true);
                try {
                  await _client.from('app_settings').upsert({'key': 'urgent_banner', 'value': ''});
                  _urgentCtrl.clear();
                  _showMsg('تم إخفاء الشريط العاجل ✓');
                } catch (_) {
                  _showMsg('فشل الإخفاء', isError: true);
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
            ),
          ],
        ),
        const Divider(height: 36),
        const Text('📢 إرسال إشعار عام للدفعة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
        const SizedBox(height: 10),
        TextField(controller: _notifTitleCtrl, decoration: const InputDecoration(labelText: 'عنوان الإشعار', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: _notifBodyCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'نص الإشعار', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _notifTargetGender,
          decoration: const InputDecoration(labelText: 'الفئة المستهدفة', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('عام للدفعة (طلاب وطالبات)')),
            DropdownMenuItem(value: 'male', child: Text('شطر الطلاب فقط (بنين)')),
            DropdownMenuItem(value: 'female', child: Text('شطر الطالبات فقط (بنات)')),
          ],
          onChanged: (v) => setState(() => _notifTargetGender = v ?? 'all'),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          icon: const Icon(Icons.send),
          label: const Text('نشر الإشعار الآن'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FD1C5), foregroundColor: Colors.black),
          onPressed: () async {
            if (_notifTitleCtrl.text.trim().isEmpty || _notifBodyCtrl.text.trim().isEmpty) {
              _showMsg('يرجى إدخال عنوان ونص الإشعار', isError: true);
              return;
            }
            setState(() => _isLoading = true);
            try {
              try {
                await _client.from('notifications').insert({
                  'title': _notifTitleCtrl.text.trim(),
                  'body': _notifBodyCtrl.text.trim(),
                  'sender_name': widget.adminName,
                  'target_gender': _notifTargetGender,
                });
              } catch (_) {
                await _client.from('notifications').insert({
                  'title': _notifTitleCtrl.text.trim(),
                  'body': _notifBodyCtrl.text.trim(),
                  'sender_name': widget.adminName,
                });
              }
              _notifTitleCtrl.clear();
              _notifBodyCtrl.clear();
              _showMsg('تم إرسال الإشعار لجميع الطلاب بنجاح ✓');
            } on PostgrestException catch (pe) {
              _showMsg('فشل الإرسال: ${pe.message}', isError: true);
            } catch (_) {
              _showMsg('فشل الإرسال، تأكد من الإنترنت', isError: true);
            } finally {
              if (mounted) setState(() => _isLoading = false);
            }
          },
        ),
        const Divider(height: 36),
        const Text('📌 إضافة تكليف / واجب جديد', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
        const SizedBox(height: 10),
        TextField(controller: _taskSubjCtrl, decoration: const InputDecoration(labelText: 'اسم المادة', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: _taskTitleCtrl, decoration: const InputDecoration(labelText: 'عنوان التكليف', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: _taskDetailsCtrl, decoration: const InputDecoration(labelText: 'التفاصيل المطلوبة', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: _taskDateCtrl, decoration: const InputDecoration(labelText: 'موعد التسليم (YYYY-MM-DD)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _taskTargetGender,
          decoration: const InputDecoration(labelText: 'الفئة المستهدفة', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('عام للدفعة (طلاب وطالبات)')),
            DropdownMenuItem(value: 'male', child: Text('شطر الطلاب فقط (بنين)')),
            DropdownMenuItem(value: 'female', child: Text('شطر الطالبات فقط (بنات)')),
          ],
          onChanged: (v) => setState(() => _taskTargetGender = v ?? 'all'),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          icon: const Icon(Icons.add_task),
          label: const Text('حفظ التكليف'),
          onPressed: () async {
            if (_taskTitleCtrl.text.trim().isEmpty) {
              _showMsg('يرجى كتابة عنوان التكليف', isError: true);
              return;
            }
            setState(() => _isLoading = true);
            try {
              try {
                await _client.from('assignments').insert({
                  'subject_name': _taskSubjCtrl.text.trim(),
                  'title': _taskTitleCtrl.text.trim(),
                  'details': _taskDetailsCtrl.text.trim(),
                  'due_date': _taskDateCtrl.text.trim(),
                  'target_gender': _taskTargetGender,
                });
              } catch (_) {
                await _client.from('assignments').insert({
                  'subject_name': _taskSubjCtrl.text.trim(),
                  'title': _taskTitleCtrl.text.trim(),
                  'details': _taskDetailsCtrl.text.trim(),
                  'due_date': _taskDateCtrl.text.trim(),
                });
              }
              _taskSubjCtrl.clear();
              _taskTitleCtrl.clear();
              _taskDetailsCtrl.clear();
              await _fetchInitialData();
              _showMsg('تمت إضافة التكليف بنجاح ✓');
            } on PostgrestException catch (pe) {
              _showMsg('فشل حفظ التكليف: ${pe.message}', isError: true);
            } catch (_) {
              _showMsg('حدث خطأ أثناء الحفظ', isError: true);
            } finally {
              if (mounted) setState(() => _isLoading = false);
            }
          },
        ),
        if (_assignmentsList.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('التكاليف الحالية:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ..._assignmentsList.take(15).map((t) => ListTile(
                dense: true,
                leading: const Icon(Icons.push_pin_rounded, color: Colors.redAccent, size: 18),
                title: Text('${t['subject_name'] ?? ''}: ${t['title'] ?? ''}'),
                subtitle: Text('التسليم: ${(t['due_date'] ?? '').toString().split('T').first}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                  onPressed: () async {
                    await _client.from('assignments').delete().eq('id', t['id']);
                    await _fetchInitialData();
                    _showMsg('تم حذف التكليف');
                  },
                ),
              )),
        ],
      ],
    );
  }

  Widget _buildSubjectsAndFilesTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFF4FD1C5) : const Color(0xFF0F766E);

    if (_subjects.isNotEmpty) {
      if (_selectedFileSubjId == null || !_subjects.any((s) => s['id'] == _selectedFileSubjId)) {
        _selectedFileSubjId = _subjects.first['id'];
      }
      if (_selectedRefSubjId == null || !_subjects.any((s) => s['id'] == _selectedRefSubjId)) {
        _selectedRefSubjId = _subjects.first['id'];
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('📚 إضافة مادة دراسية جديدة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
        const SizedBox(height: 10),
        TextField(controller: _subjNameCtrl, decoration: const InputDecoration(labelText: 'اسم المادة (مثلاً: Pharmacology)', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: _subjDescCtrl, decoration: const InputDecoration(labelText: 'وصف مختصر أو اسم الدكتور', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: () async {
            if (_subjNameCtrl.text.trim().isEmpty) return;
            setState(() => _isLoading = true);
            try {
              await _client.from('subjects').insert({
                'name': _subjNameCtrl.text.trim(),
                'subtitle': _subjDescCtrl.text.trim(),
                'color_hex': '#2B6CB0',
                'sort_order': _subjects.length + 1,
              });
              _subjNameCtrl.clear();
              _subjDescCtrl.clear();
              await _fetchInitialData();
              _showMsg('تمت إضافة المادة بنجاح ✓');
            } on PostgrestException catch (pe) {
              _showMsg('تعذر إضافة المادة: ${pe.message}', isError: true);
            } catch (_) {
              _showMsg('تعذر إضافة المادة', isError: true);
            } finally {
              if (mounted) setState(() => _isLoading = false);
            }
          },
          child: const Text('إضافة المادة'),
        ),
        const Divider(height: 36),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('📁 إضافة ملف أو محاضرة لمادة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
            IconButton(
              tooltip: 'تحديث قائمة المواد',
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF4FD1C5)),
              onPressed: () => _fetchInitialData(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_subjects.isNotEmpty)
          DropdownButtonFormField<dynamic>(
            value: _selectedFileSubjId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'اختر المادة', border: OutlineInputBorder()),
            items: _subjects
                .map<DropdownMenuItem<dynamic>>(
                  (s) => DropdownMenuItem<dynamic>(
                    value: s['id'],
                    child: Text((s['name'] ?? '').toString(), overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (val) => setState(() => _selectedFileSubjId = val),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text('لم يتم تحميل قائمة المواد بعد، اضغط تحديث أو أضف مادة بالأعلى.', style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: () => _fetchInitialData(),
                  child: const Text('تحديث الآن'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        TextField(controller: _lecNumCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'رقم المحاضرة', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: _fileTitleCtrl, decoration: const InputDecoration(labelText: 'عنوان الملف أو المحاضرة', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _selectedFileType,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'نوع الملف (الامتداد)',
            border: OutlineInputBorder(),
          ),
          items: _fileTypeOptions
              .map(
                (t) => DropdownMenuItem<String>(
                  value: t,
                  child: Text(t == 'أخرى' ? 'أخرى' : t.toUpperCase()),
                ),
              )
              .toList(),
          onChanged: (val) {
            if (val != null) setState(() => _selectedFileType = val);
          },
        ),
        if (_isUploadingFile) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'جاري رفع: $_uploadingFileName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(_uploadProgress * 100).round()}%',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: accent),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _uploadProgress,
                    minHeight: 7,
                    backgroundColor: Colors.grey.withOpacity(0.22),
                    color: accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatBytesSize((_uploadingFileSizeBytes * _uploadProgress).round())} / ${_formatBytesSize(_uploadingFileSizeBytes)}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
        if (_uploadedFilePreview != null && !_isUploadingFile) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.13),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.teal),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.insert_drive_file_rounded, color: Colors.teal, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (_uploadedFilePreview!['name'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_uploadedFilePreview!['size']} • نوع: ${_uploadedFilePreview!['type'] == 'أخرى' ? 'أخرى' : (_uploadedFilePreview!['type'] ?? '').toString().toUpperCase()} • جاهز للحفظ ✓',
                        style: const TextStyle(fontSize: 11, color: Colors.teal, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'إزالة الملف المرفوع',
                  icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 20),
                  onPressed: () {
                    setState(() {
                      _uploadedFilePreview = null;
                      _fileUrlCtrl.clear();
                    });
                  },
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _fileUrlCtrl,
                decoration: const InputDecoration(
                  labelText: 'رابط الملف المباشر أو ارفعه من هاتفك',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4FD1C5),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              ),
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('رفع ملف', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _isUploadingFile
                  ? null
                  : () async {
                      AppLockGuard.isPickingExternalFile = true;
                      FilePickerResult? result;
                      try {
                        result = await FilePicker.platform.pickFiles(
                          type: FileType.any,
                          withData: true,
                        );
                      } finally {
                        AppLockGuard.isPickingExternalFile = false;
                      }
                      if (result == null || result.files.isEmpty) return;
                      final picked = result.files.first;

                      Uint8List? bytes = picked.bytes;
                      if (bytes == null && picked.path != null && !kIsWeb) {
                        bytes = await File(picked.path!).readAsBytes();
                      }
                      if (bytes == null) {
                        _showMsg('تعذر قراءة الملف من الهاتف', isError: true);
                        return;
                      }

                      final rawExt = (picked.extension ?? '').toLowerCase();
                      final safeExt = rawExt.isNotEmpty ? rawExt : 'bin';
                      final standardType = _mapExtToStandardType(rawExt);
                      final fileName = 'mat_${DateTime.now().millisecondsSinceEpoch}.$safeExt';

                      setState(() {
                        _isUploadingFile = true;
                        _uploadProgress = 0.02;
                        _uploadingFileName = picked.name;
                        _uploadingFileSizeBytes = bytes!.length;
                      });

                      String lastErrDetail = '';
                      try {
                        String publicUrl = '';
                        try {
                          publicUrl = await _uploadBytesWithRealProgress(
                            bucket: 'materials',
                            fileName: fileName,
                            bytes: bytes,
                            contentType: _mimeTypeForExt(safeExt),
                          );
                        } catch (e1) {
                          lastErrDetail = e1.toString();
                          publicUrl = await _uploadBytesWithRealProgress(
                            bucket: 'announcements',
                            fileName: fileName,
                            bytes: bytes,
                            contentType: _mimeTypeForExt(safeExt),
                          );
                        }

                        if (!mounted) return;
                        setState(() {
                          _isUploadingFile = false;
                          _fileUrlCtrl.text = publicUrl;
                          _selectedFileType = standardType;
                          if (_fileTitleCtrl.text.trim().isEmpty) {
                            _fileTitleCtrl.text = picked.name.replaceAll(RegExp(r'\.[^.]+$'), '');
                          }
                          _uploadedFilePreview = {
                            'name': picked.name,
                            'size': _formatBytesSize(bytes!.length),
                            'type': standardType,
                            'url': publicUrl,
                          };
                        });
                        _showMsg('تم رفع الملف (${picked.name}) بنجاح ✓ اضغط الآن على حفظ الملف في المادة');
                      } catch (e) {
                        if (mounted) setState(() => _isUploadingFile = false);
                        final detail = lastErrDetail.isNotEmpty ? lastErrDetail : e.toString();
                        final shortDetail = detail.length > 120 ? detail.substring(0, 120) : detail;
                        _showMsg('تعذر رفع الملف ($shortDetail)', isError: true);
                      }
                    },
            ),
          ],
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: _isUploadingFile
              ? null
              : () async {
                  if (_selectedFileSubjId == null || _fileTitleCtrl.text.trim().isEmpty || _fileUrlCtrl.text.trim().isEmpty) {
                    _showMsg('يرجى اختيار المادة وكتابة عنوان الملف ورفعه أولاً', isError: true);
                    return;
                  }
                  setState(() => _isLoading = true);
                  try {
                    final dbType = _selectedFileType == 'أخرى' ? 'OTHER' : _selectedFileType.toUpperCase();
                    await _client.from('materials').insert({
                      'subject_id': _parseSubjId(_selectedFileSubjId),
                      'lecture_number': int.tryParse(_lecNumCtrl.text.trim()) ?? 1,
                      'title': _fileTitleCtrl.text.trim(),
                      'file_type': dbType,
                      'file_url': _fileUrlCtrl.text.trim(),
                    });
                    if (mounted) {
                      setState(() {
                        _fileTitleCtrl.clear();
                        _fileUrlCtrl.clear();
                        _uploadedFilePreview = null;
                      });
                    }
                    await _fetchInitialData();
                    _showMsg('تم حفظ الملف في المادة بنجاح ✓');
                  } on PostgrestException catch (pe) {
                    _showMsg('خطأ قاعدة البيانات: ${pe.message}', isError: true);
                  } catch (e) {
                    _showMsg('فشل حفظ الملف: $e', isError: true);
                  } finally {
                    if (mounted) setState(() => _isLoading = false);
                  }
                },
          child: const Text('حفظ الملف في المادة'),
        ),
        if (_recentMaterials.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('آخر الملفات المرفوعة في المواد:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ..._recentMaterials.take(10).map((m) => ListTile(
                dense: true,
                leading: const Icon(Icons.insert_drive_file_rounded, color: Colors.amberAccent, size: 18),
                title: Text(m['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('محاضرة ${m['lecture_number'] ?? 1} • ${m['file_type'] ?? 'PDF'}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                  onPressed: () async {
                    await _client.from('materials').delete().eq('id', m['id']);
                    await _fetchInitialData();
                    _showMsg('تم حذف الملف من المادة');
                  },
                ),
              )),
        ],
        const Divider(height: 36),
        const Text('🎒 إضافة بطاقة مرجع سريع لمادة (حقيبة ليلة الامتحان)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
        const SizedBox(height: 6),
        const Text('تظهر مقسمة حسب كل مادة داخل حقيبة المراجعة ليلة الامتحان وتعمل بدون إنترنت.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 10),
        if (_subjects.isNotEmpty)
          DropdownButtonFormField<dynamic>(
            value: _selectedRefSubjId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'المادة المرتبطة', border: OutlineInputBorder()),
            items: _subjects
                .map<DropdownMenuItem<dynamic>>(
                  (s) => DropdownMenuItem<dynamic>(
                    value: s['id'],
                    child: Text((s['name'] ?? '').toString(), overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (val) => setState(() => _selectedRefSubjId = val),
          ),
        const SizedBox(height: 8),
        TextField(controller: _refTitleCtrl, decoration: const InputDecoration(labelText: 'عنوان البطاقة (مثلاً: تصنيف أدوية الضغط)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: _refContentCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'المحتوى المختصر والقوانين أو الملاحظات', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FD1C5), foregroundColor: Colors.black),
          icon: const Icon(Icons.bookmark_add_rounded),
          label: const Text('حفظ البطاقة في مرجع المادة', style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: () async {
            if (_selectedRefSubjId == null || _refTitleCtrl.text.trim().isEmpty || _refContentCtrl.text.trim().isEmpty) {
              _showMsg('يرجى اختيار المادة وكتابة عنوان ومحتوى البطاقة', isError: true);
              return;
            }
            setState(() => _isLoading = true);
            try {
              await _client.from('subject_references').insert({
                'subject_id': _parseSubjId(_selectedRefSubjId),
                'title': _refTitleCtrl.text.trim(),
                'content': _refContentCtrl.text.trim(),
              });
              _refTitleCtrl.clear();
              _refContentCtrl.clear();
              await _fetchInitialData();
              _showMsg('تمت إضافة بطاقة المرجع للمادة بنجاح ✓');
            } on PostgrestException catch (pe) {
              _showMsg('خطأ قاعدة البيانات: ${pe.message}', isError: true);
            } catch (_) {
              _showMsg('فشل الحفظ، تأكد من إنشاء جدول subject_references', isError: true);
            } finally {
              if (mounted) setState(() => _isLoading = false);
            }
          },
        ),
        if (_subjectRefs.isNotEmpty) ...[
          const SizedBox(height: 10),
          ..._subjectRefs.take(15).map((r) => ListTile(
                dense: true,
                leading: const Icon(Icons.menu_book_rounded, color: Color(0xFF4FD1C5)),
                title: Text(r['title'] ?? ''),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () async {
                    await _client.from('subject_references').delete().eq('id', r['id']);
                    await _fetchInitialData();
                  },
                ),
              )),
        ],
      ],
    );
  }

  Widget _buildAddQuestionTab() {
    if (_subjects.isNotEmpty) {
      if (_selectedQSubjId == null || !_subjects.any((s) => s['id'] == _selectedQSubjId)) {
        _selectedQSubjId = _subjects.first['id'];
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('❓ إضافة سؤال جديد لبنك الأسئلة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
        const SizedBox(height: 12),
        if (_subjects.isNotEmpty)
          DropdownButtonFormField<dynamic>(
            value: _selectedQSubjId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'اختر المادة', border: OutlineInputBorder()),
            items: _subjects
                .map<DropdownMenuItem<dynamic>>(
                  (s) => DropdownMenuItem<dynamic>(
                    value: s['id'],
                    child: Text((s['name'] ?? '').toString(), overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (val) => setState(() => _selectedQSubjId = val),
          ),
        const SizedBox(height: 10),
        TextField(controller: _qTextCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'نص السؤال', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: _opt1Ctrl, decoration: const InputDecoration(labelText: 'الخيار الأول (A)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: _opt2Ctrl, decoration: const InputDecoration(labelText: 'الخيار الثاني (B)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: _opt3Ctrl, decoration: const InputDecoration(labelText: 'الخيار الثالث (C)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: _opt4Ctrl, decoration: const InputDecoration(labelText: 'الخيار الرابع (D)', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          value: _qCorrectIdx,
          decoration: const InputDecoration(labelText: 'الإجابة الصحيحة', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 0, child: Text('الخيار الأول (A)')),
            DropdownMenuItem(value: 1, child: Text('الخيار الثاني (B)')),
            DropdownMenuItem(value: 2, child: Text('الخيار الثالث (C)')),
            DropdownMenuItem(value: 3, child: Text('الخيار الرابع (D)')),
          ],
          onChanged: (val) => setState(() => _qCorrectIdx = val ?? 0),
        ),
        const SizedBox(height: 10),
        TextField(controller: _qExpCtrl, decoration: const InputDecoration(labelText: 'توضيح الإجابة (اختياري)', border: OutlineInputBorder())),
        const SizedBox(height: 14),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FD1C5), foregroundColor: Colors.black),
          onPressed: () async {
            if (_selectedQSubjId == null || _qTextCtrl.text.trim().isEmpty) {
              _showMsg('يرجى اختيار المادة وكتابة نص السؤال', isError: true);
              return;
            }
            final opts = [_opt1Ctrl.text.trim(), _opt2Ctrl.text.trim(), _opt3Ctrl.text.trim(), _opt4Ctrl.text.trim()]
                .where((e) => e.isNotEmpty)
                .toList();
            if (opts.length < 2) {
              _showMsg('أدخل خيارين على الأقل', isError: true);
              return;
            }
            final safeCorrectIdx = _qCorrectIdx >= opts.length ? 0 : _qCorrectIdx;
            setState(() => _isLoading = true);
            try {
              await _client.from('questions').insert({
                'subject_id': _parseSubjId(_selectedQSubjId),
                'question_text': _qTextCtrl.text.trim(),
                'options': jsonEncode(opts),
                'correct_index': safeCorrectIdx,
                'explanation': _qExpCtrl.text.trim(),
              });
              _qTextCtrl.clear();
              _opt1Ctrl.clear();
              _opt2Ctrl.clear();
              _opt3Ctrl.clear();
              _opt4Ctrl.clear();
              _qExpCtrl.clear();
              await _fetchInitialData();
              _showMsg('تمت إضافة السؤال لبنك المادة بنجاح ✓');
            } on PostgrestException catch (pe) {
              _showMsg('فشل حفظ السؤال: ${pe.message}', isError: true);
            } catch (_) {
              _showMsg('فشل حفظ السؤال', isError: true);
            } finally {
              if (mounted) setState(() => _isLoading = false);
            }
          },
          child: const Text('حفظ السؤال في البنك'),
        ),
        if (_recentQuestions.isNotEmpty) ...[
          const Divider(height: 32),
          const Text('آخر الأسئلة المضافة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ..._recentQuestions.take(10).map((q) => ListTile(
                dense: true,
                leading: const Icon(Icons.quiz_rounded, color: Color(0xFF4FD1C5), size: 18),
                title: Text(q['question_text'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                  onPressed: () async {
                    await _client.from('questions').delete().eq('id', q['id']);
                    await _fetchInitialData();
                    _showMsg('تم حذف السؤال');
                  },
                ),
              )),
        ],
      ],
    );
  }

  Widget _buildScheduleAndAttendanceTab() {
    final sessionCodes = <String>{
      'الكل',
      ..._attendance.map((e) => (e['session_code'] ?? '').toString()).where((e) => e.isNotEmpty),
    }.toList();
    if (!sessionCodes.contains(_selectedAttendanceSession)) {
      _selectedAttendanceSession = 'الكل';
    }

    final filteredAtt = _selectedAttendanceSession == 'الكل'
        ? _attendance
        : _attendance.where((a) => (a['session_code'] ?? '').toString() == _selectedAttendanceSession).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF115E59)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF4FD1C5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.radar_rounded, color: Color(0xFF4FD1C5), size: 28),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'رادار التحضير السريع (نظري + مجموعات العملي A-D)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'التقط حضور القاعة أو مجموعة العملي في ثوانٍ عبر البلوتوث أو الكود المتغير كل 10 ثوانٍ بدون إنترنت.',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FD1C5), foregroundColor: Colors.black),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('فتح رادار التحضير الآن', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => AdminRadarScreen(adminName: widget.adminName)),
                    );
                    _fetchInitialData();
                  },
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 32),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🔄 تدوير مجموعات عملي يوم الأحد (شطر البنين)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                const Text(
                  'يبدّل فترات المعامل يوم الأحد تلقائياً بين المجموعات (A ↔ C و B ↔ D) بضغطة واحدة.',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('تبديل مجموعات الأحد الأسبوعية الآن'),
                    onPressed: () async {
                      setState(() => _isLoading = true);
                      try {
                        final sundayRows = await _client
                            .from('schedule')
                            .select()
                            .eq('target_gender', 'male')
                            .eq('day_name', 'الأحد');
                        const swapMap = {'A': 'C', 'C': 'A', 'B': 'D', 'D': 'B'};
                        int updatedCount = 0;
                        for (final r in sundayRows) {
                          final ord = (r['lecture_order'] ?? '').toString().trim();
                          if (swapMap.containsKey(ord)) {
                            await _client
                                .from('schedule')
                                .update({'lecture_order': swapMap[ord]})
                                .eq('id', r['id']);
                            updatedCount++;
                          }
                        }
                        await _fetchInitialData();
                        _showMsg(
                          updatedCount > 0
                              ? 'تم تبديل $updatedCount فترات عملي يوم الأحد (A↔C و B↔D) بنجاح ✓'
                              : 'لا توجد مجموعات عملي مسجلة ليوم الأحد (A/B/C/D) لتبديلها',
                        );
                      } on PostgrestException catch (pe) {
                        _showMsg('تعذر تبديل المجموعات: ${pe.message}', isError: true);
                      } catch (_) {
                        _showMsg('تعذر تبديل المجموعات حالياً', isError: true);
                      } finally {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('📅 إضافة محاضرة إلى الجدول', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _schedSelectedDay,
          decoration: const InputDecoration(labelText: 'اليوم', border: OutlineInputBorder()),
          items: ['السبت', 'الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس']
              .map((d) => DropdownMenuItem(value: d, child: Text(d)))
              .toList(),
          onChanged: (v) => setState(() => _schedSelectedDay = v ?? 'السبت'),
        ),
        const SizedBox(height: 8),
        TextField(controller: _orderCtrl, decoration: const InputDecoration(labelText: 'ترتيب المحاضرة أو رمز المجموعة (A/B/C/D)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: _timeCtrl, decoration: const InputDecoration(labelText: 'الوقت', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: _schedSubjCtrl, decoration: const InputDecoration(labelText: 'اسم المادة', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: _hallCtrl, decoration: const InputDecoration(labelText: 'القاعة', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: _docCtrl, decoration: const InputDecoration(labelText: 'اسم الدكتور', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _schedTargetGender,
          decoration: const InputDecoration(labelText: 'الجدول خاص بـ', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'male', child: Text('جدول الطلاب (بنين)')),
            DropdownMenuItem(value: 'female', child: Text('جدول الطالبات (بنات)')),
            DropdownMenuItem(value: 'all', child: Text('مشترك (طلاب وطالبات)')),
          ],
          onChanged: (v) => setState(() => _schedTargetGender = v ?? 'male'),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: () async {
            if (_schedSubjCtrl.text.trim().isEmpty) {
              _showMsg('يرجى إدخال اسم المادة', isError: true);
              return;
            }
            setState(() => _isLoading = true);
            try {
              try {
                await _client.from('schedule').insert({
                  'day_name': _schedSelectedDay,
                  'lecture_order': _orderCtrl.text.trim(),
                  'time_range': _timeCtrl.text.trim(),
                  'subject_name': _schedSubjCtrl.text.trim(),
                  'hall': _hallCtrl.text.trim(),
                  'doctor_name': _docCtrl.text.trim(),
                  'target_gender': _schedTargetGender,
                });
              } catch (_) {
                await _client.from('schedule').insert({
                  'day_name': _schedSelectedDay,
                  'lecture_order': _orderCtrl.text.trim(),
                  'time_range': _timeCtrl.text.trim(),
                  'subject_name': _schedSubjCtrl.text.trim(),
                  'hall': _hallCtrl.text.trim(),
                  'doctor_name': _docCtrl.text.trim(),
                });
              }
              _schedSubjCtrl.clear();
              _hallCtrl.clear();
              _docCtrl.clear();
              await _fetchInitialData();
              _showMsg('تمت إضافة المحاضرة للجدول بنجاح ✓');
            } on PostgrestException catch (pe) {
              _showMsg('فشل إضافة المحاضرة: ${pe.message}', isError: true);
            } catch (_) {
              _showMsg('فشل إضافة المحاضرة', isError: true);
            } finally {
              if (mounted) setState(() => _isLoading = false);
            }
          },
          child: const Text('إضافة للجدول'),
        ),
        if (_scheduleList.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('المحاضرات المسجلة في الجدول:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ..._scheduleList.take(15).map((sc) => ListTile(
                dense: true,
                leading: const Icon(Icons.schedule_rounded, color: Color(0xFF4FD1C5), size: 18),
                title: Text('${sc['day_name'] ?? ''} • ${sc['subject_name'] ?? ''} (${sc['lecture_order'] ?? ''})'),
                subtitle: Text('${sc['time_range'] ?? ''} • ${sc['hall'] ?? ''}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                  onPressed: () async {
                    await _client.from('schedule').delete().eq('id', sc['id']);
                    await _fetchInitialData();
                    _showMsg('تم حذف المحاضرة من الجدول');
                  },
                ),
              )),
        ],
        const Divider(height: 36),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('✅ كشف الحضور (${filteredAtt.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
            ElevatedButton.icon(
              icon: const Icon(Icons.copy_all, size: 18),
              label: const Text('نسخ الكشف للكلية / Excel'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: filteredAtt.isEmpty
                  ? null
                  : () {
                      final buffer = StringBuffer('رقم القيد\tالاسم الكامل\tالبريد الجامعي\tكود الجلسة\n');
                      for (var a in filteredAtt) {
                        final sid = (a['student_id'] ?? '').toString();
                        final email = _studentEmails[sid] ?? 'غير مرتبط';
                        buffer.writeln('$sid\t${a['full_name']}\t$email\t${a['session_code']}');
                      }
                      Clipboard.setData(ClipboardData(text: buffer.toString()));
                      _showMsg('تم نسخ الكشف (${filteredAtt.length} طالب) متضمناً البريد الجامعي جاهزاً لـ Excel');
                    },
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (sessionCodes.length > 1)
          DropdownButtonFormField<String>(
            value: _selectedAttendanceSession,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'تصفية حسب كود الجلسة / المادة / المجموعة', border: OutlineInputBorder()),
            items: sessionCodes.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => _selectedAttendanceSession = v ?? 'الكل'),
          ),
        const SizedBox(height: 8),
        if (filteredAtt.isEmpty)
          const Text('لا توجد سجلات حضور مسجلة حالياً', style: TextStyle(color: Colors.grey))
        else
          ...filteredAtt.take(60).map((a) {
            final sid = (a['student_id'] ?? '').toString();
            final email = _studentEmails[sid];
            return ListTile(
              dense: true,
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: Text(a['full_name'] ?? ''),
              subtitle: Text('قيد: $sid • كود: ${a['session_code']}${email != null ? '\n📧 $email' : ''}'),
            );
          }),
      ],
    );
  }

  Widget _buildDevicesAndDirectoryTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('🎨 شعار الترويسة المطبوع في وسط الشاشة الرئيسية', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
        const SizedBox(height: 6),
        const Text('ارفع صورة PNG شفافة الخلفية وسيظهر الشعار كأنه مطبوع مباشرة في ترويسة التطبيق لجميع الطلاب فوراً.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FD1C5), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14)),
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('اختيار ورفع شعار جديد (PNG شفاف)', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  AppLockGuard.isPickingExternalFile = true;
                  XFile? picked;
                  try {
                    final picker = ImagePicker();
                    picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
                  } finally {
                    AppLockGuard.isPickingExternalFile = false;
                  }
                  if (picked == null) return;
                  setState(() => _isLoading = true);
                  try {
                    final bytes = await picked.readAsBytes();
                    final ext = picked.name.split('.').last.toLowerCase();
                    final fileName = 'header_logo_${DateTime.now().millisecondsSinceEpoch}.$ext';
                    final publicUrl = await _uploadImageToAnyPublicBucket(fileName, bytes, ext);
                    await _client.from('app_settings').upsert({'key': 'header_logo_url', 'value': publicUrl});
                    _showMsg('تم تحديث شعار الترويسة بنجاح وسيظهر للجميع عند فتح التطبيق ✓');
                  } catch (e) {
                    _showMsg('تعذر رفع الشعار: $e', isError: true);
                  } finally {
                    if (mounted) setState(() => _isLoading = false);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12)),
              icon: const Icon(Icons.restore_rounded, color: Colors.orange),
              label: const Text('افتراضي'),
              onPressed: () async {
                setState(() => _isLoading = true);
                try {
                  await _client.from('app_settings').upsert({'key': 'header_logo_url', 'value': ''});
                  _showMsg('تمت استعادة الشعار الافتراضي للتطبيق ✓');
                } catch (_) {
                  _showMsg('فشلت الاستعادة', isError: true);
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
            ),
          ],
        ),
        const Divider(height: 36),
        const Text('🚀 إدارة تحديثات البرنامج (تحديث البرنامج في الإعدادات)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
        const SizedBox(height: 6),
        const Text('حدّد رقم الإصدار الجديد ليظهر للطلاب في شاشة تحديث البرنامج أو لفرض التحديث الإجباري.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: TextField(controller: _latestVerCtrl, decoration: const InputDecoration(labelText: 'أحدث إصدار متاح', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _minVerCtrl, decoration: const InputDecoration(labelText: 'الحد الأدنى الإجباري', border: OutlineInputBorder()))),
          ],
        ),
        const SizedBox(height: 8),
        TextField(controller: _updateUrlCtrl, decoration: const InputDecoration(labelText: 'رابط تحميل التحديث (APK)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: _releaseNotesCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'ملاحظات وما الجديد في هذا التحديث', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FD1C5), foregroundColor: Colors.black),
          icon: const Icon(Icons.system_update_rounded),
          label: const Text('حفظ إعدادات التحديث', style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: () async {
            setState(() => _isLoading = true);
            try {
              await _client.from('app_settings').upsert([
                {'key': 'latest_version', 'value': _latestVerCtrl.text.trim()},
                {'key': 'min_version', 'value': _minVerCtrl.text.trim()},
                {'key': 'update_url', 'value': _updateUrlCtrl.text.trim()},
                {'key': 'update_notes', 'value': _releaseNotesCtrl.text.trim()},
              ]);
              _showMsg('تم تحديث بيانات الإصدار بنجاح ✓');
            } on PostgrestException catch (pe) {
              _showMsg('فشل حفظ بيانات التحديث: ${pe.message}', isError: true);
            } catch (_) {
              _showMsg('فشل حفظ بيانات التحديث', isError: true);
            } finally {
              if (mounted) setState(() => _isLoading = false);
            }
          },
        ),
        const Divider(height: 36),
        const Text('💬 إدارة قائمة المطورين والمناديب (للمحادثة الخاصة)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
        const SizedBox(height: 10),
        TextField(controller: _suppIdCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'رقم قيد المطور / المندوب', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: _suppNameCtrl, decoration: const InputDecoration(labelText: 'الاسم الظاهر للطلاب', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: _suppRoleCtrl, decoration: const InputDecoration(labelText: 'الصفة (مثلاً: مطور التطبيق / مندوب الدفعة)', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FD1C5), foregroundColor: Colors.black),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('إضافة لقائمة التواصل', style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: () async {
            if (_suppIdCtrl.text.trim().isEmpty || _suppNameCtrl.text.trim().isEmpty) return;
            setState(() => _isLoading = true);
            try {
              await _client.from('support_contacts').insert({
                'student_id': _suppIdCtrl.text.trim(),
                'display_name': _suppNameCtrl.text.trim(),
                'role_title': _suppRoleCtrl.text.trim().isEmpty ? 'فريق الدعم' : _suppRoleCtrl.text.trim(),
                'is_active': true,
                'sort_order': _supportContacts.length + 1,
              });
              _suppIdCtrl.clear();
              _suppNameCtrl.clear();
              _suppRoleCtrl.clear();
              await _fetchInitialData();
              _showMsg('تمت الإضافة لقائمة الدعم والتواصل بنجاح ✓');
            } on PostgrestException catch (pe) {
              _showMsg('فشل الإضافة: ${pe.message}', isError: true);
            } catch (_) {
              _showMsg('فشل الإضافة', isError: true);
            } finally {
              if (mounted) setState(() => _isLoading = false);
            }
          },
        ),
        if (_supportContacts.isNotEmpty) ...[
          const SizedBox(height: 10),
          ..._supportContacts.map((sc) => ListTile(
                dense: true,
                leading: const Icon(Icons.support_agent_rounded, color: Color(0xFF4FD1C5)),
                title: Text('${sc['display_name']} (${sc['role_title']})'),
                subtitle: Text('رقم القيد: ${sc['student_id']}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () async {
                    await _client.from('support_contacts').delete().eq('id', sc['id']);
                    await _fetchInitialData();
                    _showMsg('تم الحذف من القائمة');
                  },
                ),
              )),
        ],
        const Divider(height: 36),
        const Text('ℹ️ تعديل نبذة التطبيق في شاشة تسجيل الدخول', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
        const SizedBox(height: 10),
        TextField(controller: _aboutTextCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'نص النبذة التعريفية للتطبيق', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: _devNameCtrl, decoration: const InputDecoration(labelText: 'اسم المطور / الفريق', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: _devWaCtrl, decoration: const InputDecoration(labelText: 'رابط واتساب اختياري (https://wa.me/967...)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: _devTgCtrl, decoration: const InputDecoration(labelText: 'رابط تيليجرام اختياري (https://t.me/...)', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: () async {
            setState(() => _isLoading = true);
            try {
              final payload = jsonEncode({
                'about': _aboutTextCtrl.text.trim(),
                'developer': _devNameCtrl.text.trim(),
                'whatsapp': _devWaCtrl.text.trim(),
                'telegram': _devTgCtrl.text.trim(),
              });
              await _client.from('app_settings').upsert({'key': 'about_app_info', 'value': payload});
              _showMsg('تم تحديث نبذة التطبيق بنجاح ✓');
            } on PostgrestException catch (pe) {
              _showMsg('فشل التحديث: ${pe.message}', isError: true);
            } catch (_) {
              _showMsg('فشل التحديث', isError: true);
            } finally {
              if (mounted) setState(() => _isLoading = false);
            }
          },
          child: const Text('حفظ بيانات النبذة'),
        ),
        const Divider(height: 36),
        const Text('📱 فك ارتباط هاتف طالب (محمي بكلمة مرور)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _studentSearchCtrl,
                decoration: const InputDecoration(labelText: 'رقم القيد أو اسم الطالب', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FD1C5), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16)),
              onPressed: () async {
                final q = _studentSearchCtrl.text.trim();
                if (q.isEmpty) return;
                try {
                  final res = await _client
                      .from('students')
                      .select()
                      .or('student_id.ilike.%$q%,full_name.ilike.%$q%')
                      .limit(10);
                  setState(() => _foundStudents = res);
                } on PostgrestException catch (pe) {
                  _showMsg('خطأ البحث: ${pe.message}', isError: true);
                } catch (_) {
                  _showMsg('تعذر البحث في قاعدة البيانات', isError: true);
                }
              },
              child: const Text('بحث', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._foundStudents.map((st) {
          final sid = (st['student_id'] ?? '').toString().trim();
          final hasDevice = st['device_id'] != null && st['device_id'].toString().isNotEmpty;
          final isProtected = sid == _ownerId || st['is_admin'] == true;
          final stGender = (st['gender'] ?? 'male').toString().trim().toLowerCase();

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(st['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'رقم القيد: $sid • ${isProtected ? 'حساب مشرف/مالك محمي' : (hasDevice ? 'مرتبط بهاتف' : 'غير مرتبط')}',
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final nextG = stGender == 'female' ? 'male' : 'female';
                      try {
                        await _client.from('students').update({'gender': nextG}).eq('student_id', sid);
                        setState(() => st['gender'] = nextG);
                        _showMsg('تم تغيير الشطر إلى: ${nextG == 'female' ? 'طالبة' : 'طالب'} ✓');
                      } on PostgrestException catch (pe) {
                        _showMsg('تعذر تحديث الشطر: ${pe.message}', isError: true);
                      } catch (_) {
                        _showMsg('تعذر تحديث الشطر', isError: true);
                      }
                    },
                    child: Text(
                      'الشطر: ${stGender == 'female' ? '👩‍🎓 طالبة' : '👨‍🎓 طالب'} (اضغط للتبديل)',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF4FD1C5), fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              trailing: isProtected
                  ? const Chip(
                      avatar: Icon(Icons.verified_user_rounded, size: 16, color: Colors.teal),
                      label: Text('محمي', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    )
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hasDevice ? Colors.orange : Colors.grey,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: !hasDevice
                          ? null
                          : () => _promptAndUnlinkDevice(
                                Map<String, dynamic>.from(st),
                                () => setState(() => st['device_id'] = null),
                              ),
                      child: const Text('فك القفل'),
                    ),
            ),
          );
        }),
        const Divider(height: 36),
        const Text('📇 إضافة عنصر لدليل المناديب والروابط', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
        const SizedBox(height: 10),
        TextField(controller: _dirTitleCtrl, decoration: const InputDecoration(labelText: 'العنوان (مثلاً: مندوب مادة العقاقير / رابط القناة)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: _dirValueCtrl, decoration: const InputDecoration(labelText: 'الرقم أو الرابط', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _dirType,
          decoration: const InputDecoration(labelText: 'النوع', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'رابط', child: Text('رابط إلكتروني')),
            DropdownMenuItem(value: 'تواصل', child: Text('رقم تواصل / مندوب')),
          ],
          onChanged: (v) => setState(() => _dirType = v ?? 'رابط'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _dirTargetGender,
          decoration: const InputDecoration(labelText: 'يظهر لـ', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('الجميع (طلاب وطالبات)')),
            DropdownMenuItem(value: 'male', child: Text('شطر الطلاب فقط (بنين)')),
            DropdownMenuItem(value: 'female', child: Text('شطر الطالبات فقط (بنات)')),
          ],
          onChanged: (v) => setState(() => _dirTargetGender = v ?? 'all'),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          icon: const Icon(Icons.add_link),
          label: const Text('إضافة إلى الدليل'),
          onPressed: () async {
            if (_dirTitleCtrl.text.trim().isEmpty || _dirValueCtrl.text.trim().isEmpty) return;
            setState(() => _isLoading = true);
            try {
              final updatedDir = List>.from(_batchDirectory);
              updatedDir.add({
                'title': _dirTitleCtrl.text.trim(),
                'value': _dirValueCtrl.text.trim(),
                'type': _dirType,
                'target_gender': _dirTargetGender,
              });
              await _client.from('app_settings').upsert({'key': 'batch_directory', 'value': jsonEncode(updatedDir)});
              _batchDirectory = updatedDir;
              _dirTitleCtrl.clear();
              _dirValueCtrl.clear();
              _showMsg('تمت الإضافة إلى دليل الدفعة بنجاح ✓');
            } on PostgrestException catch (pe) {
              _showMsg('فشلت الإضافة: ${pe.message}', isError: true);
            } catch (_) {
              _showMsg('فشلت الإضافة', isError: true);
            } finally {
              if (mounted) setState(() => _isLoading = false);
            }
          },
        ),
        if (_batchDirectory.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...List.generate(_batchDirectory.length, (i) {
            final item = _batchDirectory[i];
            return ListTile(
              dense: true,
              leading: Icon(item['type'] == 'تواصل' ? Icons.phone_rounded : Icons.link_rounded, color: Colors.amberAccent, size: 18),
              title: Text((item['title'] ?? '').toString()),
              subtitle: Text((item['value'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                onPressed: () async {
                  final updatedDir = List>.from(_batchDirectory)..removeAt(i);
                  await _client.from('app_settings').upsert({'key': 'batch_directory', 'value': jsonEncode(updatedDir)});
                  setState(() => _batchDirectory = updatedDir);
                  _showMsg('تم الحذف من الدليل');
                },
              ),
            );
          }),
        ],
      ],
    );
  }
}
