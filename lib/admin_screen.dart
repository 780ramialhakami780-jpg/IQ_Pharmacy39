import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // 4. تبويب الجدول + كشف الحضور عبر QR
  Widget _buildScheduleAndAttendanceTab() {
    String selectedDay = 'السبت';
    final orderCtrl = TextEditingController(text: 'المحاضرة الأولى');
    final timeCtrl = TextEditingController(text: '08:00 - 10:00');
    final subjCtrl = TextEditingController();
    final hallCtrl = TextEditingController();
    final docCtrl = TextEditingController();

    return StatefulBuilder(
      builder: (context, setInnerState) => ListView(
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
          const Text('✅ آخر الطلاب المسجلين حضورهم عبر QR', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
          const SizedBox(height: 8),
          if (_attendance.isEmpty)
            const Text('لا توجد سجلات حضور حديثة', style: TextStyle(color: Colors.grey))
          else
            ..._attendance.map((a) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text(a['full_name'] ?? ''),
                  subtitle: Text('رقم القيد: ${a['student_id']} • الكود: ${a['session_code']}'),
                )),
        ],
      ),
    );
  }

  // 5. تبويب تغيير الرمز السري للإدارة
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
