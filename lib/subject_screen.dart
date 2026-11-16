import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class SubjectScreen extends StatefulWidget {
  final Map<String, dynamic> subject;
  final Color defaultColor;

  const SubjectScreen({
    super.key,
    required this.subject,
    required this.defaultColor,
  });

  @override
  State<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends State<SubjectScreen> {
  int _tabIndex = 0;
  List<dynamic> _questions = [];
  List<dynamic> _materials = [];
  Set<int> _wrongQuestionIds = {};
  int _totalAnswered = 0;
  int _correctAnswered = 0;

  late String _customTitle;
  late Color _themeColor;
  bool _isLoading = true;

  int get _subjectId => widget.subject['id'];

  @override
  void initState() {
    super.initState();
    _customTitle = widget.subject['name'] ?? '';
    _themeColor = widget.defaultColor;
    _loadSubjectData();
  }

  Future<void> _loadSubjectData() async {
    final prefs = await SharedPreferences.getInstance();

    final savedTitle = prefs.getString('subj_title_$_subjectId');
    final savedColorVal = prefs.getInt('subj_color_$_subjectId');
    if (savedTitle != null && savedTitle.isNotEmpty) _customTitle = savedTitle;
    if (savedColorVal != null) _themeColor = Color(savedColorVal);

    final cachedQ = prefs.getString('cache_questions_$_subjectId');
    final cachedM = prefs.getString('cache_materials_$_subjectId');
    final wrongList = prefs.getStringList('wrong_q_$_subjectId') ?? [];

    setState(() {
      if (cachedQ != null) _questions = jsonDecode(cachedQ);
      if (cachedM != null) _materials = jsonDecode(cachedM);
      _wrongQuestionIds = wrongList.map((e) => int.tryParse(e) ?? -1).where((e) => e != -1).toSet();
      _totalAnswered = prefs.getInt('stats_total_$_subjectId') ?? 0;
      _correctAnswered = prefs.getInt('stats_correct_$_subjectId') ?? 0;
      _isLoading = false;
    });

    try {
      final client = Supabase.instance.client;
      final qData = await client.from('questions').select().eq('subject_id', _subjectId).order('id');
      final mData = await client.from('materials').select().eq('subject_id', _subjectId).order('lecture_number');

      await prefs.setString('cache_questions_$_subjectId', jsonEncode(qData));
      await prefs.setString('cache_materials_$_subjectId', jsonEncode(mData));

      if (!mounted) return;
      setState(() {
        _questions = qData;
        _materials = mData;
      });
    } catch (_) {}
  }

  Future<void> _recordAnswer(int questionId, bool isCorrect) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _totalAnswered++;
      if (isCorrect) {
        _correctAnswered++;
        _wrongQuestionIds.remove(questionId);
      } else {
        _wrongQuestionIds.add(questionId);
      }
    });
    await prefs.setInt('stats_total_$_subjectId', _totalAnswered);
    await prefs.setInt('stats_correct_$_subjectId', _correctAnswered);
    await prefs.setStringList('wrong_q_$_subjectId', _wrongQuestionIds.map((e) => e.toString()).toList());
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _buildQuestionsBankTab(),
      _buildMaterialsTab(),
      _buildWeakPointsTab(),
      _buildStatsTab(),
      _buildSubjectSettingsTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_customTitle),
        backgroundColor: _themeColor.withOpacity(0.25),
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : tabs[_tabIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (i) => setState(() => _tabIndex = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF181B20),
        selectedItemColor: _themeColor,
        unselectedItemColor: Colors.grey,
        selectedFontSize: 11,
        unselectedFontSize: 10,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.quiz_rounded), label: 'بنك الأسئلة'),
          BottomNavigationBarItem(icon: Icon(Icons.folder_copy_rounded), label: 'الملفات'),
          BottomNavigationBarItem(icon: Icon(Icons.warning_amber_rounded), label: 'نقاط الضعف'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded), label: 'الإحصائيات'),
          BottomNavigationBarItem(icon: Icon(Icons.tune_rounded), label: 'إعدادات المادة'),
        ],
      ),
    );
  }

  Widget _buildQuestionsBankTab() {
    if (_questions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('لا توجد أسئلة مضافة لهذه المادة حتى الآن.\nسيتم تحديثها تلقائياً فور إضافتها من الإدارة.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _questions.length,
      itemBuilder: (context, index) {
        final q = _questions[index];
        return _QuestionCard(
          index: index + 1,
          question: q,
          accentColor: _themeColor,
          onAnswered: (isCorrect) => _recordAnswer(q['id'], isCorrect),
        );
      },
    );
  }

  Widget _buildMaterialsTab() {
    if (_materials.isEmpty) {
      return const Center(
        child: Text('لا توجد ملفات أو محاضرات مرفوعة لهذه المادة حالياً.', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _materials.length,
      itemBuilder: (context, index) {
        final m = _materials[index];
        final type = (m['file_type'] ?? 'PDF').toString().toUpperCase();
        IconData icon = Icons.picture_as_pdf_rounded;
        if (type.contains('AUDIO') || type.contains('MP3')) icon = Icons.headphones_rounded;
        if (type.contains('VIDEO') || type.contains('LINK')) icon = Icons.play_circle_fill_rounded;

        return Card(
          color: const Color(0xFF181B20),
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _themeColor.withOpacity(0.2),
              child: Icon(icon, color: _themeColor),
            ),
            title: Text(m['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('المحاضرة ${m['lecture_number']}  •  النوع: $type', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            trailing: IconButton(
              icon: const Icon(Icons.download_rounded, color: Color(0xFF4FD1C5)),
              onPressed: () async {
                final url = Uri.tryParse(m['file_url'] ?? '');
                if (url != null) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildWeakPointsTab() {
    final weakQuestions = _questions.where((q) => _wrongQuestionIds.contains(q['id'])).toList();
    if (weakQuestions.isEmpty) {
      return const Center(
        child: Text('رائع! لا توجد لديك أسئلة خاطئة مسجلة في هذه المادة 🎉', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: weakQuestions.length,
      itemBuilder: (context, index) {
        final q = weakQuestions[index];
        return _QuestionCard(
          index: index + 1,
          question: q,
          accentColor: Colors.redAccent,
          onAnswered: (isCorrect) => _recordAnswer(q['id'], isCorrect),
        );
      },
    );
  }

  Widget _buildStatsTab() {
    final double accuracy = _totalAnswered == 0 ? 0 : (_correctAnswered / _totalAnswered) * 100;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF181B20),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _themeColor.withOpacity(0.4)),
            ),
            child: Column(
              children: [
                Text('${accuracy.toStringAsFixed(1)}%', style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: _themeColor)),
                const SizedBox(height: 6),
                const Text('نسبة الدقة في الإجابات', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _statBox('إجمالي المحاولات', '$_totalAnswered', Colors.blueAccent)),
              const SizedBox(width: 12),
              Expanded(child: _statBox('إجابات صحيحة', '$_correctAnswered', Colors.green)),
              const SizedBox(width: 12),
              Expanded(child: _statBox('نقاط الضعف', '${_wrongQuestionIds.length}', Colors.redAccent)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBox(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF181B20), borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Text(val, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildSubjectSettingsTab() {
    final nameCtrl = TextEditingController(text: _customTitle);
    final colors = [
      const Color(0xFFA95C68),
      const Color(0xFF2B6CB0),
      const Color(0xFF1E8449),
      const Color(0xFFB9770E),
      const Color(0xFF8E44AD),
      const Color(0xFF0D9488),
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('تخصيص اسم المادة على هاتفك', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF181B20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 20),
        const Text('اختيار لون واجهة المادة', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          children: colors.map((c) {
            return GestureDetector(
              onTap: () => setState(() => _themeColor = c),
              child: CircleAvatar(
                backgroundColor: c,
                radius: 20,
                child: _themeColor.value == c.value ? const Icon(Icons.check, color: Colors.white) : null,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('subj_title_$_subjectId', nameCtrl.text.trim());
            await prefs.setInt('subj_color_$_subjectId', _themeColor.value);
            setState(() => _customTitle = nameCtrl.text.trim());
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم حفظ تخصيص المادة بنجاح'), backgroundColor: Colors.teal),
              );
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: _themeColor, foregroundColor: Colors.white),
          child: const Text('حفظ التعديلات'),
        ),
      ],
    );
  }
}

class _QuestionCard extends StatefulWidget {
  final int index;
  final Map<String, dynamic> question;
  final Color accentColor;
  final Function(bool isCorrect) onAnswered;

  const _QuestionCard({
    required this.index,
    required this.question,
    required this.accentColor,
    required this.onAnswered,
  });

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final List<dynamic> options = widget.question['options'] is String
        ? jsonDecode(widget.question['options'])
        : (widget.question['options'] ?? []);
    final int correctIdx = widget.question['correct_index'] ?? 0;

    return Card(
      color: const Color(0xFF181B20),
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('سؤال ${widget.index}: ${widget.question['question_text'] ?? ''}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, height: 1.4)),
            const SizedBox(height: 12),
            ...List.generate(options.length, (i) {
              Color borderColor = Colors.white12;
              Color bgColor = Colors.transparent;
              if (_selectedIndex != null) {
                if (i == correctIdx) {
                  borderColor = Colors.green;
                  bgColor = Colors.green.withOpacity(0.15);
                } else if (i == _selectedIndex) {
                  borderColor = Colors.redAccent;
                  bgColor = Colors.redAccent.withOpacity(0.15);
                }
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: _selectedIndex != null
                      ? null
                      : () {
                          setState(() => _selectedIndex = i);
                          widget.onAnswered(i == correctIdx);
                        },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor),
                    ),
                    child: Text(options[i].toString(), style: const TextStyle(fontSize: 14)),
                  ),
                ),
              );
            }),
            if (_selectedIndex != null && (widget.question['explanation'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                child: Text('💡 التوضيح: ${widget.question['explanation']}', style: const TextStyle(fontSize: 12, color: Colors.amberAccent)),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
