import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'app_prefs.dart';

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

class _SubjectScreenState extends State<SubjectScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<dynamic> _questions = [];
  List<dynamic> _materials = [];

  /// بيانات تقدم كل سؤال: { "qId": { "streak": int, "wrong": int, "box": int, "nextReview": int, "note": String } }
  Map<String, Map<String, dynamic>> _qProgress = {};

  Set<int> _completedMaterialIds = {};
  Set<int> _favQuestionIds = {};
  Set<int> _favMaterialIds = {};
  Map<int, String> _downloadedFiles = {};
  Set<int> _downloadingIds = {};

  int _totalAnswered = 0;
  int _correctAnswered = 0;

  // إعدادات المادة الشخصية
  late String _customTitle;
  late Color _themeColor;
  int _dailyGoal = 20;
  String? _examDateIso;
  bool _shuffleOptions = false;
  bool _recallBeforeOptions = false;

  // فلاتر بنك الأسئلة
  final TextEditingController _qSearchCtrl = TextEditingController();
  String _qSearchQuery = '';
  String _qStatusFilter = 'all'; // all, new, correct, mastered, weak, critical, fav, noted
  int? _qLectureFilter; // null = كل المواضيع

  // فلاتر الملفات
  final TextEditingController _mSearchCtrl = TextEditingController();
  String _mSearchQuery = '';
  String _mTypeFilter = 'all'; // all, lecture, summary, audio, video, other

  bool _isLoading = true;

  int get _subjectId => widget.subject['id'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _customTitle = widget.subject['name'] ?? '';
    _themeColor = widget.defaultColor;
    _loadSubjectData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _qSearchCtrl.dispose();
    _mSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSubjectData() async {
    final prefs = await SharedPreferences.getInstance();

    final savedTitle = prefs.getString('subj_title_$_subjectId');
    final savedColorVal = prefs.getInt('subj_color_$_subjectId');
    if (savedTitle != null && savedTitle.isNotEmpty) _customTitle = savedTitle;
    if (savedColorVal != null) _themeColor = Color(savedColorVal);

    _dailyGoal = prefs.getInt('subj_goal_$_subjectId') ?? 20;
    _examDateIso = prefs.getString('subj_exam_$_subjectId');
    _shuffleOptions = prefs.getBool('subj_shuffle_$_subjectId') ?? false;
    _recallBeforeOptions = prefs.getBool('subj_recall_$_subjectId') ?? false;

    final cachedQ = prefs.getString('cache_questions_$_subjectId');
    final cachedM = prefs.getString('cache_materials_$_subjectId');
    final wrongList = prefs.getStringList('wrong_q_$_subjectId') ?? [];
    final completedList = prefs.getStringList('completed_mat_$_subjectId') ?? [];
    final favQList = prefs.getStringList('fav_q_$_subjectId') ?? [];
    final favMList = prefs.getStringList('fav_m_$_subjectId') ?? [];

    Map<String, Map<String, dynamic>> loadedMeta = {};
    final rawMeta = prefs.getString('q_meta_$_subjectId');
    if (rawMeta != null && rawMeta.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawMeta) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          if (v is Map) loadedMeta[k] = Map<String, dynamic>.from(v);
        });
      } catch (_) {}
    }

    // ترحيل الأسئلة الخاطئة القديمة تلقائياً إلى النظام الجديد
    for (final wId in wrongList) {
      if (!loadedMeta.containsKey(wId)) {
        loadedMeta[wId] = {'streak': 0, 'wrong': 1, 'box': 0, 'nextReview': 0, 'note': ''};
      }
    }

    setState(() {
      if (cachedQ != null) _questions = jsonDecode(cachedQ);
      if (cachedM != null) _materials = jsonDecode(cachedM);
      _qProgress = loadedMeta;
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

  Future<void> _saveQuestionMeta() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('q_meta_$_subjectId', jsonEncode(_qProgress));
    final weakIds = _questions
        .where((q) => _getQuestionState(q['id']) == 'weak' || _getQuestionState(q['id']) == 'critical')
        .map((q) => q['id'].toString())
        .toList();
    await prefs.setStringList('wrong_q_$_subjectId', weakIds);
  }

  /// تحديد حالة السؤال من 6 حالات: new, correct, mastered, weak, critical
  String _getQuestionState(int qId) {
    final meta = _qProgress['$qId'];
    if (meta == null) return 'new';
    final int streak = (meta['streak'] ?? 0) as int;
    final int wrong = (meta['wrong'] ?? 0) as int;
    final bool lastWasWrong = meta['lastWrong'] == true;

    if (streak >= 3) return 'mastered';
    if (lastWasWrong || (streak == 0 && wrong > 0)) {
      return wrong >= 3 ? 'critical' : 'weak';
    }
    if (streak >= 1) return 'correct';
    return 'new';
  }

  int _getQuestionWrongCount(int qId) => (_qProgress['$qId']?['wrong'] ?? 0) as int;
  String _getQuestionNote(int qId) => (_qProgress['$qId']?['note'] ?? '').toString();
  int _getQuestionBox(int qId) => (_qProgress['$qId']?['box'] ?? 0) as int;

  bool _isQuestionDueForReview(int qId) {
    final meta = _qProgress['$qId'];
    if (meta == null) return false;
    final int nextRev = (meta['nextReview'] ?? 0) as int;
    final int streak = (meta['streak'] ?? 0) as int;
    if (streak >= 3) return false;
    return nextRev > 0 && DateTime.now().millisecondsSinceEpoch >= nextRev;
  }

  Future<void> _recordAnswer(int questionId, bool isCorrect) async {
    if (AppPrefs.quizHaptics) {
      if (isCorrect) {
        HapticFeedback.lightImpact();
      } else {
        HapticFeedback.mediumImpact();
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final key = '$questionId';
    final current = Map<String, dynamic>.from(
      _qProgress[key] ?? {'streak': 0, 'wrong': 0, 'box': 0, 'nextReview': 0, 'note': ''},
    );

    const boxIntervalsDays = [0, 3, 7, 14, 30, 60];

    setState(() {
      _totalAnswered++;
      if (isCorrect) {
        _correctAnswered++;
        final newStreak = ((current['streak'] ?? 0) as int) + 1;
        final newBox = min(5, ((current['box'] ?? 0) as int) + 1);
        final nextMs = DateTime.now().add(Duration(days: boxIntervalsDays[newBox])).millisecondsSinceEpoch;
        current['streak'] = newStreak;
        current['box'] = newBox;
        current['nextReview'] = nextMs;
        current['lastWrong'] = false;
      } else {
        current['streak'] = 0;
        current['wrong'] = ((current['wrong'] ?? 0) as int) + 1;
        current['box'] = 0;
        current['nextReview'] = DateTime.now().millisecondsSinceEpoch;
        current['lastWrong'] = true;
      }
      _qProgress[key] = current;
    });

    await prefs.setInt('stats_total_$_subjectId', _totalAnswered);
    await prefs.setInt('stats_correct_$_subjectId', _correctAnswered);
    await _saveQuestionMeta();
  }

  Future<void> _updateQuestionNote(int qId, String noteText) async {
    final key = '$qId';
    final current = Map<String, dynamic>.from(
      _qProgress[key] ?? {'streak': 0, 'wrong': 0, 'box': 0, 'nextReview': 0, 'note': ''},
    );
    current['note'] = noteText.trim();
    setState(() => _qProgress[key] = current);
    await _saveQuestionMeta();
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
        SnackBar(
          content: Text(AppPrefs.tr('تم حفظ الملف في جهازك (يعمل الآن بدون إنترنت) ✅', 'Saved offline ✅')),
          backgroundColor: Colors.teal,
        ),
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
          SnackBar(
            content: Text(AppPrefs.tr('تعذر تحميل الملف، تأكد من اتصال الإنترنت', 'Download failed, check internet')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteOfflineMaterial(int matId) async {
    if (kIsWeb) return;
    try {
      final path = _downloadedFiles[matId];
      if (path != null && await File(path).exists()) {
        await File(path).delete();
      }
      if (mounted) {
        setState(() => _downloadedFiles.remove(matId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppPrefs.tr('تم حذف النسخة المحفوظة', 'Offline copy deleted'))),
        );
      }
    } catch (_) {}
  }

  void _shareQuestionText(Map<String, dynamic> q, int displayNum) {
    final List<dynamic> options = q['options'] is String ? jsonDecode(q['options']) : (q['options'] ?? []);
    final int cIdx = q['correct_index'] ?? 0;
    final correctText = (cIdx >= 0 && cIdx < options.length) ? options[cIdx].toString() : '';
    final exp = (q['explanation'] ?? '').toString().trim();

    final buf = StringBuffer()
      ..writeln('📚 $_customTitle — سؤال #$displayNum')
      ..writeln(q['question_text'] ?? '')
      ..writeln('');
    for (int i = 0; i < options.length; i++) {
      buf.writeln('${i + 1}) ${options[i]}');
    }
    buf.writeln('\n✅ الإجابة الصحيحة: $correctText');
    if (exp.isNotEmpty) buf.writeln('💡 التوضيح: $exp');
    buf.writeln('\n— تطبيق IQ_Pharmacy39');

    Share.share(buf.toString());
  }

  void _openQuestionNoteDialog(Map<String, dynamic> q) {
    final int qId = q['id'];
    final ctrl = TextEditingController(text: _getQuestionNote(qId));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppPrefs.tr('ملاحظتي على السؤال', 'My Question Note')),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: AppPrefs.tr('اكتب تلميحاً أو قاعدة تساعدك في تذكر الإجابة...', 'Write a hint or memory note...'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          if (_getQuestionNote(qId).isNotEmpty)
            TextButton(
              onPressed: () async {
                await _updateQuestionNote(qId, '');
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(AppPrefs.tr('حذف', 'Delete'), style: const TextStyle(color: Colors.redAccent)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppPrefs.tr('إلغاء', 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _themeColor, foregroundColor: Colors.white),
            onPressed: () async {
              await _updateQuestionNote(qId, ctrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(AppPrefs.tr('حفظ', 'Save')),
          ),
        ],
      ),
    );
  }

  void _openReportQuestionDialog(Map<String, dynamic> q) {
    final ctrl = TextEditingController();
    bool sending = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(AppPrefs.tr('تبليغ عن خطأ في السؤال', 'Report Question Issue')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppPrefs.tr(
                  'أخبر مناديب الدفعة إذا كان هناك خطأ مطبعي أو في الإجابة المعتمدة:',
                  'Let batch admins know if there is a typo or wrong answer:',
                ),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: AppPrefs.tr('اكتب تفاصيل الملاحظة هنا...', 'Describe the issue...'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(ctx),
              child: Text(AppPrefs.tr('إلغاء', 'Cancel')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _themeColor, foregroundColor: Colors.white),
              onPressed: sending
                  ? null
                  : () async {
                      final note = ctrl.text.trim();
                      if (note.isEmpty) return;
                      setDialogState(() => sending = true);
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        final stName = prefs.getString('full_name') ?? 'طالب';
                        await Supabase.instance.client.from('notifications').insert({
                          'title': 'تنبيه خطأ سؤال — $_customTitle (#${q['id']})',
                          'body': 'السؤال: ${q['question_text']}\nالملاحظة: $note',
                          'sender_name': stName,
                        });
                      } catch (_) {}
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(AppPrefs.tr('تم إرسال التنبيه للمندوبين بنجاح ✓', 'Issue reported to admins ✓')),
                            backgroundColor: Colors.teal,
                          ),
                        );
                      }
                    },
              child: sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(AppPrefs.tr('إرسال', 'Send')),
            ),
          ],
        ),
      ),
    );
  }

  /// إطلاق تحدي اليوم الذكي (10 أسئلة: الضعيفة أولاً ثم المستحقة ثم الجديدة)
  void _startDailyChallenge() {
    if (_questions.isEmpty) return;
    final weak = _questions.where((q) => _getQuestionState(q['id']) == 'critical' || _getQuestionState(q['id']) == 'weak').toList()..shuffle();
    final due = _questions.where((q) => _isQuestionDueForReview(q['id']) && !weak.contains(q)).toList()..shuffle();
    final fresh = _questions.where((q) => _getQuestionState(q['id']) == 'new').toList()..shuffle();
    final rest = _questions.where((q) => !weak.contains(q) && !due.contains(q) && !fresh.contains(q)).toList()..shuffle();

    final picked = <dynamic>[...weak, ...due, ...fresh, ...rest].take(10).toList();
    _launchPracticeSession(
      title: AppPrefs.tr('تحدي اليوم (10 أسئلة)', 'Daily Challenge (10 Qs)'),
      sessionQuestions: picked,
      requeueWrong: true,
    );
  }

  /// فتح نافذة إعداد جلسة التدريب التفاعلي أو البطاقات أو الحفظ
  void _openSessionLauncher({required String mode}) {
    if (_questions.isEmpty) return;
    bool shuffle = false;

    final newQs = _questions.where((q) => _getQuestionState(q['id']) == 'new').toList();
    final weakQs = _questions.where((q) => _getQuestionState(q['id']) == 'weak' || _getQuestionState(q['id']) == 'critical').toList();
    final favQs = _questions.where((q) => _favQuestionIds.contains(q['id'])).toList();

    final int groupSize = 50;
    final int groupCount = (_questions.length / groupSize).ceil();

    final Set<int> lectureNums = {};
    for (final q in _questions) {
      final ln = int.tryParse('${q['lecture_number'] ?? 0}') ?? 0;
      if (ln > 0) lectureNums.add(ln);
    }
    final sortedLectures = lectureNums.toList()..sort();

    final modeTitle = mode == 'practice'
        ? AppPrefs.tr('التدريب التفاعلي', 'Interactive Practice')
        : mode == 'flashcards'
            ? AppPrefs.tr('البطاقات السريعة', 'Flashcards')
            : AppPrefs.tr('وضع الحفظ والمراجعة', 'Study & Quick Review');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          void runWithList(String label, List<dynamic> rawList) {
            if (rawList.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppPrefs.tr('لا توجد أسئلة في هذا القسم حالياً', 'No questions in this category'))),
              );
              return;
            }
            final list = List<dynamic>.from(rawList);
            if (shuffle) list.shuffle();
            Navigator.pop(ctx);

            if (mode == 'practice') {
              _launchPracticeSession(title: label, sessionQuestions: list, requeueWrong: true);
            } else if (mode == 'flashcards') {
              _launchFlashcardsSession(title: label, sessionQuestions: list);
            } else {
              _launchStudyCardsSession(title: label, sessionQuestions: list);
            }
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.72,
            maxChildSize: 0.9,
            minChildSize: 0.45,
            expand: false,
            builder: (_, scrollCtrl) => ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                Text(modeTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _themeColor)),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(AppPrefs.tr('ترتيب الأسئلة عشوائياً', 'Shuffle Questions'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(AppPrefs.tr('تعطيله يعرض الأسئلة بالترتيب المتسلسل', 'Off shows questions in order'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  value: shuffle,
                  activeColor: _themeColor,
                  onChanged: (v) => setSheetState(() => shuffle = v),
                ),
                const Divider(height: 20),
                _launcherOptionTile(
                  title: AppPrefs.tr('كل الأسئلة', 'All Questions'),
                  count: _questions.length,
                  icon: Icons.all_inclusive_rounded,
                  onTap: () => runWithList(AppPrefs.tr('كل الأسئلة', 'All Questions'), _questions),
                ),
                _launcherOptionTile(
                  title: AppPrefs.tr('الأسئلة الجديدة فقط', 'New Questions Only'),
                  count: newQs.length,
                  icon: Icons.fiber_new_rounded,
                  onTap: () => runWithList(AppPrefs.tr('الأسئلة الجديدة', 'New Questions'), newQs),
                ),
                _launcherOptionTile(
                  title: AppPrefs.tr('الأسئلة الضعيفة والأخطاء', 'Weak & Missed Questions'),
                  count: weakQs.length,
                  icon: Icons.warning_amber_rounded,
                  color: Colors.redAccent,
                  onTap: () => runWithList(AppPrefs.tr('مراجعة الأخطاء', 'Weak Questions'), weakQs),
                ),
                _launcherOptionTile(
                  title: AppPrefs.tr('الأسئلة المفضلة ⭐', 'Starred Questions ⭐'),
                  count: favQs.length,
                  icon: Icons.star_rounded,
                  color: Colors.amber,
                  onTap: () => runWithList(AppPrefs.tr('المفضلة', 'Favorites'), favQs),
                ),
                if (groupCount > 1) ...[
                  const SizedBox(height: 14),
                  Text(AppPrefs.tr('أو اختر مجموعة (كل 50 سؤالاً):', 'Or pick a 50-question group:'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(groupCount, (gIdx) {
                      final start = gIdx * groupSize;
                      final end = min(start + groupSize, _questions.length);
                      final slice = _questions.sublist(start, end);
                      return ActionChip(
                        backgroundColor: _themeColor.withOpacity(0.14),
                        label: Text('${AppPrefs.tr('مجموعة', 'Group')} ${gIdx + 1} (${start + 1}-$end)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        onPressed: () => runWithList('${AppPrefs.tr('المجموعة', 'Group')} ${gIdx + 1}', slice),
                      );
                    }),
                  ),
                ],
                if (sortedLectures.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(AppPrefs.tr('أو اختر حسب المحاضرة:', 'Or pick by lecture:'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  ...sortedLectures.map((ln) {
                    final lecQs = _questions.where((q) => (int.tryParse('${q['lecture_number'] ?? 0}') ?? 0) == ln).toList();
                    return _launcherOptionTile(
                      title: '${AppPrefs.tr('المحاضرة', 'Lecture')} $ln',
                      count: lecQs.length,
                      icon: Icons.menu_book_rounded,
                      onTap: () => runWithList('${AppPrefs.tr('المحاضرة', 'Lecture')} $ln', lecQs),
                    );
                  }),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _launcherOptionTile({
    required String title,
    required int count,
    required IconData icon,
    Color? color,
    required VoidCallback onTap,
  }) {
    final c = color ?? _themeColor;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: c, size: 22),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
          child: Text('$count', style: TextStyle(fontWeight: FontWeight.bold, color: c, fontSize: 12)),
        ),
        onTap: onTap,
      ),
    );
  }

  /// نافذة إعداد الاختبار المحاكي (Mock Exam)
  void _openMockExamSetup() {
    if (_questions.isEmpty) return;
    int selectedCount = min(30, _questions.length);
    final optionsCounts = [10, 20, 30, 50, 70].where((c) => c <= _questions.length).toList();
    if (!optionsCounts.contains(_questions.length)) optionsCounts.add(_questions.length);
    if (!optionsCounts.contains(selectedCount)) selectedCount = optionsCounts.first;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.timer_outlined, color: _themeColor),
              const SizedBox(width: 8),
              Text(AppPrefs.tr('إعداد الاختبار المحاكي', 'Mock Exam Setup'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppPrefs.tr(
                  'يُخفي الاختبار الإجابات حتى تسليم الورقة، ويمنحك دقيقة واحدة لكل سؤال ثم يعرض درجتك ومراجعة الأخطاء.',
                  'Answers stay hidden until submission with 1 minute per question.',
                ),
                style: const TextStyle(fontSize: 12.5, color: Colors.grey, height: 1.5),
              ),
              const SizedBox(height: 16),
              Text(AppPrefs.tr('اختر عدد أسئلة الاختبار:', 'Select number of questions:'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: optionsCounts.map((cnt) {
                  final active = cnt == selectedCount;
                  return ChoiceChip(
                    label: Text('$cnt ${AppPrefs.tr('سؤال', 'Qs')}'),
                    selected: active,
                    selectedColor: _themeColor,
                    labelStyle: TextStyle(color: active ? Colors.black : null, fontWeight: FontWeight.bold),
                    onSelected: (_) => setDialogState(() => selectedCount = cnt),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Text(
                '⏱️ ${AppPrefs.tr('المدة الزمنية:', 'Duration:')} $selectedCount ${AppPrefs.tr('دقيقة', 'minutes')}',
                style: TextStyle(color: _themeColor, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppPrefs.tr('إلغاء', 'Cancel'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _themeColor, foregroundColor: Colors.black),
              onPressed: () {
                final pool = List<dynamic>.from(_questions)..shuffle();
                final picked = pool.take(selectedCount).toList();
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _MockExamScreen(
                      subjectName: _customTitle,
                      accentColor: _themeColor,
                      questions: picked,
                      durationMinutes: selectedCount,
                      onRecordAnswer: _recordAnswer,
                    ),
                  ),
                );
              },
              child: Text(AppPrefs.tr('ابدأ الاختبار الآن', 'Start Exam'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _launchPracticeSession({
    required String title,
    required List<dynamic> sessionQuestions,
    bool requeueWrong = true,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _InteractivePracticeScreen(
          title: title,
          subjectName: _customTitle,
          accentColor: _themeColor,
          initialQuestions: sessionQuestions,
          shuffleOptions: _shuffleOptions,
          recallBeforeOptions: _recallBeforeOptions,
          requeueWrong: requeueWrong,
          isFavorite: (qId) => _favQuestionIds.contains(qId),
          getNote: _getQuestionNote,
          onToggleFavorite: _toggleQuestionFavorite,
          onSaveNote: _updateQuestionNote,
          onAnswered: _recordAnswer,
          onShareQuestion: _shareQuestionText,
          onReportQuestion: _openReportQuestionDialog,
        ),
      ),
    );
  }

  void _launchFlashcardsSession({
    required String title,
    required List<dynamic> sessionQuestions,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FlashcardsSessionScreen(
          title: title,
          subjectName: _customTitle,
          accentColor: _themeColor,
          questions: sessionQuestions,
          isFavorite: (qId) => _favQuestionIds.contains(qId),
          onToggleFavorite: _toggleQuestionFavorite,
          onRateCard: _recordAnswer,
          onShareQuestion: _shareQuestionText,
        ),
      ),
    );
  }

  void _launchStudyCardsSession({
    required String title,
    required List<dynamic> sessionQuestions,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _StudyModeScreen(
          title: title,
          subjectName: _customTitle,
          accentColor: _themeColor,
          questions: sessionQuestions,
          isFavorite: (qId) => _favQuestionIds.contains(qId),
          getNote: _getQuestionNote,
          onToggleFavorite: _toggleQuestionFavorite,
          onSaveNote: _updateQuestionNote,
          onShareQuestion: _shareQuestionText,
        ),
      ),
    );
  }

  Future<void> _exportWeakQuestions() async {
    final weakQs = _questions
        .where((q) => _getQuestionState(q['id']) == 'weak' || _getQuestionState(q['id']) == 'critical')
        .toList();
    if (weakQs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppPrefs.tr('لا توجد أسئلة ضعيفة لتصديرها حالياً 🎉', 'No weak questions to export 🎉'))),
      );
      return;
    }

    final buf = StringBuffer()
      ..writeln('📋 ملخص الأسئلة الضعيفة والأكثر خطأً — $_customTitle')
      ..writeln('العدد الإجمالي: ${weakQs.length} سؤال')
      ..writeln('=' * 40)
      ..writeln('');

    for (int i = 0; i < weakQs.length; i++) {
      final q = weakQs[i];
      final List<dynamic> opts = q['options'] is String ? jsonDecode(q['options']) : (q['options'] ?? []);
      final int cIdx = q['correct_index'] ?? 0;
      final ans = (cIdx >= 0 && cIdx < opts.length) ? opts[cIdx].toString() : '';
      final exp = (q['explanation'] ?? '').toString().trim();
      buf.writeln('${i + 1}) ${q['question_text']}');
      buf.writeln('   ✅ الإجابة الصحيحة: $ans');
      if (exp.isNotEmpty) buf.writeln('   💡 التوضيح: $exp');
      buf.writeln('');
    }

    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: buf.toString()));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppPrefs.tr('تم نسخ الأسئلة الضعيفة إلى الحافظة', 'Copied weak questions to clipboard'))),
        );
      }
    } else {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/Weak_Questions_${_subjectId}.txt');
      await file.writeAsString(buf.toString());
      await Share.shareXFiles([XFile(file.path)], text: 'الأسئلة الضعيفة — $_customTitle');
    }
  }

  void _openSubjectSettingsSheet() {
    final nameCtrl = TextEditingController(text: _customTitle);
    Color tempColor = _themeColor;
    int tempGoal = _dailyGoal;
    String? tempExam = _examDateIso;
    bool tempShuffle = _shuffleOptions;
    bool tempRecall = _recallBeforeOptions;

    final colors = [
      const Color(0xFF4FD1C5),
      const Color(0xFF2B6CB0),
      const Color(0xFF1E8449),
      const Color(0xFFA95C68),
      const Color(0xFFB9770E),
      const Color(0xFF8E44AD),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                Text(AppPrefs.tr('إعدادات وتخصيص المادة', 'Subject Settings'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: tempColor)),
                const SizedBox(height: 14),
                Text(AppPrefs.tr('اسم المادة على هاتفك:', 'Subject Display Name:'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                Text(AppPrefs.tr('لون واجهة المادة:', 'Subject Accent Color:'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: colors.map((c) {
                    return GestureDetector(
                      onTap: () => setSheetState(() => tempColor = c),
                      child: CircleAvatar(
                        backgroundColor: c,
                        radius: 18,
                        child: tempColor.value == c.value ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                      ),
                    );
                  }).toList(),
                ),
                const Divider(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.event_available_rounded, color: tempColor),
                  title: Text(AppPrefs.tr('تاريخ اختبار المادة', 'Exam Date'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    tempExam != null
                        ? tempExam!.split('T').first
                        : AppPrefs.tr('غير محدد (اضغط لتحديد الموعد وحساب خطة المذاكرة)', 'Not set (tap to set exam date)'),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  trailing: tempExam != null
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setSheetState(() => tempExam = null),
                        )
                      : const Icon(Icons.calendar_month_rounded),
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: now.add(const Duration(days: 14)),
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setSheetState(() => tempExam = picked.toIso8601String());
                    }
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(AppPrefs.tr('الهدف اليومي للأسئلة:', 'Daily Questions Goal:'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: tempGoal > 5 ? () => setSheetState(() => tempGoal -= 5) : null,
                        ),
                        Text('$tempGoal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: tempColor)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setSheetState(() => tempGoal += 5),
                        ),
                      ],
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(AppPrefs.tr('ترتيب الخيارات عشوائياً أثناء التدريب', 'Shuffle Answer Choices'), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                  value: tempShuffle,
                  activeColor: tempColor,
                  onChanged: (v) => setSheetState(() => tempShuffle = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(AppPrefs.tr('التذكر قبل عرض الخيارات', 'Recall Before Showing Options'), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                  subtitle: Text(AppPrefs.tr('إخفاء الخيارات مؤقتاً لتختبر ذاكرتك أولاً', 'Hide options until you tap to reveal'), style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                  value: tempRecall,
                  activeColor: tempColor,
                  onChanged: (v) => setSheetState(() => tempRecall = v),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: tempColor, foregroundColor: Colors.black),
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      final newTitle = nameCtrl.text.trim().isEmpty ? _customTitle : nameCtrl.text.trim();
                      await prefs.setString('subj_title_$_subjectId', newTitle);
                      await prefs.setInt('subj_color_$_subjectId', tempColor.value);
                      await prefs.setInt('subj_goal_$_subjectId', tempGoal);
                      if (tempExam != null) {
                        await prefs.setString('subj_exam_$_subjectId', tempExam!);
                      } else {
                        await prefs.remove('subj_exam_$_subjectId');
                      }
                      await prefs.setBool('subj_shuffle_$_subjectId', tempShuffle);
                      await prefs.setBool('subj_recall_$_subjectId', tempRecall);

                      setState(() {
                        _customTitle = newTitle;
                        _themeColor = tempColor;
                        _dailyGoal = tempGoal;
                        _examDateIso = tempExam;
                        _shuffleOptions = tempShuffle;
                        _recallBeforeOptions = tempRecall;
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Text(AppPrefs.tr('حفظ الإعدادات', 'Save Settings'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Theme.of(context).cardColor;

    return Scaffold(
      appBar: AppBar(
        title: Text(_customTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        actions: [
          IconButton(
            tooltip: AppPrefs.tr('إعدادات المادة', 'Subject Settings'),
            icon: Icon(Icons.tune_rounded, color: _themeColor),
            onPressed: _openSubjectSettingsSheet,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _themeColor,
          labelColor: _themeColor,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: [
            Tab(text: AppPrefs.tr('التدريب والأسئلة', 'Study & Quiz')),
            Tab(text: AppPrefs.tr('المحاضرات والملفات', 'Files & PDFs')),
            Tab(text: AppPrefs.tr('نقاط الضعف والإحصاء', 'Stats & Weak')),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _themeColor))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildStudyAndQuestionsTab(cardBg),
                _buildMaterialsOrganizedTab(cardBg),
                _buildWeakAndStatsTab(cardBg),
              ],
            ),
    );
  }

  /// التبويب الأول: لوحة مذاكرة هادئة ومرتبة + 4 أوضاع تدريب + بحث وفلترة متقدمة
  Widget _buildStudyAndQuestionsTab(Color cardBg) {
    final radius = AppPrefs.cardRadius;
    final borderCol = Colors.grey.withOpacity(0.18);

    final int totalQ = _questions.length;
    final int masteredQ = _questions.where((q) => _getQuestionState(q['id']) == 'mastered').length;
    final int weakQ = _questions.where((q) => _getQuestionState(q['id']) == 'weak' || _getQuestionState(q['id']) == 'critical').length;
    final int dueQ = _questions.where((q) => _isQuestionDueForReview(q['id'])).length;
    final double masteryRatio = totalQ == 0 ? 0.0 : masteredQ / totalQ;

    String examPlanText = '';
    if (_examDateIso != null) {
      final examDt = DateTime.tryParse(_examDateIso!);
      if (examDt != null) {
        final daysLeft = examDt.difference(DateTime.now()).inDays + 1;
        final remainingQs = max(0, totalQ - masteredQ);
        if (daysLeft > 0) {
          final perDay = (remainingQs / daysLeft).ceil();
          examPlanText = AppPrefs.tr(
            'متبقي $daysLeft يوم للاختبار • المطلوب $perDay سؤال/يوم',
            '$daysLeft days left • $perDay Qs/day needed',
          );
        } else {
          examPlanText = AppPrefs.tr('موعد الاختبار اليوم — بالتوفيق!', 'Exam day is today — Good luck!');
        }
      }
    }

    // تطبيق البحث والفلاتر على قائمة الأسئلة
    final Set<int> lectureNumbers = {};
    for (final q in _questions) {
      final ln = int.tryParse('${q['lecture_number'] ?? 0}') ?? 0;
      if (ln > 0) lectureNumbers.add(ln);
    }
    final sortedLecs = lectureNumbers.toList()..sort();

    final filteredQuestions = <Map<String, dynamic>>[];
    for (int i = 0; i < _questions.length; i++) {
      final q = Map<String, dynamic>.from(_questions[i]);
      final int qId = q['id'];
      final int displayNum = i + 1;
      final state = _getQuestionState(qId);

      if (_qLectureFilter != null) {
        final ln = int.tryParse('${q['lecture_number'] ?? 0}') ?? 0;
        if (ln != _qLectureFilter) continue;
      }

      if (_qStatusFilter == 'new' && state != 'new') continue;
      if (_qStatusFilter == 'correct' && state != 'correct') continue;
      if (_qStatusFilter == 'mastered' && state != 'mastered') continue;
      if (_qStatusFilter == 'weak' && state != 'weak' && state != 'critical') continue;
      if (_qStatusFilter == 'critical' && state != 'critical') continue;
      if (_qStatusFilter == 'fav' && !_favQuestionIds.contains(qId)) continue;
      if (_qStatusFilter == 'noted' && _getQuestionNote(qId).isEmpty) continue;

      if (_qSearchQuery.isNotEmpty) {
        final clean = _qSearchQuery.replaceAll('#', '').trim().toLowerCase();
        final text = (q['question_text'] ?? '').toString().toLowerCase();
        if (!text.contains(clean) && '$displayNum' != clean && '$qId' != clean) continue;
      }

      q['_displayNum'] = displayNum;
      q['_state'] = state;
      filteredQuestions.add(q);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // بطاقة التقدم الموحدة الهادئة
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: _themeColor.withOpacity(0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppPrefs.tr('إتقان المادة: ${(masteryRatio * 100).round()}%', 'Subject Mastery: ${(masteryRatio * 100).round()}%'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  Text(
                    '$masteredQ / $totalQ ${AppPrefs.tr('سؤال', 'Qs')}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _themeColor),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: masteryRatio,
                  minHeight: 7,
                  backgroundColor: Colors.grey.withOpacity(0.18),
                  color: _themeColor,
                ),
              ),
              if (examPlanText.isNotEmpty || dueQ > 0) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 14, color: _themeColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        examPlanText.isNotEmpty
                            ? examPlanText
                            : AppPrefs.tr('لديك $dueQ سؤال مستحق للمراجعة المتباعدة اليوم', '$dueQ questions due for spaced review'),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ],
              if (totalQ > 0) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _themeColor,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.bolt_rounded, size: 20),
                    label: Text(
                      AppPrefs.tr('ابدأ تحدي اليوم (10 أسئلة مختارة)', 'Start Daily Challenge (10 Qs)'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    onPressed: _startDailyChallenge,
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 14),

        // شبكة أوضاع المذاكرة الأربعة بشكل نظيف ومتوازن
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.55,
          children: [
            _studyModeCard(
              cardBg: cardBg,
              radius: radius,
              icon: Icons.edit_note_rounded,
              color: _themeColor,
              title: AppPrefs.tr('التدريب التفاعلي', 'Practice Mode'),
              subtitle: AppPrefs.tr('حل مع التوضيح الفوري', 'Solve with instant feedback'),
              onTap: () => _openSessionLauncher(mode: 'practice'),
            ),
            _studyModeCard(
              cardBg: cardBg,
              radius: radius,
              icon: Icons.style_rounded,
              color: Colors.amber,
              title: AppPrefs.tr('البطاقات السريعة', 'Flashcards'),
              subtitle: AppPrefs.tr('اقلب البطاقة وقيّم حفظك', 'Flip & self-rate recall'),
              onTap: () => _openSessionLauncher(mode: 'flashcards'),
            ),
            _studyModeCard(
              cardBg: cardBg,
              radius: radius,
              icon: Icons.menu_book_rounded,
              color: Colors.lightBlueAccent,
              title: AppPrefs.tr('وضع الحفظ', 'Study Mode'),
              subtitle: AppPrefs.tr('تصفح السؤال مع إظهار الجواب', 'Browse Q & reveal answer'),
              onTap: () => _openSessionLauncher(mode: 'study'),
            ),
            _studyModeCard(
              cardBg: cardBg,
              radius: radius,
              icon: Icons.timer_rounded,
              color: Colors.tealAccent,
              title: AppPrefs.tr('الاختبار المحاكي', 'Mock Exam'),
              subtitle: AppPrefs.tr('اختبار عشوائي بمؤقت زمني', 'Timed random exam'),
              onTap: _openMockExamSetup,
            ),
          ],
        ),

        const SizedBox(height: 18),

        // رأس قسم بنك الأسئلة + شريط البحث المدمج
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${AppPrefs.tr('بنك الأسئلة', 'Question Bank')} (${filteredQuestions.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (sortedLecs.isNotEmpty)
              DropdownButton<int?>(
                value: _qLectureFilter,
                underline: const SizedBox.shrink(),
                style: TextStyle(fontSize: 12.5, color: _themeColor, fontWeight: FontWeight.bold),
                hint: Text(AppPrefs.tr('كل المحاضرات', 'All Lectures'), style: TextStyle(fontSize: 12.5, color: _themeColor)),
                items: [
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text(AppPrefs.tr('كل المحاضرات', 'All Lectures')),
                  ),
                  ...sortedLecs.map((ln) => DropdownMenuItem<int?>(
                        value: ln,
                        child: Text('${AppPrefs.tr('المحاضرة', 'Lecture')} $ln'),
                      )),
                ],
                onChanged: (val) => setState(() => _qLectureFilter = val),
              ),
          ],
        ),
        const SizedBox(height: 8),

        TextField(
          controller: _qSearchCtrl,
          onChanged: (v) => setState(() => _qSearchQuery = v),
          decoration: InputDecoration(
            hintText: AppPrefs.tr('ابحث بكلمة أو برقم السؤال (مثلاً #15)...', 'Search by keyword or #number...'),
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _qSearchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _qSearchCtrl.clear();
                      setState(() => _qSearchQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: cardBg,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: borderCol)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: borderCol)),
          ),
        ),

        const SizedBox(height: 10),

        // صف واحد فقط من أزرار التصفية القابلة للتمرير الأفقي (بلا ازدحام)
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _filterPill('all', AppPrefs.tr('الكل', 'All')),
              _filterPill('new', AppPrefs.tr('جديد', 'New')),
              _filterPill('correct', AppPrefs.tr('صحيح', 'Correct')),
              _filterPill('mastered', AppPrefs.tr('متقن', 'Mastered')),
              _filterPill('weak', '${AppPrefs.tr('ضعيف', 'Weak')} ($weakQ)'),
              _filterPill('critical', AppPrefs.tr('خطير +3', 'Critical')),
              _filterPill('fav', AppPrefs.tr('المفضلة ⭐', 'Starred ⭐')),
              _filterPill('noted', AppPrefs.tr('بملاحظة', 'With Note')),
            ],
          ),
        ),

        const SizedBox(height: 12),

        if (_questions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: Text(
                AppPrefs.tr(
                  'لا توجد أسئلة مضافة لهذه المادة حتى الآن.\nسيتم تحديثها تلقائياً فور إضافتها من الإدارة.',
                  'No questions added for this subject yet.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          )
        else if (filteredQuestions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                AppPrefs.tr('لا توجد أسئلة مطابقة لخيارات البحث أو الفلترة الحالية.', 'No matching questions found.'),
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ...filteredQuestions.map((q) {
            final int qId = q['id'];
            final int displayNum = q['_displayNum'] as int;
            final String state = q['_state'] as String;
            return _QuestionCard(
              index: displayNum,
              question: q,
              accentColor: _themeColor,
              stateBadge: state,
              wrongCount: _getQuestionWrongCount(qId),
              personalNote: _getQuestionNote(qId),
              isFavorite: _favQuestionIds.contains(qId),
              onToggleFavorite: () => _toggleQuestionFavorite(qId),
              onEditNote: () => _openQuestionNoteDialog(q),
              onShare: () => _shareQuestionText(q, displayNum),
              onReport: () => _openReportQuestionDialog(q),
              onAnswered: (isCorrect) => _recordAnswer(qId, isCorrect),
            );
          }),
      ],
    );
  }

  Widget _studyModeCard({
    required Color cardBg,
    required double radius,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.grey.withOpacity(0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20),
            ),
            const Spacer(),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
            const SizedBox(height: 2),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _filterPill(String value, String label) {
    final selected = _qStatusFilter == value;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: _themeColor,
        labelStyle: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          color: selected ? Colors.black : null,
        ),
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() => _qStatusFilter = value),
      ),
    );
  }

  /// التبويب الثاني: المحاضرات والملفات مجمّعة حسب المحاضرة والمجموعات مع شريط الإنجاز والبحث
  Widget _buildMaterialsOrganizedTab(Color cardBg) {
    final radius = AppPrefs.cardRadius;
    final borderCol = Colors.grey.withOpacity(0.18);

    if (_materials.isEmpty) {
      return Center(
        child: Text(
          AppPrefs.tr('لا توجد ملفات أو محاضرات مرفوعة لهذه المادة حالياً.', 'No files uploaded for this subject yet.'),
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    final int completedCount = _materials.where((m) => _completedMaterialIds.contains(m['id'])).length;
    final double progress = _materials.isEmpty ? 0.0 : completedCount / _materials.length;

    String classifyMaterial(Map<String, dynamic> m) {
      final t = (m['file_type'] ?? '').toString().toUpperCase();
      final title = (m['title'] ?? '').toString();
      if (t.contains('AUDIO') || title.contains('تسجيل') || title.contains('صوت')) return 'audio';
      if (t.contains('VIDEO') || title.contains('فيديو')) return 'video';
      if (t.contains('SUMMARY') || title.contains('ملخص') || title.contains('تفريغ')) return 'summary';
      if (t.contains('PDF') || t.contains('LECTURE')) return 'lecture';
      return 'other';
    }

    final filteredMats = _materials.where((m) {
      final mapM = Map<String, dynamic>.from(m);
      final cat = classifyMaterial(mapM);
      if (_mTypeFilter != 'all' && cat != _mTypeFilter) return false;
      if (_mSearchQuery.isNotEmpty) {
        final title = (mapM['title'] ?? '').toString().toLowerCase();
        if (!title.contains(_mSearchQuery.trim().toLowerCase())) return false;
      }
      return true;
    }).toList();

    // تجميع الملفات حسب رقم المحاضرة (أو عامة)
    final Map<int, List<Map<String, dynamic>>> groupedByLec = {};
    for (final m in filteredMats) {
      final mapM = Map<String, dynamic>.from(m);
      final lecNum = int.tryParse('${mapM['lecture_number'] ?? 0}') ?? 0;
      groupedByLec.putIfAbsent(lecNum, () => []).add(mapM);
    }
    final sortedKeys = groupedByLec.keys.toList()
      ..sort((a, b) {
        if (a == 0) return 1;
        if (b == 0) return -1;
        return a.compareTo(b);
      });

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // شريط نسبة إنجاز مذاكرة الملفات
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: _themeColor.withOpacity(0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(AppPrefs.tr('نسبة إنجاز مذاكرة المحاضرات', 'Lectures Study Progress'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
                  minHeight: 7,
                  backgroundColor: Colors.grey.withOpacity(0.18),
                  color: _themeColor,
                ),
              ),
            ],
          ),
        ),

        // البحث في الملفات
        TextField(
          controller: _mSearchCtrl,
          onChanged: (v) => setState(() => _mSearchQuery = v),
          decoration: InputDecoration(
            hintText: AppPrefs.tr('ابحث في ملفات المادة...', 'Search subject files...'),
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _mSearchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _mSearchCtrl.clear();
                      setState(() => _mSearchQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: cardBg,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: borderCol)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: borderCol)),
          ),
        ),

        const SizedBox(height: 10),

        // فلتر نوع الملفات
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _matTypeChip('all', AppPrefs.tr('الكل', 'All')),
              _matTypeChip('lecture', AppPrefs.tr('محاضرات', 'Lectures')),
              _matTypeChip('summary', AppPrefs.tr('ملخصات', 'Summaries')),
              _matTypeChip('audio', AppPrefs.tr('صوتيات', 'Audio')),
              _matTypeChip('video', AppPrefs.tr('فيديو', 'Videos')),
              _matTypeChip('other', AppPrefs.tr('أخرى', 'Other')),
            ],
          ),
        ),

        const SizedBox(height: 12),

        if (filteredMats.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(AppPrefs.tr('لا توجد ملفات مطابقة للبحث.', 'No matching files.'), style: const TextStyle(color: Colors.grey)),
            ),
          )
        else
          ...sortedKeys.map((lecNum) {
            final items = groupedByLec[lecNum]!;
            final groupTitle = lecNum == 0
                ? AppPrefs.tr('ملفات ومراجع عامة', 'General Files & References')
                : '${AppPrefs.tr('المحاضرة', 'Lecture')} $lecNum';

            return Card(
              color: cardBg,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
              child: ExpansionTile(
                initiallyExpanded: sortedKeys.length <= 4 || lecNum == sortedKeys.first,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: _themeColor.withOpacity(0.18),
                  child: Text(
                    lecNum == 0 ? '★' : '$lecNum',
                    style: TextStyle(color: _themeColor, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                title: Text(groupTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                subtitle: Text('${items.length} ${AppPrefs.tr('ملف', 'files')}', style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                children: items.map((m) => _buildSingleMaterialTile(m)).toList(),
              ),
            );
          }),
      ],
    );
  }

  Widget _matTypeChip(String val, String label) {
    final selected = _mTypeFilter == val;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: _themeColor,
        labelStyle: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: selected ? Colors.black : null),
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() => _mTypeFilter = val),
      ),
    );
  }

  Widget _buildSingleMaterialTile(Map<String, dynamic> m) {
    final int id = m['id'];
    final type = (m['file_type'] ?? 'PDF').toString().toUpperCase();
    final bool isPdf = !type.contains('AUDIO') && !type.contains('VIDEO');
    final bool isSavedOffline = _downloadedFiles.containsKey(id);
    final bool isDownloading = _downloadingIds.contains(id);
    final bool isDone = _completedMaterialIds.contains(id);
    final bool isFav = _favMaterialIds.contains(id);

    IconData icon = Icons.picture_as_pdf_rounded;
    Color iconColor = Colors.redAccent;
    if (type.contains('AUDIO')) {
      icon = Icons.headphones_rounded;
      iconColor = Colors.amber;
    } else if (type.contains('VIDEO')) {
      icon = Icons.play_circle_fill_rounded;
      iconColor = Colors.lightBlueAccent;
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        dense: true,
        onTap: () => _handleMaterialTap(m),
        onLongPress: isSavedOffline ? () => _deleteOfflineMaterial(id) : null,
        leading: Icon(icon, color: iconColor, size: 24),
        title: Text(
          m['title'] ?? '',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13.5,
            decoration: isDone ? TextDecoration.lineThrough : null,
            color: isDone ? Colors.grey : null,
          ),
        ),
        subtitle: Text(
          isPdf
              ? (isSavedOffline ? AppPrefs.tr('محفوظ أوفلاين ✅ (اضغط للفتح)', 'Saved offline ✅') : AppPrefs.tr('PDF • اضغط للتحميل والفتح', 'PDF • Tap to download'))
              : '${AppPrefs.tr('رابط خارجي', 'External link')} ($type)',
          style: TextStyle(fontSize: 11, color: isSavedOffline ? Colors.greenAccent : Colors.grey),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: AppPrefs.tr('مفضلة ليلة الامتحان', 'Exam Review Favorite'),
              icon: Icon(isFav ? Icons.star_rounded : Icons.star_border_rounded, color: isFav ? Colors.amber : Colors.grey, size: 20),
              onPressed: () => _toggleMaterialFavorite(id),
            ),
            IconButton(
              tooltip: AppPrefs.tr('تمت المذاكرة', 'Mark Studied'),
              icon: Icon(isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: isDone ? Colors.greenAccent : Colors.grey, size: 20),
              onPressed: () => _toggleMaterialCompleted(id),
            ),
            if (isDownloading)
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(
                isPdf ? (isSavedOffline ? Icons.offline_pin_rounded : Icons.download_rounded) : Icons.open_in_new_rounded,
                color: isSavedOffline ? Colors.greenAccent : _themeColor,
                size: 19,
              ),
          ],
        ),
      ),
    );
  }

  /// التبويب الثالث: نقاط الضعف والإحصائيات والتكرار المتباعد
  Widget _buildWeakAndStatsTab(Color cardBg) {
    final radius = AppPrefs.cardRadius;
    final double accuracy = _totalAnswered == 0 ? 0 : (_correctAnswered / _totalAnswered) * 100;

    final int newCount = _questions.where((q) => _getQuestionState(q['id']) == 'new').length;
    final int correctCount = _questions.where((q) => _getQuestionState(q['id']) == 'correct').length;
    final int masteredCount = _questions.where((q) => _getQuestionState(q['id']) == 'mastered').length;

    final weakQuestions = _questions
        .where((q) => _getQuestionState(q['id']) == 'weak' || _getQuestionState(q['id']) == 'critical')
        .toList()
      ..sort((a, b) => _getQuestionWrongCount(b['id']).compareTo(_getQuestionWrongCount(a['id'])));

    final int criticalCount = weakQuestions.where((q) => _getQuestionState(q['id']) == 'critical').length;

    // توزيع صناديق التكرار المتباعد (0..5)
    final boxCounts = List<int>.filled(6, 0);
    for (final q in _questions) {
      final b = _getQuestionBox(q['id']).clamp(0, 5);
      boxCounts[b]++;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // بطاقة الدقة والإحصائيات السريعة
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: _themeColor.withOpacity(0.35)),
          ),
          child: Column(
            children: [
              Text('${accuracy.toStringAsFixed(1)}%', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: _themeColor)),
              Text(AppPrefs.tr('نسبة الدقة في الإجابات', 'Answer Accuracy'), style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _miniStat(AppPrefs.tr('متقن', 'Mastered'), '$masteredCount', Colors.greenAccent)),
                  Expanded(child: _miniStat(AppPrefs.tr('صحيح', 'Correct'), '$correctCount', Colors.lightBlueAccent)),
                  Expanded(child: _miniStat(AppPrefs.tr('ضعيف', 'Weak'), '${weakQuestions.length}', Colors.redAccent)),
                  Expanded(child: _miniStat(AppPrefs.tr('جديد', 'New'), '$newCount', Colors.grey)),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // بطاقة التكرار المتباعد (6 صناديق)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.grey.withOpacity(0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.psychology_rounded, color: _themeColor, size: 20),
                  const SizedBox(width: 8),
                  Text(AppPrefs.tr('صناديق التكرار المتباعد', 'Spaced Repetition Boxes'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _boxChip(AppPrefs.tr('فوراً', 'Now'), boxCounts[0], Colors.redAccent),
                  _boxChip('3d', boxCounts[1], Colors.orange),
                  _boxChip('7d', boxCounts[2], Colors.amber),
                  _boxChip('14d', boxCounts[3], Colors.lightBlueAccent),
                  _boxChip('30d', boxCounts[4], Colors.tealAccent),
                  _boxChip(AppPrefs.tr('متقن', 'Done'), boxCounts[5], Colors.greenAccent),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // قسم نقاط الضعف والأكثر خطأً
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${AppPrefs.tr('نقاط الضعف', 'Weak Points')} (${weakQuestions.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (criticalCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.16), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  '${AppPrefs.tr('خطير (+3 أخطاء):', 'Critical:')} $criticalCount',
                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11.5),
                ),
              ),
          ],
        ),

        if (weakQuestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _themeColor,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: Text(AppPrefs.tr('راجع الضعيفة الآن', 'Review Weak Now'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: () => _launchPracticeSession(
                    title: AppPrefs.tr('مراجعة نقاط الضعف', 'Weak Questions Review'),
                    sessionQuestions: weakQuestions,
                    requeueWrong: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _themeColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: Icon(Icons.share_rounded, size: 18, color: _themeColor),
                label: Text(AppPrefs.tr('تصدير', 'Export'), style: TextStyle(color: _themeColor, fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: _exportWeakQuestions,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(weakQuestions.length, (idx) {
            final q = weakQuestions[idx];
            final int qId = q['id'];
            return _QuestionCard(
              index: idx + 1,
              question: q,
              accentColor: Colors.redAccent,
              stateBadge: _getQuestionState(qId),
              wrongCount: _getQuestionWrongCount(qId),
              personalNote: _getQuestionNote(qId),
              isFavorite: _favQuestionIds.contains(qId),
              onToggleFavorite: () => _toggleQuestionFavorite(qId),
              onEditNote: () => _openQuestionNoteDialog(q),
              onShare: () => _shareQuestionText(q, idx + 1),
              onReport: () => _openReportQuestionDialog(q),
              onAnswered: (isCorrect) => _recordAnswer(qId, isCorrect),
            );
          }),
        ] else
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                AppPrefs.tr('رائع! لا توجد لديك أسئلة خاطئة مسجلة في هذه المادة 🎉', 'Great! No weak questions recorded 🎉'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          ),
      ],
    );
  }

  Widget _miniStat(String label, String val, Color col) {
    return Column(
      children: [
        Text(val, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: col)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _boxChip(String label, int count, Color col) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: col.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text('$count', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: col)),
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

/// بطاقة السؤال في القائمة الرئيسية لبنك الأسئلة ونقاط الضعف
class _QuestionCard extends StatefulWidget {
  final int index;
  final Map<String, dynamic> question;
  final Color accentColor;
  final String stateBadge;
  final int wrongCount;
  final String personalNote;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onEditNote;
  final VoidCallback onShare;
  final VoidCallback onReport;
  final Function(bool isCorrect) onAnswered;

  const _QuestionCard({
    required this.index,
    required this.question,
    required this.accentColor,
    required this.stateBadge,
    required this.wrongCount,
    required this.personalNote,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onEditNote,
    required this.onShare,
    required this.onReport,
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
    final cardBg = Theme.of(context).cardColor;

    Color statusColor = Colors.grey;
    String statusText = AppPrefs.tr('جديد', 'New');
    if (widget.stateBadge == 'mastered') {
      statusColor = Colors.greenAccent;
      statusText = AppPrefs.tr('متقن', 'Mastered');
    } else if (widget.stateBadge == 'correct') {
      statusColor = Colors.lightBlueAccent;
      statusText = AppPrefs.tr('صحيح', 'Correct');
    } else if (widget.stateBadge == 'critical') {
      statusColor = Colors.redAccent;
      statusText = '${AppPrefs.tr('خطير', 'Critical')} (${widget.wrongCount}×)';
    } else if (widget.stateBadge == 'weak') {
      statusColor = Colors.orangeAccent;
      statusText = '${AppPrefs.tr('ضعيف', 'Weak')} (${widget.wrongCount}×)';
    }

    return Card(
      color: cardBg,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppPrefs.cardRadius)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                  child: Text('#${widget.index} • $statusText', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor)),
                ),
                const Spacer(),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: AppPrefs.tr('ملاحظتي', 'My Note'),
                  icon: Icon(
                    widget.personalNote.isNotEmpty ? Icons.sticky_note_2_rounded : Icons.sticky_note_2_outlined,
                    color: widget.personalNote.isNotEmpty ? Colors.amber : Colors.grey,
                    size: 19,
                  ),
                  onPressed: widget.onEditNote,
                ),
                const SizedBox(width: 10),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: AppPrefs.tr('مشاركة السؤال', 'Share'),
                  icon: const Icon(Icons.share_outlined, color: Colors.grey, size: 19),
                  onPressed: widget.onShare,
                ),
                const SizedBox(width: 10),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: AppPrefs.tr('إبلاغ عن خطأ', 'Report'),
                  icon: const Icon(Icons.flag_outlined, color: Colors.grey, size: 19),
                  onPressed: widget.onReport,
                ),
                const SizedBox(width: 10),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: AppPrefs.tr('المفضلة', 'Favorite'),
                  icon: Icon(
                    widget.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                    color: widget.isFavorite ? Colors.amber : Colors.grey,
                    size: 21,
                  ),
                  onPressed: widget.onToggleFavorite,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              widget.question['question_text'] ?? '',
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, height: 1.45),
            ),
            if (widget.personalNote.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withOpacity(0.4)),
                ),
                child: Text('📝 ${widget.personalNote}', style: const TextStyle(fontSize: 12, color: Colors.amberAccent)),
              ),
            ],
            const SizedBox(height: 12),
            ...List.generate(options.length, (i) {
              Color borderColor = Colors.grey.withOpacity(0.22);
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
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor),
                    ),
                    child: Text(options[i].toString(), style: const TextStyle(fontSize: 13.5)),
                  ),
                ),
              );
            }),
            if (_selectedIndex != null && (widget.question['explanation'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.grey.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                child: Text('💡 ${AppPrefs.tr('التوضيح:', 'Explanation:')} ${widget.question['explanation']}', style: const TextStyle(fontSize: 12, color: Colors.amberAccent)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// شاشة التدريب التفاعلي الكاملة (مع التذكر قبل الخيارات، إعادة السؤال الخاطئ، والملاحظات)
class _InteractivePracticeScreen extends StatefulWidget {
  final String title;
  final String subjectName;
  final Color accentColor;
  final List<dynamic> initialQuestions;
  final bool shuffleOptions;
  final bool recallBeforeOptions;
  final bool requeueWrong;
  final bool Function(int qId) isFavorite;
  final String Function(int qId) getNote;
  final Future<void> Function(int qId) onToggleFavorite;
  final Future<void> Function(int qId, String note) onSaveNote;
  final Future<void> Function(int qId, bool isCorrect) onAnswered;
  final void Function(Map<String, dynamic> q, int num) onShareQuestion;
  final void Function(Map<String, dynamic> q) onReportQuestion;

  const _InteractivePracticeScreen({
    required this.title,
    required this.subjectName,
    required this.accentColor,
    required this.initialQuestions,
    required this.shuffleOptions,
    required this.recallBeforeOptions,
    required this.requeueWrong,
    required this.isFavorite,
    required this.getNote,
    required this.onToggleFavorite,
    required this.onSaveNote,
    required this.onAnswered,
    required this.onShareQuestion,
    required this.onReportQuestion,
  });

  @override
  State<_InteractivePracticeScreen> createState() => _InteractivePracticeScreenState();
}

class _InteractivePracticeScreenState extends State<_InteractivePracticeScreen> {
  late List<Map<String, dynamic>> _queue;
  int _idx = 0;
  int? _selectedIdx;
  bool _optionsRevealed = true;
  int _sessionCorrect = 0;
  int _sessionWrong = 0;
  List<int> _currentOptionOrder = [];

  @override
  void initState() {
    super.initState();
    _queue = widget.initialQuestions.map((e) => Map<String, dynamic>.from(e)).toList();
    _prepareCurrentQuestion();
  }

  void _prepareCurrentQuestion() {
    if (_idx >= _queue.length) return;
    final q = _queue[_idx];
    final List<dynamic> opts = q['options'] is String ? jsonDecode(q['options']) : (q['options'] ?? []);
    _currentOptionOrder = List<int>.generate(opts.length, (i) => i);
    if (widget.shuffleOptions) {
      _currentOptionOrder.shuffle();
    }
    _selectedIdx = null;
    _optionsRevealed = !widget.recallBeforeOptions;
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Theme.of(context).cardColor;
    final bool finished = _idx >= _queue.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          if (!finished)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Text(
                '${_idx + 1} / ${_queue.length}',
                style: TextStyle(color: widget.accentColor, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: finished
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(20)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.emoji_events_rounded, size: 64, color: widget.accentColor),
                      const SizedBox(height: 12),
                      Text(AppPrefs.tr('أنهيت جلسة التدريب بنجاح!', 'Session Complete!'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 14),
                      Text('✅ ${AppPrefs.tr('إجابات صحيحة:', 'Correct:')} $_sessionCorrect', style: const TextStyle(color: Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text('❌ ${AppPrefs.tr('أخطاء:', 'Wrong:')} $_sessionWrong', style: const TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: widget.accentColor, foregroundColor: Colors.black),
                          onPressed: () => Navigator.pop(context),
                          child: Text(AppPrefs.tr('العودة للمادة', 'Back to Subject'), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : Builder(
              builder: (context) {
                final q = _queue[_idx];
                final int qId = q['id'];
                final List<dynamic> opts = q['options'] is String ? jsonDecode(q['options']) : (q['options'] ?? []);
                final int correctIdx = q['correct_index'] ?? 0;
                final bool isRequeued = q['_requeued'] == true;
                final note = widget.getNote(qId);

                return Column(
                  children: [
                    LinearProgressIndicator(
                      value: (_idx + 1) / _queue.length,
                      minHeight: 4,
                      backgroundColor: Colors.grey.withOpacity(0.2),
                      color: widget.accentColor,
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (isRequeued)
                            Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.orange),
                              ),
                              child: Text(
                                AppPrefs.tr('🔁 سؤال مُعاد من هذه الجلسة لتثبيت إجابته', '🔁 Re-queued question for mastery'),
                                style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.grey.withOpacity(0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text('#$qId', style: TextStyle(color: widget.accentColor, fontWeight: FontWeight.bold)),
                                    const Spacer(),
                                    IconButton(
                                      icon: Icon(widget.isFavorite(qId) ? Icons.star_rounded : Icons.star_border_rounded, color: widget.isFavorite(qId) ? Colors.amber : Colors.grey),
                                      onPressed: () async {
                                        await widget.onToggleFavorite(qId);
                                        setState(() {});
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.share_outlined, size: 20),
                                      onPressed: () => widget.onShareQuestion(q, _idx + 1),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.flag_outlined, size: 20),
                                      onPressed: () => widget.onReportQuestion(q),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(q['question_text'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.5)),
                                if (note.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: Colors.amber.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                                    child: Text('📝 $note', style: const TextStyle(fontSize: 12, color: Colors.amberAccent)),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                if (!_optionsRevealed)
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(side: BorderSide(color: widget.accentColor)),
                                      icon: Icon(Icons.visibility_rounded, color: widget.accentColor),
                                      label: Text(AppPrefs.tr('إظهار الخيارات', 'Reveal Options'), style: TextStyle(color: widget.accentColor, fontWeight: FontWeight.bold)),
                                      onPressed: () => setState(() => _optionsRevealed = true),
                                    ),
                                  )
                                else
                                  ..._currentOptionOrder.map((origIdx) {
                                    Color borderCol = Colors.grey.withOpacity(0.25);
                                    Color bgCol = Colors.transparent;
                                    if (_selectedIdx != null) {
                                      if (origIdx == correctIdx) {
                                        borderCol = Colors.green;
                                        bgCol = Colors.green.withOpacity(0.18);
                                      } else if (origIdx == _selectedIdx) {
                                        borderCol = Colors.redAccent;
                                        bgCol = Colors.redAccent.withOpacity(0.18);
                                      }
                                    }

                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: InkWell(
                                        onTap: _selectedIdx != null
                                            ? null
                                            : () async {
                                                final ok = origIdx == correctIdx;
                                                setState(() {
                                                  _selectedIdx = origIdx;
                                                  if (ok) {
                                                    _sessionCorrect++;
                                                  } else {
                                                    _sessionWrong++;
                                                    if (widget.requeueWrong && q['_requeued'] != true) {
                                                      final copy = Map<String, dynamic>.from(q)..['_requeued'] = true;
                                                      final insertPos = min(_queue.length, _idx + 3);
                                                      _queue.insert(insertPos, copy);
                                                    }
                                                  }
                                                });
                                                await widget.onAnswered(qId, ok);
                                              },
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: bgCol,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: borderCol, width: 1.3),
                                          ),
                                          child: Text(opts[origIdx].toString(), style: const TextStyle(fontSize: 14.5)),
                                        ),
                                      ),
                                    );
                                  }),
                                if (_selectedIdx != null && (q['explanation'] ?? '').toString().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: Colors.grey.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                                    child: Text('💡 ${q['explanation']}', style: const TextStyle(fontSize: 13, color: Colors.amberAccent, height: 1.4)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _selectedIdx != null ? widget.accentColor : cardBg,
                            foregroundColor: _selectedIdx != null ? Colors.black : Colors.grey,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () {
                            setState(() {
                              _idx++;
                              _prepareCurrentQuestion();
                            });
                          },
                          child: Text(
                            _selectedIdx != null
                                ? AppPrefs.tr('السؤال التالي ←', 'Next Question →')
                                : AppPrefs.tr('تخطي ←', 'Skip →'),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

/// وضع البطاقات السريعة (Flashcards)
class _FlashcardsSessionScreen extends StatefulWidget {
  final String title;
  final String subjectName;
  final Color accentColor;
  final List<dynamic> questions;
  final bool Function(int qId) isFavorite;
  final Future<void> Function(int qId) onToggleFavorite;
  final Future<void> Function(int qId, bool known) onRateCard;
  final void Function(Map<String, dynamic> q, int num) onShareQuestion;

  const _FlashcardsSessionScreen({
    required this.title,
    required this.subjectName,
    required this.accentColor,
    required this.questions,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onRateCard,
    required this.onShareQuestion,
  });

  @override
  State<_FlashcardsSessionScreen> createState() => _FlashcardsSessionScreenState();
}

class _FlashcardsSessionScreenState extends State<_FlashcardsSessionScreen> {
  int _idx = 0;
  bool _flipped = false;

  @override
  Widget build(BuildContext context) {
    final cardBg = Theme.of(context).cardColor;
    final bool finished = _idx >= widget.questions.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          if (!finished)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Text('${_idx + 1} / ${widget.questions.length}', style: TextStyle(color: widget.accentColor, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: finished
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 64, color: widget.accentColor),
                    const SizedBox(height: 12),
                    Text(AppPrefs.tr('أنهيت مراجعة البطاقات!', 'Flashcards Complete!'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: widget.accentColor, foregroundColor: Colors.black),
                      onPressed: () => Navigator.pop(context),
                      child: Text(AppPrefs.tr('العودة للمادة', 'Back to Subject'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            )
          : Builder(
              builder: (context) {
                final q = Map<String, dynamic>.from(widget.questions[_idx]);
                final int qId = q['id'];
                final List<dynamic> opts = q['options'] is String ? jsonDecode(q['options']) : (q['options'] ?? []);
                final int cIdx = q['correct_index'] ?? 0;
                final answerText = (cIdx >= 0 && cIdx < opts.length) ? opts[cIdx].toString() : '';

                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _flipped = !_flipped),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: _flipped ? widget.accentColor.withOpacity(0.14) : cardBg,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: widget.accentColor.withOpacity(0.45), width: 1.5),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('#$qId', style: TextStyle(color: widget.accentColor, fontWeight: FontWeight.bold)),
                                    IconButton(
                                      icon: Icon(widget.isFavorite(qId) ? Icons.star_rounded : Icons.star_border_rounded, color: widget.isFavorite(qId) ? Colors.amber : Colors.grey),
                                      onPressed: () async {
                                        await widget.onToggleFavorite(qId);
                                        setState(() {});
                                      },
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                if (!_flipped) ...[
                                  Text(
                                    q['question_text'] ?? '',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, height: 1.5),
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    AppPrefs.tr('👆 اضغط لقلب البطاقة وإظهار الإجابة', '👆 Tap to flip card'),
                                    style: TextStyle(fontSize: 12.5, color: widget.accentColor),
                                  ),
                                ] else ...[
                                  Text(AppPrefs.tr('الإجابة الصحيحة:', 'Correct Answer:'), style: const TextStyle(fontSize: 13, color: Colors.grey)),
                                  const SizedBox(height: 10),
                                  Text(
                                    answerText,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: widget.accentColor, height: 1.4),
                                  ),
                                  if ((q['explanation'] ?? '').toString().isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    Text(
                                      '💡 ${q['explanation']}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 12.5, color: Colors.grey),
                                    ),
                                  ],
                                ],
                                const Spacer(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!_flipped)
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(backgroundColor: widget.accentColor, foregroundColor: Colors.black),
                                  icon: const Icon(Icons.flip_rounded),
                                  label: Text(AppPrefs.tr('اقلب البطاقة', 'Flip Card'), style: const TextStyle(fontWeight: FontWeight.bold)),
                                  onPressed: () => setState(() => _flipped = true),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              height: 48,
                              child: OutlinedButton(
                                onPressed: () => setState(() {
                                  _idx++;
                                  _flipped = false;
                                }),
                                child: Text(AppPrefs.tr('تخطي', 'Skip')),
                              ),
                            ),
                          ],
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                  icon: const Icon(Icons.check_rounded),
                                  label: Text(AppPrefs.tr('عرفتها ✓', 'Knew It ✓'), style: const TextStyle(fontWeight: FontWeight.bold)),
                                  onPressed: () async {
                                    await widget.onRateCard(qId, true);
                                    setState(() {
                                      _idx++;
                                      _flipped = false;
                                    });
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                                  icon: const Icon(Icons.close_rounded),
                                  label: Text(AppPrefs.tr('لم أعرفها ✗', 'Missed It ✗'), style: const TextStyle(fontWeight: FontWeight.bold)),
                                  onPressed: () async {
                                    await widget.onRateCard(qId, false);
                                    setState(() {
                                      _idx++;
                                      _flipped = false;
                                    });
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// وضع الحفظ والمراجعة السريعة (عرض السؤال مع إظهار/إخفاء الجواب المباشر)
class _StudyModeScreen extends StatefulWidget {
  final String title;
  final String subjectName;
  final Color accentColor;
  final List<dynamic> questions;
  final bool Function(int qId) isFavorite;
  final String Function(int qId) getNote;
  final Future<void> Function(int qId) onToggleFavorite;
  final Future<void> Function(int qId, String note) onSaveNote;
  final void Function(Map<String, dynamic> q, int num) onShareQuestion;

  const _StudyModeScreen({
    required this.title,
    required this.subjectName,
    required this.accentColor,
    required this.questions,
    required this.isFavorite,
    required this.getNote,
    required this.onToggleFavorite,
    required this.onSaveNote,
    required this.onShareQuestion,
  });

  @override
  State<_StudyModeScreen> createState() => _StudyModeScreenState();
}

class _StudyModeScreenState extends State<_StudyModeScreen> {
  bool _hideAllAnswers = false;
  final Set<int> _individuallyRevealed = {};

  @override
  Widget build(BuildContext context) {
    final cardBg = Theme.of(context).cardColor;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          TextButton.icon(
            icon: Icon(_hideAllAnswers ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: widget.accentColor, size: 18),
            label: Text(
              _hideAllAnswers ? AppPrefs.tr('إظهار الكل', 'Show All') : AppPrefs.tr('إخفاء الإجابات', 'Hide Answers'),
              style: TextStyle(color: widget.accentColor, fontWeight: FontWeight.bold, fontSize: 12),
            ),
            onPressed: () {
              setState(() {
                _hideAllAnswers = !_hideAllAnswers;
                _individuallyRevealed.clear();
              });
            },
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: widget.questions.length,
        itemBuilder: (_, idx) {
          final q = Map<String, dynamic>.from(widget.questions[idx]);
          final int qId = q['id'];
          final List<dynamic> opts = q['options'] is String ? jsonDecode(q['options']) : (q['options'] ?? []);
          final int cIdx = q['correct_index'] ?? 0;
          final answerText = (cIdx >= 0 && cIdx < opts.length) ? opts[cIdx].toString() : '';
          final bool showAns = !_hideAllAnswers || _individuallyRevealed.contains(qId);

          return Card(
            color: cardBg,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('#${idx + 1}', style: TextStyle(color: widget.accentColor, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.share_outlined, size: 18, color: Colors.grey),
                        onPressed: () => widget.onShareQuestion(q, idx + 1),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(widget.isFavorite(qId) ? Icons.star_rounded : Icons.star_border_rounded, color: widget.isFavorite(qId) ? Colors.amber : Colors.grey, size: 20),
                        onPressed: () async {
                          await widget.onToggleFavorite(qId);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(q['question_text'] ?? '', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, height: 1.45)),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () {
                      if (_hideAllAnswers) {
                        setState(() {
                          if (_individuallyRevealed.contains(qId)) {
                            _individuallyRevealed.remove(qId);
                          } else {
                            _individuallyRevealed.add(qId);
                          }
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: showAns ? Colors.green.withOpacity(0.15) : Colors.grey.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: showAns ? Colors.green.withOpacity(0.5) : Colors.grey.withOpacity(0.3)),
                      ),
                      child: showAns
                          ? Text('✅ $answerText', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14))
                          : Center(
                              child: Text(
                                AppPrefs.tr('اضغط لإظهار الإجابة الصحيحة', 'Tap to reveal answer'),
                                style: TextStyle(color: widget.accentColor, fontSize: 12.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// شاشة الاختبار المحاكي بمؤقت زمني ونتيجة ومراجعة الأخطاء
class _MockExamScreen extends StatefulWidget {
  final String subjectName;
  final Color accentColor;
  final List<dynamic> questions;
  final int durationMinutes;
  final Future<void> Function(int qId, bool isCorrect) onRecordAnswer;

  const _MockExamScreen({
    required this.subjectName,
    required this.accentColor,
    required this.questions,
    required this.durationMinutes,
    required this.onRecordAnswer,
  });

  @override
  State<_MockExamScreen> createState() => _MockExamScreenState();
}

class _MockExamScreenState extends State<_MockExamScreen> {
  final Map<int, int> _chosenAnswers = {};
  late int _secondsRemaining;
  Timer? _timer;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.durationMinutes * 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _submitted) return;
      if (_secondsRemaining <= 1) {
        _submitExam();
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _submitExam() async {
    if (_submitted) return;
    _timer?.cancel();
    setState(() => _submitted = true);

    for (int i = 0; i < widget.questions.length; i++) {
      final q = widget.questions[i];
      final int qId = q['id'];
      final int correctIdx = q['correct_index'] ?? 0;
      final int? chosen = _chosenAnswers[i];
      if (chosen != null) {
        await widget.onRecordAnswer(qId, chosen == correctIdx);
      }
    }
  }

  String _formatTimer(int totalSec) {
    final m = (totalSec ~/ 60).toString().padLeft(2, '0');
    final s = (totalSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Theme.of(context).cardColor;

    if (_submitted) {
      int correct = 0;
      final List<Map<String, dynamic>> wrongReview = [];
      for (int i = 0; i < widget.questions.length; i++) {
        final q = Map<String, dynamic>.from(widget.questions[i]);
        final int cIdx = q['correct_index'] ?? 0;
        final int? chosen = _chosenAnswers[i];
        if (chosen == cIdx) {
          correct++;
        } else {
          q['_chosenIdx'] = chosen;
          q['_examNum'] = i + 1;
          wrongReview.add(q);
        }
      }
      final double pct = widget.questions.isEmpty ? 0 : (correct / widget.questions.length) * 100;

      return Scaffold(
        appBar: AppBar(title: Text(AppPrefs.tr('نتيجة الاختبار المحاكي', 'Mock Exam Result'))),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: widget.accentColor.withOpacity(0.4)),
              ),
              child: Column(
                children: [
                  Text('${pct.toStringAsFixed(1)}%', style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: widget.accentColor)),
                  const SizedBox(height: 6),
                  Text(
                    '${AppPrefs.tr('النتيجة:', 'Score:')} $correct ${AppPrefs.tr('من', 'out of')} ${widget.questions.length}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (wrongReview.isNotEmpty) ...[
              Text(
                '${AppPrefs.tr('مراجعة الأسئلة الخاطئة أو المتروكة', 'Review Missed Questions')} (${wrongReview.length})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.redAccent),
              ),
              const SizedBox(height: 10),
              ...wrongReview.map((q) {
                final List<dynamic> opts = q['options'] is String ? jsonDecode(q['options']) : (q['options'] ?? []);
                final int cIdx = q['correct_index'] ?? 0;
                final int? ch = q['_chosenIdx'];
                final correctText = (cIdx >= 0 && cIdx < opts.length) ? opts[cIdx].toString() : '';
                final chosenText = (ch != null && ch >= 0 && ch < opts.length) ? opts[ch].toString() : AppPrefs.tr('لم يتم الاختيار', 'Unanswered');

                return Card(
                  color: cardBg,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('سؤال ${q['_examNum']}: ${q['question_text']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 8),
                        Text('❌ ${AppPrefs.tr('إجابتك:', 'Your answer:')} $chosenText', style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('✅ ${AppPrefs.tr('الإجابة الصحيحة:', 'Correct:')} $correctText', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subjectName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _secondsRemaining < 60 ? Colors.redAccent.withOpacity(0.2) : widget.accentColor.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.timer_rounded, size: 16, color: _secondsRemaining < 60 ? Colors.redAccent : widget.accentColor),
                const SizedBox(width: 4),
                Text(
                  _formatTimer(_secondsRemaining),
                  style: TextStyle(fontWeight: FontWeight.bold, color: _secondsRemaining < 60 ? Colors.redAccent : widget.accentColor),
                ),
              ],
            ),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 84),
        itemCount: widget.questions.length,
        itemBuilder: (_, idx) {
          final q = widget.questions[idx];
          final List<dynamic> opts = q['options'] is String ? jsonDecode(q['options']) : (q['options'] ?? []);
          final int? chosen = _chosenAnswers[idx];

          return Card(
            color: cardBg,
            margin: const EdgeInsets.only(bottom: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('سؤال ${idx + 1}: ${q['question_text'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                  const SizedBox(height: 10),
                  ...List.generate(opts.length, (oIdx) {
                    final selected = chosen == oIdx;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: InkWell(
                        onTap: () => setState(() => _chosenAnswers[idx] = oIdx),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: selected ? widget.accentColor.withOpacity(0.18) : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: selected ? widget.accentColor : Colors.grey.withOpacity(0.25)),
                          ),
                          child: Text(opts[oIdx].toString(), style: const TextStyle(fontSize: 13.5)),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: widget.accentColor, foregroundColor: Colors.black),
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: Text(
                '${AppPrefs.tr('تسليم الاختبار', 'Submit Exam')} (${_chosenAnswers.length}/${widget.questions.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              onPressed: _submitExam,
            ),
          ),
        ),
      ),
    );
  }
}
