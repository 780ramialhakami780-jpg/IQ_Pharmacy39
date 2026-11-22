import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

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
  Set<int> _completedMaterialIds = {};
  Set<int> _favQuestionIds = {};
  Set<int> _favMaterialIds = {};
  Map<int, String> _downloadedFiles = {};
  Set<int> _downloadingIds = {};

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
    final completedList = prefs.getStringList('completed_mat_$_subjectId') ?? [];
    final favQList = prefs.getStringList('fav_q_$_subjectId') ?? [];
    final favMList = prefs.getStringList('fav_m_$_subjectId') ?? [];

    setState(() {
      if (cachedQ != null) _questions = jsonDecode(cachedQ);
      if (cachedM != null) _materials = jsonDecode(cachedM);
      _wrongQuestionIds = wrongList.map((e) => int.tryParse(e) ?? -1).where((e) => e != -1).toSet();
      _completedMaterialIds = completedList.map((e) => int.tryParse(e) ?? -1).where((e) => e != -1).toSet();
      _favQuestionIds = favQList.map((e) => int.tryParse(e) ?? -1).where((e) => e != -1).toSet();
      _favMaterialIds = favMList.map((e) => int.tryParse(e) ?? -1).where((e) => e != -1).toSet();
      _totalAnswered = prefs.getInt('stats_total_$_subjectId') ?? 0;
      _correctAnswered = prefs.getInt('stats_correct_$_subjectId') ?? 0;
      _isLoading = false;
    });

    await _checkDownloadedFiles();

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
      await _checkDownloadedFiles();
    } catch (_) {}
  }

  Future<void> _toggleMaterialCompleted(int matId) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_completedMaterialIds.contains(matId)) {
        _completedMaterialIds.remove(matId);
      } else {
        _completedMaterialIds.add(matId);
      }
    });
    await prefs.setStringList(
      'completed_mat_$_subjectId',
      _completedMaterialIds.map((e) => e.toString()).toList(),
    );
  }

  Future<void> _toggleMaterialFavorite(int matId) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favMaterialIds.contains(matId)) {
        _favMaterialIds.remove(matId);
      } else {
        _favMaterialIds.add(matId);
      }
    });
    await prefs.setStringList(
      'fav_m_$_subjectId',
      _favMaterialIds.map((e) => e.toString()).toList(),
    );
  }

  Future<void> _toggleQuestionFavorite(int qId) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favQuestionIds.contains(qId)) {
        _favQuestionIds.remove(qId);
      } else {
        _favQuestionIds.add(qId);
      }
    });
    await prefs.setStringList(
      'fav_q_$_subjectId',
      _favQuestionIds.map((e) => e.toString()).toList(),
    );
  }

  Future<void> _checkDownloadedFiles() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final Map<int, String> found = {};
      for (var m in _materials) {
        final id = m['id'];
        final path = '${dir.path}/iq_mat_$id.pdf';
        if (await File(path).exists()) {
          found[id] = path;
        }
      }
      if (mounted) {
        setState(() => _downloadedFiles = found);
      }
    } catch (_) {}
  }

  Future<void> _handleMaterialTap(Map<String, dynamic> m) async {
    final int id = m['id'];
    final String type = (m['file_type'] ?? 'PDF').toString().toUpperCase();
    final String rawUrl = (m['file_url'] ?? '').toString().trim();

    if (rawUrl.isEmpty) return;

    if (type.contains('VIDEO') || type.contains('AUDIO') || kIsWeb) {
      final uri = Uri.tryParse(rawUrl);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    if (_downloadedFiles.containsKey(id)) {
      await OpenFilex.open(_downloadedFiles[id]!);
      return;
    }

    if (_downloadingIds.contains(id)) return;
    setState(() => _downloadingIds.add(id));

    try {
      final dir = await getApplicationDocumentsDirectory();
      final savePath = '${dir.path}/iq_mat_$id.pdf';
      await Dio().download(rawUrl, savePath);

      if (!mounted) return;
      setState(() {
        _downloadingIds.remove(id);
        _downloadedFiles[id] = savePath;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الملف في جهازك (يعمل الآن بدون إنترنت)'), backgroundColor: Colors.teal),
      );
      await OpenFilex.open(savePath);
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloadingIds.remove(id));
      final uri = Uri.tryParse(rawUrl);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحميل الملف، تأكد من اتصال الإنترنت'), backgroundColor: Colors.red),
        );
      }
    }
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
        final int qId = q['id'];
        return _QuestionCard(
          index: index + 1,
          question: q,
          accentColor: _themeColor,
          isFavorite: _favQuestionIds.contains(qId),
          onToggleFavorite: () => _toggleQuestionFavorite(qId),
          onAnswered: (isCorrect) => _recordAnswer(qId, isCorrect),
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

    final int completedCount = _materials.where((m) => _completedMaterialIds.contains(m['id'])).length;
    final double progress = _materials.isEmpty ? 0.0 : completedCount / _materials.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF181B20),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _themeColor.withOpacity(0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('نسبة إنجاز مذاكرة المادة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(
                    '${(progress * 100).round()}% ($completedCount/${_materials.length})',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _themeColor),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.white12,
                  color: _themeColor,
                ),
              ),
            ],
          ),
        ),
        ...List.generate(_materials.length, (index) {
          final m = _materials[index];
          final int id = m['id'];
          final type = (m['file_type'] ?? 'PDF').toString().toUpperCase();
          final bool isPdf = !type.contains('AUDIO') && !type.contains('VIDEO');
          final bool isSavedOffline = _downloadedFiles.containsKey(id);
          final bool isDownloading = _downloadingIds.contains(id);
          final bool isDone = _completedMaterialIds.contains(id);
          final bool isFav = _favMaterialIds.contains(id);

          IconData icon = Icons.picture_as_pdf_rounded;
          if (type.contains('AUDIO')) icon = Icons.headphones_rounded;
          if (type.contains('VIDEO')) icon = Icons.play_circle_fill_rounded;

          return Card(
            color: const Color(0xFF181B20),
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              onTap: () => _handleMaterialTap(m),
              leading: CircleAvatar(
                backgroundColor: _themeColor.withOpacity(0.2),
                child: Icon(icon, color: _themeColor),
              ),
              title: Text(
                m['title'] ?? '',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  decoration: isDone ? TextDecoration.lineThrough : null,
                  color: isDone ? Colors.grey : null,
                ),
              ),
              subtitle: Text(
                isPdf
                    ? 'المحاضرة ${m['lecture_number']}  •  ${isSavedOffline ? "محفوظ أوفلاين ✅" : "PDF (اضغط للتحميل)"}'
                    : 'المحاضرة ${m['lecture_number']}  •  رابط $type خارجي',
                style: TextStyle(fontSize: 12, color: isSavedOffline ? Colors.greenAccent : Colors.grey),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'مفضلة ليلة الامتحان',
                    icon: Icon(
                      isFav ? Icons.star_rounded : Icons.star_border_rounded,
                      color: isFav ? Colors.amber : Colors.grey,
                      size: 22,
                    ),
                    onPressed: () => _toggleMaterialFavorite(id),
                  ),
                  IconButton(
                    tooltip: 'تمت المذاكرة',
                    icon: Icon(
                      isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: isDone ? Colors.greenAccent : Colors.grey,
                      size: 22,
                    ),
                    onPressed: () => _toggleMaterialCompleted(id),
                  ),
                  if (isDownloading)
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Icon(
                      isPdf
                          ? (isSavedOffline ? Icons.offline_pin_rounded : Icons.download_rounded)
                          : Icons.open_in_new_rounded,
                      color: isSavedOffline ? Colors.greenAccent : const Color(0xFF4FD1C5),
                      size: 20,
                    ),
                ],
              ),
            ),
          );
        }),
      ],
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
        final int qId = q['id'];
        return _QuestionCard(
          index: index + 1,
          question: q,
          accentColor: Colors.redAccent,
          isFavorite: _favQuestionIds.contains(qId),
          onToggleFavorite: () => _toggleQuestionFavorite(qId),
          onAnswered: (isCorrect) => _recordAnswer(qId, isCorrect),
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
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final Function(bool isCorrect) onAnswered;

  const _QuestionCard({
    required this.index,
    required this.question,
    required this.accentColor,
    required this.isFavorite,
    required this.onToggleFavorite,
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'سؤال ${widget.index}: ${widget.question['question_text'] ?? ''}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, height: 1.4),
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'إضافة لحقيبة ليلة الامتحان',
                  icon: Icon(
                    widget.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                    color: widget.isFavorite ? Colors.amber : Colors.grey,
                  ),
                  onPressed: widget.onToggleFavorite,
                ),
              ],
            ),
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
