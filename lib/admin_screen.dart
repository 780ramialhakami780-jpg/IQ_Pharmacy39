import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

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
  List<dynamic> _announcements = [];
  List<dynamic> _supportContacts = [];
  Map<String, String> _studentEmails = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    try {
      final subjs = await _client.from('subjects').select().order('sort_order');
      final att = await _client.from('attendance').select().order('created_at', ascending: false).limit(500);
      List<dynamic> anns = [];
      List<dynamic> supps = [];
      final Map<String, String> emailMap = {};

      try {
        anns = await _client.from('announcements').select().order('created_at', ascending: false);
      } catch (_) {}

      try {
        supps = await _client.from('support_contacts').select().order('sort_order');
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
        _subjects = subjs;
        _attendance = att;
        _announcements = anns;
        _supportContacts = supps;
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لوحة إدارة الدفعة السرية'),
          backgroundColor: const Color(0xFF1E293B),
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: Color(0xFF4FD1C5),
            tabs: [
              Tab(text: 'الإعلانات والتنبيهات'),
              Tab(text: 'المواد والملفات'),
              Tab(text: 'بنك الأسئلة'),
              Tab(text: 'الجدول وكشف الحضور'),
              Tab(text: 'الدعم والأجهزة والدليل'),
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
                  _buildDevicesAndDirectoryTab(),
                  _buildChangePinTab(),
                ],
              ),
      ),
    );
  }

  // 1. تبويب شريط الإعلانات المصوّرة + الشريط العاجل + الإشعارات + التكاليف
  Widget _buildNotificationsAndTasksTab() {
    final annTitleCtrl = TextEditingController();
    final annDescCtrl = TextEditingController();
    final annImgUrlCtrl = TextEditingController();
    final annActionUrlCtrl = TextEditingController();

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
        const Text('🖼️ نشر إعلان مصوّر في الشريط المتحرك (Carousel)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
        const SizedBox(height: 6),
        const Text('يظهر أعلى الواجهة الرئيسية مع إمكانية التكبير وزر "فتح الرابط" الاختياري.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 10),
        TextField(controller: annTitleCtrl, decoration: const InputDecoration(labelText: 'عنوان الإعلان (إلزامي)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: annDescCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'وصف تفصيلي يظهر عند تكبير الإعلان (اختياري)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: annImgUrlCtrl,
                decoration: const InputDecoration(labelText: 'رابط الصورة أو ارفعها من الاستوديو', border: OutlineInputBorder()),
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
          icon: const Icon(Icons.add_photo_alternate_rounded),
          label: const Text('نشر الإعلان في التطبيق', style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: () async {
            if (annTitleCtrl.text.trim().isEmpty || annImgUrlCtrl.text.trim().isEmpty) {
              _showMsg('يرجى إدخال عنوان الإعلان وصورته', isError: true);
              return;
            }
            setState(() => _isLoading = true);
            try {
              await _client.from('announcements').insert({
                'title': annTitleCtrl.text.trim(),
                'description': annDescCtrl.text.trim(),
                'image_url': annImgUrlCtrl.text.trim(),
                'action_url': annActionUrlCtrl.text.trim(),
                'is_active': true,
              });
              await _fetchInitialData();
              _showMsg('تم نشر الإعلان للدفعة بنجاح ✓');
            } catch (_) {
              _showMsg('فشل نشر الإعلان', isError: true);
            } finally {
              if (mounted) setState(() => _isLoading = false);
            }
          },
        ),
        if (_announcements.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('الإعلانات النشطة حالياً:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ..._announcements.map((a) => ListTile(
                dense: true,
                leading: const Icon(Icons.image_rounded, color: Color(0xFF4FD1C5)),
                title: Text(a['title'] ?? ''),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  onPressed: () async {
                    await _client.from('announcements').delete().eq('id', a['id']);
                    await _fetchInitialData();
                    _showMsg('تم حذف الإعلان');
                  },
                ),
              )),
        ],
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

  // 2. تبويب إضافة مادة + رفع رابط ملف/محاضرة
  Widget _buildSubjectsAndFilesTab() {
    final subjName = TextEditingController();
    final subjDesc = TextEditingController();

    int? selectedSubjId = _subjects.isNotEmpty ? _subjects.first['id'] : null;
    final lecNum = TextEditingController(text: '1');
    final fileTitle = TextEditingController();
    final fileType = TextEditingController(text: 'PDF');
    final fileUrl = TextEditingController();

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

  // 4. تبويب الجدول + تصدير كشوفات الحضور متضمنة البريد الجامعي للكلية
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
                decoration: const InputDecoration(labelText: 'تصفية حسب كود الجلسة / المادة', border: OutlineInputBorder()),
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

  // 5. تبويب إدارة المطورين/المناديب للتواصل + نبذة التطبيق + فك الأجهزة + الدليل
  Widget _buildDevicesAndDirectoryTab() {
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
          const Text('💬 إدارة قائمة المطورين والمناديب (للمحادثة الخاصة)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
          const SizedBox(height: 6),
          const Text('أضف رقم قيد المطور أو المندوب ليظهر للطلاب في زر "الدعم والتواصل" للمراسلة داخل التطبيق.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 10),
          TextField(controller: suppIdCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'رقم قيد المطور / المندوب (لربط المحادثة بحسابه)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: suppNameCtrl, decoration: const InputDecoration(labelText: 'الاسم الظاهر للطلاب (مثلاً: د. رامي الحكمي)', border: OutlineInputBorder())),
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
          const Text('📱 فك ارتباط هاتف طالب (تصفير device_id)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5))),
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
            final hasDevice = st['device_id'] != null && st['device_id'].toString().isNotEmpty;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(st['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text('رقم القيد: ${st['student_id']} • ${hasDevice ? 'مرتبط بهاتف' : 'غير مرتبط'}'),
                trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: hasDevice ? Colors.orange : Colors.grey, foregroundColor: Colors.black),
                  onPressed: !hasDevice
                      ? null
                      : () async {
                          try {
                            await _client.from('students').update({'device_id': null}).eq('student_id', st['student_id']);
                            setInnerState(() => st['device_id'] = null);
                            _showMsg('تم فك ارتباط الجهاز بنجاح، يمكن للطالب الدخول من هاتفه الجديد الآن');
                          } catch (_) {
                            _showMsg('فشل فك الارتباط', isError: true);
                          }
                        },
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

  // 6. تبويب تغيير الرمز السري للإدارة
  Widget _buildChangePinTab() {
    final pinCtrl = TextEditingController();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text('تغيير الرمز السري العام للوحة الإدارة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('سيتم تحديث الرمز تلقائياً عند جميع المشرفين في الدفعة.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          TextField(
            controller: pinCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'الرمز السري الجديد (أرقام)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FD1C5), foregroundColor: Colors.black),
              onPressed: () async {
                final newPin = pinCtrl.text.trim();
                if (newPin.length < 4) return;
                await Supabase.instance.client
                    .from('app_settings')
                    .upsert({'key': 'admin_pin', 'value': newPin});
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('admin_pin', newPin);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم تحديث الرمز السري العام لجميع المشرفين بنجاح'), backgroundColor: Colors.teal),
                );
              },
              child: const Text('حفظ الرمز الجديد للجميع', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
