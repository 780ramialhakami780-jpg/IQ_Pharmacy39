import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'attendance_radar.dart';

class AdminScreen extends StatefulWidget {
  final String adminName;
  const AdminScreen({super.key, required this.adminName});

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
  List<dynamic> _supportContacts = [];
  List<dynamic> _subjectRefs = [];
  Map<String, String> _studentEmails = {};
  bool _isLoading = false;

  bool get _isOwner => _myStudentId.trim() == _ownerId;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final myId = prefs.getString('student_id') ?? '';

      final subjs = await _client.from('subjects').select().order('sort_order');
      final att = await _client.from('attendance').select().order('created_at', ascending: false).limit(500);
      List<dynamic> anns = [];
      List<dynamic> supps = [];
      List<dynamic> refs = [];
      final Map<String, String> emailMap = {};

      try {
        anns = await _client.from('announcements').select().order('created_at', ascending: false);
      } catch (_) {}

      try {
        supps = await _client.from('support_contacts').select().order('sort_order');
      } catch (_) {}

      try {
        refs = await _client.from('subject_references').select().order('created_at', ascending: false);
      } catch (_) {}

      try {
        final studs = await _client.from('students').select('student_id, university_email');
        for (var s in studs) {
          if (s['university_email'] != null && s['university_email'].toString().isNotEmpty) {
            emailMap[s['student_id'].toString()] = s['university_email'].toString();
          }
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _myStudentId = myId;
        _subjects = subjs;
        _attendance = att;
        _announcements = anns;
        _supportContacts = supps;
        _subjectRefs = refs;
        _studentEmails = emailMap;
      });
    } catch (_) {}
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
              Tab(text: 'الإعلانات والتصويت'),
              Tab(text: 'المواد والمرجع'),
              Tab(text: 'بنك الأسئلة'),
              Tab(text: 'الجدول وكشف الحضور'),
              Tab(text: 'الدعم والأجهزة والتحديث'),
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
                  _buildDevicesAndDirectoryTab(),
                ],
              ),
      ),
    );
  }

  Widget _buildNotificationsAndTasksTab() {
    final annTitleCtrl = TextEditingController();
    final annDescCtrl = TextEditingController();
    final annImgUrlCtrl = TextEditingController();
    final annActionUrlCtrl = TextEditingController();
    final annPollOptionsCtrl = TextEditingController();

    final occDateCtrl = TextEditingController();
    final occTitleCtrl = TextEditingController();

    final urgentCtrl = TextEditingController();
    final notifTitle = TextEditingController();
    final notifBody = TextEditingController();

    final taskSubj = TextEditingController();
    final taskTitle = TextEditingController();
    final taskDetails = TextEditingController();
    final taskDate = TextEditingController(text: '2026-11-25');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('🖼️ نشر إعلان أو تصويت دفعة في الشريط العلوي', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
        const SizedBox(height: 6),
        const Text('يمكنك نشر إعلان مصوّر، أو طرح تصويت بخيارات متعددة ليصوّت الطلاب فور دخولهم التطبيق.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 10),
        TextField(controller: annTitleCtrl, decoration: const InputDecoration(labelText: 'عنوان الإعلان أو سؤال التصويت (إلزامي)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(
          controller: annPollOptionsCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'خيارات التصويت (اختياري - اكتب كل خيار في سطر مستقل)',
            hintText: 'مثال:\nتأجيل المحاضرة ليوم الثلاثاء\nإبقاء الموعد كما هو',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(controller: annDescCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'وصف تفصيلي (اختياري)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: annImgUrlCtrl,
                decoration: const InputDecoration(labelText: 'رابط الصورة (اختياري للتصويت)', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12)),
              icon: const Icon(Icons.upload_rounded),
              label: const Text('رفع صورة'),
              onPressed: () async {
                final picker = ImagePicker();
                final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                if (picked == null) return;
                setState(() => _isLoading = true);
                try {
                  final bytes = await picked.readAsBytes();
                  final ext = picked.name.split('.').last;
                  final fileName = 'ann_${DateTime.now().millisecondsSinceEpoch}.$ext';
                  await _client.storage.from('announcements').uploadBinary(fileName, bytes);
                  final publicUrl = _client.storage.from('announcements').getPublicUrl(fileName);
                  annImgUrlCtrl.text = publicUrl;
                  _showMsg('تم رفع الصورة بنجاح ✓');
                } catch (e) {
                  _showMsg('تعذر رفع الصورة، تأكد من إعدادات Storage في Supabase', isError: true);
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(controller: annActionUrlCtrl, decoration: const InputDecoration(labelText: 'رابط خارجي لزر "فتح الرابط" (اختياري)', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FD1C5), foregroundColor: Colors.black),
          icon: const Icon(Icons.publish_rounded),
          label: const Text('نشر الإعلان / التصويت الآن', style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: () async {
            final title = annTitleCtrl.text.trim();
            final pollLines = annPollOptionsCtrl.text
                .split('\n')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();

            if (title.isEmpty) {
              _showMsg('يرجى إدخال عنوان الإعلان أو سؤال التصويت', isError: true);
              return;
            }
            if (pollLines.isEmpty && annImgUrlCtrl.text.trim().isEmpty) {
              _showMsg('يرجى رفع صورة للإعلان أو إدخال خيارين للتصويت', isError: true);
              return;
            }
            setState(() => _isLoading = true);
            try {
              await _client.from('announcements').insert({
                'title': title,
                'description': annDescCtrl.text.trim(),
                'image_url': annImgUrlCtrl.text.trim(),
                'action_url': annActionUrlCtrl.text.trim(),
                'poll_options': pollLines,
                'poll_votes': {},
                'is_active': true,
              });
              await _fetchInitialData();
              _showMsg('تم النشر للدفعة بنجاح ✓');
            } catch (_) {
              _showMsg('فشل النشر، تأكد من تنفيذ كود SQL الخاص بالتصويت', isError: true);
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
                  _showMsg('تم الحذف');
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
                controller: occDateCtrl,
                decoration: const InputDecoration(labelText: 'التاريخ (YYYY-MM-DD)', hintText: '2026-11-25', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: occTitleCtrl,
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
            final d = occDateCtrl.text.trim();
            final t = occTitleCtrl.text.trim();
            if (d.isEmpty || t.isEmpty) return;
            setState(() => _isLoading = true);
            try {
              Map<String, dynamic> events = {};
              final existing = await _client.from('app_settings').select('value').eq('key', 'calendar_occasions').maybeSingle();
              if (existing != null && existing['value'] != null && existing['value'].toString().isNotEmpty) {
                events = Map<String, dynamic>.from(jsonDecode(existing['value']));
              }
              events[d] = t;
              await _client.from('app_settings').upsert({'key': 'calendar_occasions', 'value': jsonEncode(events)});
              _showMsg('تمت إضافة المناسبة ليوم $d بنجاح ✓');
            } catch (_) {
              _showMsg('فشل حفظ المناسبة', isError: true);
            } finally {
              if (mounted) setState(() => _isLoading = false);
            }
          },
        ),
        const Divider(height: 36),
        const Text('🚨 شريط التنبيه العاجل أعلى الرئيسية', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.redAccent)),
        const SizedBox(height: 10),
        TextField(
          controller: urgentCtrl,
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
                  if (urgentCtrl.text.trim().isEmpty) return;
                  setState(() => _isLoading = true);
                  try {
                    await _client.from('app_settings').upsert({'key': 'urgent_banner', 'value': urgentCtrl.text.trim()});
                    _showMsg('تم تفعيل الشريط العاجل لجميع الطلاب');
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
                  _showMsg('تم إخفاء الشريط العاجل');
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

  Widget _buildSubjectsAndFilesTab() {
    final subjName = TextEditingController();
    final subjDesc = TextEditingController();

    int? selectedSubjId = _subjects.isNotEmpty ? _subjects.first['id'] : null;
    final lecNum = TextEditingController(text: '1');
    final fileTitle = TextEditingController();
    final fileType = TextEditingController(text: 'PDF');
    final fileUrl = TextEditingController();

    int? refSubjId = _subjects.isNotEmpty ? _subjects.first['id'] : null;
    final refTitleCtrl = TextEditingController();
    final refContentCtrl = TextEditingController();

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
          const Text('📁 إضافة ملف أو محاضرة لمادة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
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
          TextField(controller: fileTitle, decoration: const InputDecoration(labelText: 'عنوان الملف أو المحاضرة', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: fileType, decoration: const InputDecoration(labelText: 'النوع (PDF / AUDIO / VIDEO)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: fileUrl, decoration: const InputDecoration(labelText: 'رابط الملف المباشر (Drive / Telegram / URL)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () async {
              if (selectedSubjId == null || fileTitle.text.trim().isEmpty || fileUrl.text.trim().isEmpty) return;
              setState(() => _isLoading = true);
              try {
                await _client.from('materials').insert({
                  'subject_id': selectedSubjId,
                  'lecture_number': int.tryParse(lecNum.text) ?? 1,
                  'title': fileTitle.text.trim(),
                  'file_type': fileType.text.trim().toUpperCase(),
                  'file_url': fileUrl.text.trim(),
                });
                _showMsg('تم رفع رابط الملف بنجاح');
              } catch (_) {
                _showMsg('فشل حفظ الملف', isError: true);
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            child: const Text('حفظ الملف في المادة'),
          ),
          const Divider(height: 36),
          const Text('🎒 إضافة بطاقة مرجع سريع لمادة (حقيبة ليلة الامتحان)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
          const SizedBox(height: 6),
          const Text('تظهر مقسمة حسب كل مادة داخل حقيبة المراجعة ليلة الامتحان وتعمل بدون إنترنت.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 10),
          if (_subjects.isNotEmpty)
            DropdownButtonFormField<int>(
              value: refSubjId,
              decoration: const InputDecoration(labelText: 'المادة المرتبطة', border: OutlineInputBorder()),
              items: _subjects.map<DropdownMenuItem<int>>((s) => DropdownMenuItem(value: s['id'], child: Text(s['name']))).toList(),
              onChanged: (val) => setInnerState(() => refSubjId = val),
            ),
          const SizedBox(height: 8),
          TextField(controller: refTitleCtrl, decoration: const InputDecoration(labelText: 'عنوان البطاقة (مثلاً: تصنيف أدوية الضغط)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: refContentCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'المحتوى المختصر والقوانين أو الملاحظات', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FD1C5), foregroundColor: Colors.black),
            icon: const Icon(Icons.bookmark_add_rounded),
            label: const Text('حفظ البطاقة في مرجع المادة', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              if (refSubjId == null || refTitleCtrl.text.trim().isEmpty || refContentCtrl.text.trim().isEmpty) return;
              setState(() => _isLoading = true);
              try {
                await _client.from('subject_references').insert({
                  'subject_id': refSubjId,
                  'title': refTitleCtrl.text.trim(),
                  'content': refContentCtrl.text.trim(),
                });
                await _fetchInitialData();
                _showMsg('تمت إضافة بطاقة المرجع للمادة بنجاح ✓');
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
      ),
    );
  }

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

  Widget _buildScheduleAndAttendanceTab() {
    String selectedDay = 'السبت';
    final orderCtrl = TextEditingController(text: 'المحاضرة الأولى');
    final timeCtrl = TextEditingController(text: '08:00 - 10:00');
    final subjCtrl = TextEditingController();
    final hallCtrl = TextEditingController();
    final docCtrl = TextEditingController();

    final sessionCodes = <String>{'الكل', ..._attendance.map((e) => (e['session_code'] ?? '').toString()).where((e) => e.isNotEmpty)}.toList();
    String selectedSession = 'الكل';

    return StatefulBuilder(
      builder: (context, setInnerState) {
        final filteredAtt = selectedSession == 'الكل'
            ? _attendance
            : _attendance.where((a) => (a['session_code'] ?? '').toString() == selectedSession).toList();

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
                value: selectedSession,
                decoration: const InputDecoration(labelText: 'تصفية حسب كود الجلسة / المادة / المجموعة', border: OutlineInputBorder()),
                items: sessionCodes.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setInnerState(() => selectedSession = v ?? 'الكل'),
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
      },
    );
  }

  Widget _buildDevicesAndDirectoryTab() {
    final latestVerCtrl = TextEditingController(text: '1.3.0');
    final minVerCtrl = TextEditingController(text: '1.0.0');
    final updateUrlCtrl = TextEditingController(text: 'https://github.com/780ramialhakami780-jpg/IQ_Pharmacy39/releases/latest/download/IQ_Pharmacy39.apk');
    final releaseNotesCtrl = TextEditingController();

    final suppIdCtrl = TextEditingController();
    final suppNameCtrl = TextEditingController();
    final suppRoleCtrl = TextEditingController();

    final aboutTextCtrl = TextEditingController();
    final devNameCtrl = TextEditingController();
    final devWaCtrl = TextEditingController();
    final devTgCtrl = TextEditingController();

    final searchCtrl = TextEditingController();
    List<dynamic> foundStudents = [];

    final dirTitleCtrl = TextEditingController();
    final dirValueCtrl = TextEditingController();
    String dirType = 'رابط';

    return StatefulBuilder(
      builder: (context, setInnerState) => ListView(
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
                    final picker = ImagePicker();
                    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
                    if (picked == null) return;
                    setState(() => _isLoading = true);
                    try {
                      final bytes = await picked.readAsBytes();
                      final ext = picked.name.split('.').last;
                      final fileName = 'header_logo_${DateTime.now().millisecondsSinceEpoch}.$ext';
                      await _client.storage.from('announcements').uploadBinary(fileName, bytes);
                      final publicUrl = _client.storage.from('announcements').getPublicUrl(fileName);
                      await _client.from('app_settings').upsert({'key': 'header_logo_url', 'value': publicUrl});
                      _showMsg('تم تحديث شعار الترويسة بنجاح وسيظهر للجميع عند فتح التطبيق ✓');
                    } catch (_) {
                      _showMsg('تعذر رفع الشعار، تأكد من اتصال الإنترنت', isError: true);
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
                    _showMsg('تمت استعادة الشعار الافتراضي للتطبيق');
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
              Expanded(child: TextField(controller: latestVerCtrl, decoration: const InputDecoration(labelText: 'أحدث إصدار متاح', border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: minVerCtrl, decoration: const InputDecoration(labelText: 'الحد الأدنى الإجباري', border: OutlineInputBorder()))),
            ],
          ),
          const SizedBox(height: 8),
          TextField(controller: updateUrlCtrl, decoration: const InputDecoration(labelText: 'رابط تحميل التحديث (APK)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: releaseNotesCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'ملاحظات وما الجديد في هذا التحديث', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FD1C5), foregroundColor: Colors.black),
            icon: const Icon(Icons.system_update_rounded),
            label: const Text('حفظ إعدادات التحديث', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              setState(() => _isLoading = true);
              try {
                await _client.from('app_settings').upsert([
                  {'key': 'latest_version', 'value': latestVerCtrl.text.trim()},
                  {'key': 'min_version', 'value': minVerCtrl.text.trim()},
                  {'key': 'update_url', 'value': updateUrlCtrl.text.trim()},
                  {'key': 'update_notes', 'value': releaseNotesCtrl.text.trim()},
                ]);
                _showMsg('تم تحديث بيانات الإصدار بنجاح ✓');
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
          TextField(controller: suppIdCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'رقم قيد المطور / المندوب', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: suppNameCtrl, decoration: const InputDecoration(labelText: 'الاسم الظاهر للطلاب', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: suppRoleCtrl, decoration: const InputDecoration(labelText: 'الصفة (مثلاً: مطور التطبيق / مندوب الدفعة)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FD1C5), foregroundColor: Colors.black),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('إضافة لقائمة التواصل', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              if (suppIdCtrl.text.trim().isEmpty || suppNameCtrl.text.trim().isEmpty) return;
              setState(() => _isLoading = true);
              try {
                await _client.from('support_contacts').insert({
                  'student_id': suppIdCtrl.text.trim(),
                  'display_name': suppNameCtrl.text.trim(),
                  'role_title': suppRoleCtrl.text.trim().isEmpty ? 'فريق الدعم' : suppRoleCtrl.text.trim(),
                  'is_active': true,
                  'sort_order': _supportContacts.length + 1,
                });
                await _fetchInitialData();
                _showMsg('تمت الإضافة لقائمة الدعم والتواصل بنجاح');
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
          TextField(controller: aboutTextCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'نص النبذة التعريفية للتطبيق', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: devNameCtrl, decoration: const InputDecoration(labelText: 'اسم المطور / الفريق', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: devWaCtrl, decoration: const InputDecoration(labelText: 'رابط واتساب اختياري (https://wa.me/967...)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: devTgCtrl, decoration: const InputDecoration(labelText: 'رابط تيليجرام اختياري (https://t.me/...)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () async {
              setState(() => _isLoading = true);
              try {
                final payload = jsonEncode({
                  'about': aboutTextCtrl.text.trim(),
                  'developer': devNameCtrl.text.trim(),
                  'whatsapp': devWaCtrl.text.trim(),
                  'telegram': devTgCtrl.text.trim(),
                });
                await _client.from('app_settings').upsert({'key': 'about_app_info', 'value': payload});
                _showMsg('تم تحديث نبذة التطبيق بنجاح ✓');
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
                  controller: searchCtrl,
                  decoration: const InputDecoration(labelText: 'رقم القيد أو اسم الطالب', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FD1C5), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16)),
                onPressed: () async {
                  final q = searchCtrl.text.trim();
                  if (q.isEmpty) return;
                  try {
                    final res = await _client
                        .from('students')
                        .select()
                        .or('student_id.ilike.%$q%,full_name.ilike.%$q%')
                        .limit(10);
                    setInnerState(() => foundStudents = res);
                  } catch (_) {
                    _showMsg('تعذر البحث في قاعدة البيانات', isError: true);
                  }
                },
                child: const Text('بحث', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...foundStudents.map((st) {
            final sid = (st['student_id'] ?? '').toString().trim();
            final hasDevice = st['device_id'] != null && st['device_id'].toString().isNotEmpty;
            final isProtected = sid == _ownerId || st['is_admin'] == true;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(st['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(
                  'رقم القيد: $sid • ${isProtected ? 'حساب مشرف/مالك محمي' : (hasDevice ? 'مرتبط بهاتف' : 'غير مرتبط')}',
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
                                  () => setInnerState(() => st['device_id'] = null),
                                ),
                        child: const Text('فك القفل'),
                      ),
              ),
            );
          }),
          const Divider(height: 36),
          const Text('📇 إضافة عنصر لدليل المناديب والروابط', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
          const SizedBox(height: 10),
          TextField(controller: dirTitleCtrl, decoration: const InputDecoration(labelText: 'العنوان (مثلاً: مندوب مادة العقاقير / رابط القناة)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: dirValueCtrl, decoration: const InputDecoration(labelText: 'الرقم أو الرابط', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: dirType,
            decoration: const InputDecoration(labelText: 'النوع', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'رابط', child: Text('رابط إلكتروني')),
              DropdownMenuItem(value: 'تواصل', child: Text('رقم تواصل / مندوب')),
            ],
            onChanged: (v) => setInnerState(() => dirType = v ?? 'رابط'),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            icon: const Icon(Icons.add_link),
            label: const Text('إضافة إلى الدليل'),
            onPressed: () async {
              if (dirTitleCtrl.text.trim().isEmpty || dirValueCtrl.text.trim().isEmpty) return;
              setState(() => _isLoading = true);
              try {
                List<dynamic> currentList = [];
                final existing = await _client.from('app_settings').select('value').eq('key', 'batch_directory').maybeSingle();
                if (existing != null && existing['value'] != null && existing['value'].toString().isNotEmpty) {
                  currentList = jsonDecode(existing['value']);
                }
                currentList.add({
                  'title': dirTitleCtrl.text.trim(),
                  'value': dirValueCtrl.text.trim(),
                  'type': dirType,
                });
                await _client.from('app_settings').upsert({'key': 'batch_directory', 'value': jsonEncode(currentList)});
                _showMsg('تمت الإضافة إلى دليل الدفعة بنجاح');
              } catch (_) {
                _showMsg('فشلت الإضافة', isError: true);
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
          ),
        ],
      ),
    );
  }
}
