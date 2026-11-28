import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'app_prefs.dart';
import 'main.dart';
import 'home_screen.dart';

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
  final _client = Supabase.instance.client;

  List<dynamic> _materials = [];
  List<dynamic> _questions = [];
  Set<String> _favMaterialIds = {};
  Set<String> _favQuestionIds = {};
  Map<String, String> _localFilePaths = {};
  Map<String, double> _downloadProgress = {};

  /// حالة إتقان كل سؤال: 'new' | 'correct' | 'mastered' | 'weak' | 'wrong'
  Map<String, String> _questionStatus = {};
  Map<String, int> _wrongAttempts = {};

  bool _loading = true;
  String _matSearchQuery = '';
  String _selectedMatFilter = 'الكل';

  String _qSearchQuery = '';
  String _selectedQFilter = 'الكل';
  String _selectedLectureFilter = 'الكل';
  bool _shuffleQuestions = false;
  bool _showInstantExplanation = true;

  /// إجابات التدريب التفاعلي الفوري
  final Map<String, int> _interactiveChosen = {};

  dynamic get _subjectId => widget.subject['id'];
  String get _subjectName => AppLocalizer.localizeSubjectName(widget.subject);

  @override
  void initState() {
    super.initState();
    _loadLocalAndSync();
  }

  Future<void> _loadLocalAndSync() async {
    final prefs = await SharedPreferences.getInstance();
    final sid = _subjectId;

    List<dynamic> cachedMats = [];
    List<dynamic> cachedQs = [];
    try {
      cachedMats = jsonDecode(prefs.getString('cache_materials_$sid') ?? '[]');
    } catch (_) {}
    try {
      cachedQs = jsonDecode(prefs.getString('cache_questions_$sid') ?? '[]');
    } catch (_) {}

    final favM = (prefs.getStringList('fav_m_$sid') ?? []).toSet();
    final favQ = (prefs.getStringList('fav_q_$sid') ?? []).toSet();

    Map<String, String> statusMap = {};
    Map<String, int> wrongMap = {};
    try {
      final rawSt = jsonDecode(prefs.getString('q_status_$sid') ?? '{}') as Map<String, dynamic>;
      statusMap = rawSt.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {}
    try {
      final rawWr = jsonDecode(prefs.getString('q_wrong_$sid') ?? '{}') as Map<String, dynamic>;
      wrongMap = rawWr.map((k, v) => MapEntry(k, int.tryParse(v.toString()) ?? 0));
    } catch (_) {}

    final Map<String, String> savedPaths = {};
    if (!kIsWeb) {
      try {
        final rawMap = jsonDecode(prefs.getString('offline_files_map_$sid') ?? '{}') as Map<String, dynamic>;
        for (final entry in rawMap.entries) {
          final p = entry.value.toString();
          if (p.isNotEmpty && File(p).existsSync()) {
            savedPaths[entry.key] = p;
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _materials = cachedMats;
        _questions = cachedQs;
        _favMaterialIds = favM;
        _favQuestionIds = favQ;
        _questionStatus = statusMap;
        _wrongAttempts = wrongMap;
        _localFilePaths = savedPaths;
        _loading = cachedMats.isEmpty && cachedQs.isEmpty;
      });
    }

    try {
      final freshMats = await _client
          .from('materials')
          .select()
          .eq('subject_id', sid)
          .order('lecture_number', ascending: true)
          .order('id', ascending: true);

      final freshQs = await _client
          .from('questions')
          .select()
          .eq('subject_id', sid)
          .order('id', ascending: true);

      await prefs.setString('cache_materials_$sid', jsonEncode(freshMats));
      await prefs.setString('cache_questions_$sid', jsonEncode(freshQs));

      if (!mounted) return;
      setState(() {
        _materials = freshMats;
        _questions = freshQs;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProgressStats() async {
    final prefs = await SharedPreferences.getInstance();
    final sid = _subjectId;
    await prefs.setString('q_status_$sid', jsonEncode(_questionStatus));
    await prefs.setString('q_wrong_$sid', jsonEncode(_wrongAttempts));
  }

  Future<void> _recordQuestionAttempt(String qKey, bool isCorrect) async {
    setState(() {
      if (isCorrect) {
        final prev = _questionStatus[qKey] ?? 'new';
        if (prev == 'correct' || prev == 'mastered') {
          _questionStatus[qKey] = 'mastered';
        } else {
          _questionStatus[qKey] = 'correct';
        }
      } else {
        final wrongs = (_wrongAttempts[qKey] ?? 0) + 1;
        _wrongAttempts[qKey] = wrongs;
        _questionStatus[qKey] = wrongs >= 2 ? 'weak' : 'wrong';
      }
    });
    await _saveProgressStats();
  }

  Future<void> _markQuestionMastered(String qKey, bool mastered) async {
    setState(() {
      _questionStatus[qKey] = mastered ? 'mastered' : 'weak';
    });
    await _saveProgressStats();
  }

  Future<void> _resetSubjectProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final sid = _subjectId;
    setState(() {
      _questionStatus.clear();
      _wrongAttempts.clear();
      _interactiveChosen.clear();
    });
    await prefs.remove('q_status_$sid');
    await prefs.remove('q_wrong_$sid');
  }

  Future<void> _toggleFavMaterial(dynamic matId) async {
    final key = matId.toString();
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favMaterialIds.contains(key)) {
        _favMaterialIds.remove(key);
      } else {
        _favMaterialIds.add(key);
      }
    });
    await prefs.setStringList('fav_m_$_subjectId', _favMaterialIds.toList());
  }

  Future<void> _toggleFavQuestion(dynamic qId) async {
    final key = qId.toString();
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favQuestionIds.contains(key)) {
        _favQuestionIds.remove(key);
      } else {
        _favQuestionIds.add(key);
      }
    });
    await prefs.setStringList('fav_q_$_subjectId', _favQuestionIds.toList());
  }

  String _guessExtension(Map<String, dynamic> mat) {
    final url = (mat['file_url'] ?? '').toString().split('?').first;
    final dotIdx = url.lastIndexOf('.');
    if (dotIdx != -1 && dotIdx < url.length - 1) {
      final ext = url.substring(dotIdx + 1).toLowerCase();
      if (ext.length <= 5) return ext;
    }
    final fType = (mat['file_type'] ?? 'pdf').toString().toLowerCase();
    if (fType == 'audio') return 'mp3';
    if (fType == 'video') return 'mp4';
    if (fType == 'other' || fType == 'أخرى') return 'pdf';
    return fType;
  }

  bool _isImageFile(Map<String, dynamic> mat) {
    final ext = _guessExtension(mat);
    return ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext);
  }

  bool _isMediaFile(Map<String, dynamic> mat) {
    final ext = _guessExtension(mat);
    return ['mp3', 'm4a', 'wav', 'ogg', 'aac', 'mp4', 'mkv', 'mov', 'avi', 'webm'].contains(ext);
  }

  Future<String?> _downloadToLocalCache(Map<String, dynamic> mat) async {
    if (kIsWeb) return null;
    final matKey = (mat['id'] ?? mat['title']).toString();
    if (_localFilePaths.containsKey(matKey) && File(_localFilePaths[matKey]!).existsSync()) {
      return _localFilePaths[matKey];
    }

    final url = (mat['file_url'] ?? '').toString().trim();
    if (url.isEmpty) return null;

    setState(() => _downloadProgress[matKey] = 0.05);

    final httpClient = HttpClient();
    try {
      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final dir = await getApplicationDocumentsDirectory();
      final subjDir = Directory('${dir.path}/materials_$_subjectId');
      if (!subjDir.existsSync()) {
        subjDir.createSync(recursive: true);
      }

      final ext = _guessExtension(mat);
      final safeTitle = (mat['title'] ?? 'file_$matKey')
          .toString()
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .trim();
      final filePath = '${subjDir.path}/${safeTitle}_$matKey.$ext';
      final file = File(filePath);
      final sink = file.openWrite();

      final totalBytes = response.contentLength;
      int received = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (mounted && totalBytes > 0) {
          setState(() {
            _downloadProgress[matKey] = (received / totalBytes).clamp(0.05, 0.99);
          });
        }
      }
      await sink.flush();
      await sink.close();

      final prefs = await SharedPreferences.getInstance();
      _localFilePaths[matKey] = filePath;
      await prefs.setString('offline_files_map_$_subjectId', jsonEncode(_localFilePaths));

      if (mounted) {
        setState(() {
          _downloadProgress.remove(matKey);
        });
      }
      return filePath;
    } catch (_) {
      if (mounted) {
        setState(() => _downloadProgress.remove(matKey));
      }
      return null;
    } finally {
      httpClient.close();
    }
  }

  Future<void> _openMaterialFile(Map<String, dynamic> mat, {bool forceExternal = false}) async {
    final url = (mat['file_url'] ?? '').toString().trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppPrefs.tr('رابط الملف غير متوفر', 'File URL is empty')), backgroundColor: Colors.redAccent),
      );
      return;
    }

    final ext = _guessExtension(mat);
    final title = (mat['title'] ?? '').toString();

    if (forceExternal || kIsWeb) {
      AppLockGuard.isPickingExternalFile = true;
      try {
        final uri = Uri.parse(url);
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched && mounted) {
          await launchUrl(uri, mode: LaunchMode.platformDefault);
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppPrefs.tr('تعذر فتح الرابط خارجياً', 'Could not open URL')), backgroundColor: Colors.redAccent),
          );
        }
      } finally {
        AppLockGuard.isPickingExternalFile = false;
      }
      return;
    }

    final savedPath = await _downloadToLocalCache(mat);
    if (!mounted) return;

    if (_isImageFile(mat)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _InAppImageViewerScreen(
            title: title,
            imageUrl: url,
            localFilePath: savedPath,
            onShareFile: () async {
              final path = savedPath ?? await _downloadToLocalCache(mat);
              if (path != null) {
                AppLockGuard.isPickingExternalFile = true;
                try {
                  await Share.shareXFiles([XFile(path)], text: title);
                } finally {
                  AppLockGuard.isPickingExternalFile = false;
                }
              }
            },
          ),
        ),
      );
      return;
    }

    if (_isMediaFile(mat)) {
      if (savedPath != null && File(savedPath).existsSync()) {
        AppLockGuard.isPickingExternalFile = true;
        try {
          await Share.shareXFiles([XFile(savedPath)], subject: title);
        } finally {
          AppLockGuard.isPickingExternalFile = false;
        }
      } else {
        final uri = Uri.tryParse(url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WpsStyleDocumentViewerScreen(
          title: title,
          extension: ext,
          fileUrl: url,
          localFilePath: savedPath,
          accentColor: widget.defaultColor,
        ),
      ),
    );
  }

  IconData _iconForMaterial(Map<String, dynamic> mat) {
    final ext = _guessExtension(mat);
    if (ext == 'pdf') return Icons.picture_as_pdf_rounded;
    if (['mp3', 'm4a', 'wav', 'audio'].contains(ext)) return Icons.headphones_rounded;
    if (['mp4', 'mkv', 'mov', 'video'].contains(ext)) return Icons.play_circle_fill_rounded;
    if (['jpg', 'jpeg', 'png', 'webp'].contains(ext)) return Icons.image_rounded;
    if (['doc', 'docx'].contains(ext)) return Icons.description_rounded;
    if (['xls', 'xlsx', 'csv'].contains(ext)) return Icons.table_chart_rounded;
    if (['ppt', 'pptx'].contains(ext)) return Icons.slideshow_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _badgeColorForExt(String ext, Color fallback) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return const Color(0xFFE53E3E);
      case 'doc':
      case 'docx':
        return const Color(0xFF2B6CB0);
      case 'xls':
      case 'xlsx':
      case 'csv':
        return const Color(0xFF2F855A);
      case 'ppt':
      case 'pptx':
        return const Color(0xFFDD6B20);
      default:
        return fallback;
    }
  }

  /// نافذة إعدادات وفلترة بنك الأسئلة (الأيقونة الموجودة في أعلى يسار الشريط العلوي)
  void _showQuestionBankSettingsSheet(Color cardBg, Color accent) {
    final lecSet = <String>{'الكل'};
    for (final q in _questions) {
      final ln = (q['lecture_number'] ?? '').toString().trim();
      if (ln.isNotEmpty) lecSet.add(ln);
    }
    final lectures = lecSet.toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppPrefs.tr('إعدادات وفلترة التدريب', 'Training & Filter Settings'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: accent),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: AppPrefs.tr('تحديث البيانات', 'Refresh'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _loadLocalAndSync();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (lectures.length > 1) ...[
                Text(AppPrefs.tr('تصفية حسب المحاضرة:', 'Filter by Lecture:'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: lectures.map((lec) {
                      final sel = _selectedLectureFilter == lec;
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(lec == 'الكل' ? AppPrefs.tr('كل المحاضرات', 'All Lectures') : '${AppPrefs.tr('محاضرة', 'Lecture')} $lec'),
                          selected: sel,
                          selectedColor: accent,
                          labelStyle: TextStyle(color: sel ? Colors.white : null, fontWeight: FontWeight.bold, fontSize: 12),
                          onSelected: (_) {
                            setState(() => _selectedLectureFilter = lec);
                            setSheetState(() {});
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const Divider(height: 22),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(AppPrefs.tr('ترتيب عشوائي للأسئلة', 'Shuffle Questions Order')),
                value: _shuffleQuestions,
                activeColor: accent,
                onChanged: (v) {
                  setState(() => _shuffleQuestions = v);
                  setSheetState(() {});
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(AppPrefs.tr('إظهار التوضيح العلمي فور الإجابة', 'Show Instant Explanation')),
                value: _showInstantExplanation,
                activeColor: accent,
                onChanged: (v) {
                  setState(() => _showInstantExplanation = v);
                  setSheetState(() {});
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: Text(AppPrefs.tr('تصفير إحصائيات التقدم لهذه المادة', 'Reset Subject Progress')),
                  onPressed: () async {
                    await _resetSubjectProgress();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredQuestions {
    final list = _questions.map((e) => Map<String, dynamic>.from(e)).where((q) {
      final qKey = (q['id'] ?? q['question_text']).toString();
      final status = _questionStatus[qKey] ?? 'new';
      final text = (q['question_text'] ?? '').toString().toLowerCase();
      final lec = (q['lecture_number'] ?? '').toString().trim();

      if (_selectedLectureFilter != 'الكل' && lec != _selectedLectureFilter) {
        return false;
      }

      if (_qSearchQuery.isNotEmpty) {
        final clean = _qSearchQuery.replaceAll('#', '').trim();
        final idxMatch = (_questions.indexWhere((item) => item['id'] == q['id']) + 1).toString() == clean;
        if (!text.contains(clean.toLowerCase()) && !idxMatch) {
          return false;
        }
      }

      if (_selectedQFilter == 'جديد') return status == 'new';
      if (_selectedQFilter == 'صحيح') return status == 'correct' || status == 'mastered';
      if (_selectedQFilter == 'متقن') return status == 'mastered';
      if (_selectedQFilter == 'ضعيف') return status == 'weak' || status == 'wrong';
      if (_selectedQFilter == 'خطأ') return status == 'wrong';
      return true;
    }).toList();

    if (_shuffleQuestions) {
      list.shuffle(Random(42));
    }
    return list;
  }

  int get _masteredCount {
    int count = 0;
    for (final q in _questions) {
      final qKey = (q['id'] ?? q['question_text']).toString();
      final st = _questionStatus[qKey];
      if (st == 'mastered' || st == 'correct') count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Theme.of(context).cardColor;
    final accent = widget.defaultColor;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_subjectName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          actions: [
            IconButton(
              tooltip: AppPrefs.tr('إعدادات التدريب والفلترة', 'Training Settings & Filters'),
              icon: Icon(Icons.tune_rounded, color: accent),
              onPressed: () => _showQuestionBankSettingsSheet(cardBg, accent),
            ),
          ],
          bottom: TabBar(
            isScrollable: false,
            indicatorColor: accent,
            labelColor: accent,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            tabs: [
              Tab(text: AppPrefs.tr('التدريب والأسئلة', 'Practice & Quiz')),
              Tab(text: AppPrefs.tr('المحاضرات والملفات', 'Lectures & Files')),
              Tab(text: AppPrefs.tr('نقاط الضعف والإحصاء', 'Weakness & Stats')),
            ],
          ),
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: accent))
            : TabBarView(
                children: [
                  _buildTrainingAndQuestionsTab(cardBg, accent),
                  _buildMaterialsTab(cardBg, accent),
                  _buildWeaknessAndStatsTab(cardBg, accent),
                ],
              ),
      ),
    );
  }

  /// =========================================================================
  /// التبويب الأول: التدريب والأسئلة (إتقان المادة + الأنماط الأربعة + بنك الأسئلة)
  /// =========================================================================
  Widget _buildTrainingAndQuestionsTab(Color cardBg, Color accent) {
    final totalQs = _questions.length;
    final mastered = _masteredCount;
    final masteryPct = totalQs > 0 ? ((mastered / totalQs) * 100).round() : 0;

    int weakCount = 0;
    for (final q in _questions) {
      final k = (q['id'] ?? q['question_text']).toString();
      if (_questionStatus[k] == 'weak' || _questionStatus[k] == 'wrong') weakCount++;
    }

    final filterChips = [
      {'key': 'الكل', 'label': AppPrefs.tr('الكل', 'All')},
      {'key': 'جديد', 'label': AppPrefs.tr('جديد', 'New')},
      {'key': 'صحيح', 'label': AppPrefs.tr('صحيح', 'Correct')},
      {'key': 'متقن', 'label': AppPrefs.tr('متقن', 'Mastered')},
      {'key': 'ضعيف', 'label': '${AppPrefs.tr('ضعيف', 'Weak')} ($weakCount)'},
      {'key': 'خطأ', 'label': AppPrefs.tr('خطأ', 'Wrong')},
    ];

    final visibleQuestions = _filteredQuestions;

    return RefreshIndicator(
      onRefresh: _loadLocalAndSync,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. بطاقة إتقان المادة
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${AppPrefs.tr('إتقان المادة:', 'Subject Mastery:')} $masteryPct%',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      '$mastered / $totalQs ${AppPrefs.tr('سؤال', 'questions')}',
                      style: const TextStyle(fontSize: 12.5, color: Colors.grey, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: totalQs > 0 ? (mastered / totalQs).clamp(0.0, 1.0) : 0.0,
                    minHeight: 7,
                    backgroundColor: Colors.grey.withOpacity(0.2),
                    color: accent,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 2. شبكة أنماط التدريب الأربعة (البطاقات السريعة، التدريب التفاعلي، الاختبار المحاكي، وضع الحفظ)
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.48,
            children: [
              _studyModeCard(
                cardBg: cardBg,
                icon: Icons.style_rounded,
                iconColor: Colors.amber,
                title: AppPrefs.tr('البطاقات السريعة', 'Flashcards'),
                subtitle: AppPrefs.tr('اقلب البطاقة وقيّم حفظك', 'Flip & rate recall'),
                onTap: () => _launchStudyMode('flashcards', accent),
              ),
              _studyModeCard(
                cardBg: cardBg,
                icon: Icons.fact_check_rounded,
                iconColor: accent,
                title: AppPrefs.tr('التدريب التفاعلي', 'Interactive Quiz'),
                subtitle: AppPrefs.tr('حل مع التوضيح الفوري', 'Solve with instant hints'),
                onTap: () => _launchStudyMode('interactive', accent),
              ),
              _studyModeCard(
                cardBg: cardBg,
                icon: Icons.timer_rounded,
                iconColor: Colors.tealAccent.shade700,
                title: AppPrefs.tr('الاختبار المحاكي', 'Mock Exam'),
                subtitle: AppPrefs.tr('اختبار عشوائي بمؤقت زمني', 'Timed random exam'),
                onTap: () => _launchStudyMode('mock_exam', accent),
              ),
              _studyModeCard(
                cardBg: cardBg,
                icon: Icons.menu_book_rounded,
                iconColor: Colors.blueAccent,
                title: AppPrefs.tr('وضع الحفظ', 'Memorization Mode'),
                subtitle: AppPrefs.tr('تصفح السؤال مع إظهار الجواب', 'Browse Q&A directly'),
                onTap: () => _launchStudyMode('memorize', accent),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // 3. عنوان بنك الأسئلة وشريط البحث والفلاتر
          Text(
            '${AppPrefs.tr('بنك الأسئلة', 'Question Bank')} ($totalQs)',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5),
          ),
          const SizedBox(height: 10),
          TextField(
            onChanged: (v) => setState(() => _qSearchQuery = v.trim()),
            decoration: InputDecoration(
              hintText: AppPrefs.tr('ابحث بكلمة أو رقم السؤال (مثلاً #15)...', 'Search keyword or #15...'),
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              filled: true,
              fillColor: cardBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: filterChips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, idx) {
                final chip = filterChips[idx];
                final isSel = _selectedQFilter == chip['key'];
                return ChoiceChip(
                  label: Text(
                    chip['label']!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSel ? Colors.white : null,
                    ),
                  ),
                  selected: isSel,
                  selectedColor: accent,
                  onSelected: (_) => setState(() => _selectedQFilter = chip['key']!),
                );
              },
            ),
          ),
          const SizedBox(height: 14),

          if (visibleQuestions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  totalQs == 0
                      ? AppPrefs.tr(
                          'لا توجد أسئلة مضافة لهذه المادة حتى الآن.\nسيتم تحديثها تلقائياً فور إضافتها من الإدارة.',
                          'No questions added for this subject yet.\nIt will update automatically once added.',
                        )
                      : AppPrefs.tr('لا توجد أسئلة مطابقة للفلتر الحالي.', 'No questions match current filter.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13.5, height: 1.6),
                ),
              ),
            )
          else
            ...List.generate(visibleQuestions.length, (idx) {
              final q = visibleQuestions[idx];
              final qKey = (q['id'] ?? q['question_text']).toString();
              final isFav = _favQuestionIds.contains(qKey);
              final List<dynamic> opts = q['options'] is String ? jsonDecode(q['options']) : (q['options'] ?? []);
              final int correctIdx = q['correct_index'] ?? 0;
              final int? chosenIdx = _interactiveChosen[qKey];
              final explanation = (q['explanation'] ?? '').toString().trim();
              final st = _questionStatus[qKey] ?? 'new';

              return Card(
                color: cardBg,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppPrefs.cardRadius)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('#${idx + 1}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: accent)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              (q['question_text'] ?? '').toString(),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, height: 1.4),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              isFav ? Icons.star_rounded : Icons.star_border_rounded,
                              color: isFav ? Colors.amber : Colors.grey,
                            ),
                            onPressed: () => _toggleFavQuestion(qKey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(opts.length, (oIdx) {
                        final isChosen = chosenIdx == oIdx;
                        final isRight = oIdx == correctIdx;
                        final showResult = chosenIdx != null;
                        Color? tileColor;
                        if (showResult) {
                          if (isRight) {
                            tileColor = Colors.green.withOpacity(0.18);
                          } else if (isChosen && !isRight) {
                            tileColor = Colors.redAccent.withOpacity(0.18);
                          }
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: tileColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: showResult && isRight
                                  ? Colors.green
                                  : (isChosen ? Colors.redAccent : Colors.grey.withOpacity(0.25)),
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            leading: Icon(
                              showResult
                                  ? (isRight
                                      ? Icons.check_circle_rounded
                                      : (isChosen ? Icons.cancel_rounded : Icons.radio_button_unchecked_rounded))
                                  : Icons.radio_button_unchecked_rounded,
                              size: 20,
                              color: showResult && isRight
                                  ? Colors.green
                                  : (isChosen ? Colors.redAccent : Colors.grey),
                            ),
                            title: Text(opts[oIdx].toString(), style: const TextStyle(fontSize: 13.5)),
                            onTap: () {
                              setState(() => _interactiveChosen[qKey] = oIdx);
                              _recordQuestionAttempt(qKey, oIdx == correctIdx);
                            },
                          ),
                        );
                      }),
                      if (chosenIdx != null && _showInstantExplanation && explanation.isNotEmpty)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('💡 ${AppPrefs.tr('التوضيح:', 'Explanation:')} $explanation', style: const TextStyle(fontSize: 12.5)),
                        ),
                      if (st != 'new')
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                st == 'mastered'
                                    ? AppPrefs.tr('متقن ✓✓', 'Mastered ✓✓')
                                    : (st == 'correct'
                                        ? AppPrefs.tr('إجابة صحيحة ✓', 'Correct ✓')
                                        : AppPrefs.tr('يحتاج مراجعة ⚠️', 'Needs Review ⚠️')),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: (st == 'mastered' || st == 'correct') ? Colors.green : Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _studyModeCard({
    required Color cardBg,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.withOpacity(0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
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

  void _launchStudyMode(String mode, Color accent) {
    final list = _filteredQuestions.isNotEmpty
        ? _filteredQuestions
        : _questions.map((e) => Map<String, dynamic>.from(e)).toList();

    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppPrefs.tr('لا توجد أسئلة متاحة في هذه المادة لبدء التدريب', 'No questions available in this subject yet')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SubjectStudySessionScreen(
          subjectName: _subjectName,
          mode: mode,
          questions: list,
          accentColor: accent,
          onQuestionEvaluated: (qKey, isCorrect) => _recordQuestionAttempt(qKey, isCorrect),
          onToggleMastered: (qKey, mastered) => _markQuestionMastered(qKey, mastered),
        ),
      ),
    );
  }

  /// =========================================================================
  /// التبويب الثاني: المحاضرات والملفات (مع عارض المستندات الداخلي والتكبير بالأصابع)
  /// =========================================================================
  Widget _buildMaterialsTab(Color cardBg, Color accent) {
    final filters = ['الكل', 'PDF', 'WORD', 'EXCEL', 'PPT', 'AUDIO', 'VIDEO', 'صور'];

    final filtered = _materials.where((item) {
      final m = Map<String, dynamic>.from(item);
      final title = (m['title'] ?? '').toString().toLowerCase();
      final ext = _guessExtension(m);
      final fType = (m['file_type'] ?? '').toString().toUpperCase();

      if (_matSearchQuery.isNotEmpty && !title.contains(_matSearchQuery.toLowerCase())) {
        return false;
      }

      if (_selectedMatFilter == 'PDF') return ext == 'pdf' || fType == 'PDF';
      if (_selectedMatFilter == 'WORD') return ['doc', 'docx'].contains(ext) || fType == 'DOCX';
      if (_selectedMatFilter == 'EXCEL') return ['xls', 'xlsx', 'csv'].contains(ext) || fType == 'XLSX';
      if (_selectedMatFilter == 'PPT') return ['ppt', 'pptx'].contains(ext) || fType == 'PPTX';
      if (_selectedMatFilter == 'AUDIO') return ['mp3', 'm4a', 'wav'].contains(ext) || fType == 'AUDIO' || fType == 'MP3';
      if (_selectedMatFilter == 'VIDEO') return ['mp4', 'mkv', 'mov'].contains(ext) || fType == 'VIDEO' || fType == 'MP4';
      if (_selectedMatFilter == 'صور') return ['jpg', 'jpeg', 'png', 'webp'].contains(ext) || fType == 'JPG';
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadLocalAndSync,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            onChanged: (v) => setState(() => _matSearchQuery = v.trim()),
            decoration: InputDecoration(
              hintText: AppPrefs.tr('ابحث في محاضرات وملفات المادة...', 'Search subject files...'),
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final f = filters[i];
                final sel = _selectedMatFilter == f;
                return ChoiceChip(
                  label: Text(f, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: sel ? Colors.white : null)),
                  selected: sel,
                  selectedColor: accent,
                  onSelected: (_) => setState(() => _selectedMatFilter = f),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  AppPrefs.tr('لا توجد ملفات مضافة لهذه المادة حالياً.', 'No files added for this subject yet.'),
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ),
            )
          else
            ...filtered.map((raw) {
              final mat = Map<String, dynamic>.from(raw);
              final matId = (mat['id'] ?? mat['title']).toString();
              final isFav = _favMaterialIds.contains(matId);
              final isOfflineSaved = _localFilePaths.containsKey(matId);
              final progress = _downloadProgress[matId];
              final ext = _guessExtension(mat);
              final extLabel = ext.toUpperCase();
              final badgeColor = _badgeColorForExt(ext, accent);
              final lecNum = (mat['lecture_number'] ?? 1).toString();

              return Card(
                color: cardBg,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppPrefs.cardRadius),
                  side: BorderSide(color: Colors.grey.withOpacity(0.2)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppPrefs.cardRadius),
                  onTap: progress != null ? null : () => _openMaterialFile(mat),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: badgeColor.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(_iconForMaterial(mat), color: badgeColor, size: 28),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (mat['title'] ?? '').toString(),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, height: 1.3),
                                  ),
                                  const SizedBox(height: 5),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: accent.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'محاضرة $lecNum',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accent),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: badgeColor.withOpacity(0.16),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          extLabel,
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor),
                                        ),
                                      ),
                                      if (isOfflineSaved)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withOpacity(0.16),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'محفوظ أوفلاين ✓',
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: AppPrefs.tr('إضافة لحقيبة المراجعة', 'Bookmark for Exam Review'),
                              icon: Icon(
                                isFav ? Icons.star_rounded : Icons.star_border_rounded,
                                color: isFav ? Colors.amber : Colors.grey,
                              ),
                              onPressed: () => _toggleFavMaterial(matId),
                            ),
                          ],
                        ),
                        if (progress != null) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(value: progress, minHeight: 6, color: badgeColor),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('${(progress * 100).round()}%', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: badgeColor)),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: badgeColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.auto_stories_rounded, size: 18),
                                label: Text(
                                  _isImageFile(mat)
                                      ? AppPrefs.tr('عرض الصورة', 'View Image')
                                      : (_isMediaFile(mat)
                                          ? AppPrefs.tr('تشغيل الملف', 'Play Media')
                                          : AppPrefs.tr('فتح المستند في العارض', 'Open in Doc Viewer')),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                onPressed: progress != null ? null : () => _openMaterialFile(mat),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.open_in_new_rounded, size: 17),
                              label: Text(AppPrefs.tr('خارجي', 'External'), style: const TextStyle(fontSize: 12)),
                              onPressed: () => _openMaterialFile(mat, forceExternal: true),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  /// =========================================================================
  /// التبويب الثالث: نقاط الضعف والإحصاء
  /// =========================================================================
  Widget _buildWeaknessAndStatsTab(Color cardBg, Color accent) {
    final total = _questions.length;
    int mastered = 0;
    int correct = 0;
    int weak = 0;
    int untouched = 0;

    final List<Map<String, dynamic>> weakQuestions = [];

    for (final raw in _questions) {
      final q = Map<String, dynamic>.from(raw);
      final key = (q['id'] ?? q['question_text']).toString();
      final st = _questionStatus[key] ?? 'new';
      if (st == 'mastered') {
        mastered++;
      } else if (st == 'correct') {
        correct++;
      } else if (st == 'weak' || st == 'wrong') {
        weak++;
        weakQuestions.add(q);
      } else {
        untouched++;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppPrefs.tr('ملخص الأداء والإحصاء في المادة', 'Performance & Statistics Summary'),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: accent),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _statTile(AppPrefs.tr('إجمالي الأسئلة', 'Total'), '$total', Colors.blueAccent)),
                    const SizedBox(width: 8),
                    Expanded(child: _statTile(AppPrefs.tr('متقن', 'Mastered'), '$mastered', Colors.green)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _statTile(AppPrefs.tr('إجابات صحيحة', 'Correct'), '$correct', Colors.teal)),
                    const SizedBox(width: 8),
                    Expanded(child: _statTile(AppPrefs.tr('نقاط الضعف', 'Weak'), '$weak', Colors.redAccent)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _statTile(AppPrefs.tr('أسئلة جديدة لم تُحل', 'Unanswered'), '$untouched', Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (weakQuestions.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${AppPrefs.tr('الأسئلة التي تحتاج مراجعة', 'Weak Questions to Review')} (${weakQuestions.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(AppPrefs.tr('تدريب عليها الآن', 'Practice Weak')),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _SubjectStudySessionScreen(
                        subjectName: _subjectName,
                        mode: 'interactive',
                        questions: weakQuestions,
                        accentColor: accent,
                        onQuestionEvaluated: (qKey, isCorrect) => _recordQuestionAttempt(qKey, isCorrect),
                        onToggleMastered: (qKey, m) => _markQuestionMastered(qKey, m),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...weakQuestions.map((q) {
            final qKey = (q['id'] ?? q['question_text']).toString();
            final List<dynamic> opts = q['options'] is String ? jsonDecode(q['options']) : (q['options'] ?? []);
            final int cIdx = q['correct_index'] ?? 0;
            final ans = (cIdx >= 0 && cIdx < opts.length) ? opts[cIdx].toString() : '';

            return Card(
              color: cardBg,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.redAccent.withOpacity(0.35)),
              ),
              child: ListTile(
                title: Text((q['question_text'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('✅ $ans', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12.5)),
                ),
                trailing: IconButton(
                  tooltip: AppPrefs.tr('تحديد كمتقن', 'Mark Mastered'),
                  icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.green),
                  onPressed: () => _markQuestionMastered(qKey, true),
                ),
              ),
            );
          }),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                AppPrefs.tr('لا توجد نقاط ضعف مسجلة حالياً! استمر في التدريب 💪', 'No weak questions recorded yet! Keep practicing 💪'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ),
          ),
      ],
    );
  }

  Widget _statTile(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          Text(val, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// ============================================================================
/// شاشة جلسات التدريب الأربعة:
/// 1. البطاقات السريعة (flashcards)
/// 2. التدريب التفاعلي (interactive)
/// 3. الاختبار المحاكي بمؤقت زمني (mock_exam)
/// 4. وضع الحفظ (memorize)
/// ============================================================================
class _SubjectStudySessionScreen extends StatefulWidget {
  final String subjectName;
  final String mode;
  final List<Map<String, dynamic>> questions;
  final Color accentColor;
  final Future<void> Function(String qKey, bool isCorrect) onQuestionEvaluated;
  final Future<void> Function(String qKey, bool mastered) onToggleMastered;

  const _SubjectStudySessionScreen({
    required this.subjectName,
    required this.mode,
    required this.questions,
    required this.accentColor,
    required this.onQuestionEvaluated,
    required this.onToggleMastered,
  });

  @override
  State<_SubjectStudySessionScreen> createState() => _SubjectStudySessionScreenState();
}

class _SubjectStudySessionScreenState extends State<_SubjectStudySessionScreen> {
  late List<Map<String, dynamic>> _sessionQuestions;
  int _currentIndex = 0;
  bool _cardFlipped = false;
  int? _chosenOption;
  int _score = 0;
  bool _finished = false;

  Timer? _examTimer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    _sessionQuestions = List<Map<String, dynamic>>.from(widget.questions);
    if (widget.mode == 'mock_exam') {
      _sessionQuestions.shuffle();
      if (_sessionQuestions.length > 20) {
        _sessionQuestions = _sessionQuestions.take(20).toList();
      }
      _secondsLeft = _sessionQuestions.length * 45;
      _examTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_secondsLeft <= 1) {
          _examTimer?.cancel();
          setState(() {
            _secondsLeft = 0;
            _finished = true;
          });
        } else {
          setState(() => _secondsLeft--);
        }
      });
    }
  }

  @override
  void dispose() {
    _examTimer?.cancel();
    super.dispose();
  }

  String get _modeTitle {
    switch (widget.mode) {
      case 'flashcards':
        return AppPrefs.tr('البطاقات السريعة', 'Flashcards');
      case 'mock_exam':
        return AppPrefs.tr('الاختبار المحاكي', 'Mock Exam');
      case 'memorize':
        return AppPrefs.tr('وضع الحفظ', 'Memorization Mode');
      default:
        return AppPrefs.tr('التدريب التفاعلي', 'Interactive Quiz');
    }
  }

  String _formatTime(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _nextItem() {
    if (_currentIndex + 1 >= _sessionQuestions.length) {
      _examTimer?.cancel();
      setState(() => _finished = true);
    } else {
      setState(() {
        _currentIndex++;
        _cardFlipped = false;
        _chosenOption = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Theme.of(context).cardColor;
    final accent = widget.accentColor;

    if (_finished) {
      final total = _sessionQuestions.length;
      final pct = total > 0 ? ((_score / total) * 100).round() : 0;
      return Scaffold(
        appBar: AppBar(title: Text(_modeTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              color: cardBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.emoji_events_rounded, size: 64, color: accent),
                    const SizedBox(height: 14),
                    Text(AppPrefs.tr('اكتملت الجلسة التدريبية!', 'Session Completed!'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text(
                      '${AppPrefs.tr('النتيجة:', 'Score:')} $_score / $total ($pct%)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: accent),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
                        onPressed: () => Navigator.pop(context),
                        child: Text(AppPrefs.tr('العودة للمادة', 'Back to Subject'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final q = _sessionQuestions[_currentIndex];
    final qKey = (q['id'] ?? q['question_text']).toString();
    final List<dynamic> opts = q['options'] is String ? jsonDecode(q['options']) : (q['options'] ?? []);
    final int correctIdx = q['correct_index'] ?? 0;
    final String correctAnswer = (correctIdx >= 0 && correctIdx < opts.length) ? opts[correctIdx].toString() : '';
    final String explanation = (q['explanation'] ?? '').toString().trim();

    return Scaffold(
      appBar: AppBar(
        title: Text('$_modeTitle (${_currentIndex + 1}/${_sessionQuestions.length})', style: const TextStyle(fontSize: 16)),
        actions: [
          if (widget.mode == 'mock_exam')
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Chip(
                  backgroundColor: Colors.redAccent.withOpacity(0.16),
                  label: Text(_formatTime(_secondsLeft), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            LinearProgressIndicator(
              value: (_currentIndex + 1) / _sessionQuestions.length,
              color: accent,
              minHeight: 6,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: widget.mode == 'flashcards'
                  ? _buildFlashcardBody(cardBg, accent, q, qKey, correctAnswer, explanation)
                  : _buildQuizOrMemorizeBody(cardBg, accent, q, qKey, opts, correctIdx, explanation),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlashcardBody(
    Color cardBg,
    Color accent,
    Map<String, dynamic> q,
    String qKey,
    String correctAnswer,
    String explanation,
  ) {
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _cardFlipped = !_cardFlipped),
            child: Card(
              color: cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: BorderSide(color: accent.withOpacity(0.45), width: 1.5),
              ),
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(
                        backgroundColor: accent.withOpacity(0.15),
                        label: Text(
                          _cardFlipped ? AppPrefs.tr('الإجابة', 'Answer') : AppPrefs.tr('السؤال (اضغط لقلب البطاقة)', 'Question (Tap to flip)'),
                          style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _cardFlipped ? '✅ $correctAnswer' : (q['question_text'] ?? '').toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: _cardFlipped ? 19 : 17,
                          fontWeight: FontWeight.bold,
                          color: _cardFlipped ? Colors.green : null,
                          height: 1.5,
                        ),
                      ),
                      if (_cardFlipped && explanation.isNotEmpty) ...[
                        const Divider(height: 28),
                        Text('💡 $explanation', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, color: Colors.grey)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (!_cardFlipped)
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
              icon: const Icon(Icons.flip_rounded),
              label: Text(AppPrefs.tr('إظهار الإجابة', 'Show Answer'), style: const TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => setState(() => _cardFlipped = true),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                  icon: const Icon(Icons.close_rounded),
                  label: Text(AppPrefs.tr('لم أتذكرها (ضعيف)', 'Forgot (Weak)'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    await widget.onToggleMastered(qKey, false);
                    _nextItem();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(AppPrefs.tr('تذكرتها (متقن)', 'Recalled (Mastered)'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    _score++;
                    await widget.onToggleMastered(qKey, true);
                    _nextItem();
                  },
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildQuizOrMemorizeBody(
    Color cardBg,
    Color accent,
    Map<String, dynamic> q,
    String qKey,
    List<dynamic> opts,
    int correctIdx,
    String explanation,
  ) {
    final isMemorize = widget.mode == 'memorize';

    return ListView(
      children: [
        Card(
          color: cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              (q['question_text'] ?? '').toString(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(opts.length, (oIdx) {
          final isRight = oIdx == correctIdx;
          final isChosen = _chosenOption == oIdx;
          final reveal = isMemorize || _chosenOption != null;

          Color? bg;
          if (reveal) {
            if (isRight) {
              bg = Colors.green.withOpacity(0.18);
            } else if (isChosen) {
              bg = Colors.redAccent.withOpacity(0.18);
            }
          }

          return Card(
            color: bg ?? cardBg,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: reveal && isRight ? Colors.green : (isChosen ? Colors.redAccent : Colors.grey.withOpacity(0.25)),
              ),
            ),
            child: ListTile(
              title: Text(opts[oIdx].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: reveal && isRight ? const Icon(Icons.check_circle_rounded, color: Colors.green) : null,
              onTap: (isMemorize || _chosenOption != null)
                  ? null
                  : () async {
                      final right = oIdx == correctIdx;
                      setState(() {
                        _chosenOption = oIdx;
                        if (right) _score++;
                      });
                      await widget.onQuestionEvaluated(qKey, right);
                    },
            ),
          );
        }),
        if ((isMemorize || _chosenOption != null) && explanation.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('💡 $explanation', style: const TextStyle(fontSize: 13)),
          ),
        const SizedBox(height: 16),
        if (isMemorize || _chosenOption != null)
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(
                _currentIndex + 1 >= _sessionQuestions.length
                    ? AppPrefs.tr('إنهاء وعرض النتيجة', 'Finish & Show Score')
                    : AppPrefs.tr('السؤال التالي', 'Next Question'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                if (isMemorize) _score++;
                _nextItem();
              },
            ),
          ),
      ],
    );
  }
}

/// ============================================================================
/// عارض المستندات المتكامل شبيه تطبيق WPS Office
/// - يعرض صفحات أي ملف PDF (مصوّر أو نصي) كصفحات حقيقية عالية الدقة عبر Printing.raster
/// - يدعم التكبير والتصغير التلقائي بالأصابع (InteractiveViewer) لأي نوع ملف
/// ============================================================================
class WpsStyleDocumentViewerScreen extends StatefulWidget {
  final String title;
  final String extension;
  final String fileUrl;
  final String? localFilePath;
  final Color accentColor;

  const WpsStyleDocumentViewerScreen({
    super.key,
    required this.title,
    required this.extension,
    required this.fileUrl,
    this.localFilePath,
    required this.accentColor,
  });

  @override
  State<WpsStyleDocumentViewerScreen> createState() => _WpsStyleDocumentViewerScreenState();
}

class _WpsStyleDocumentViewerScreenState extends State<WpsStyleDocumentViewerScreen> {
  bool _parsing = true;
  String _readingMode = 'paper';
  double _fontSize = 15.5;
  bool _showSearchBar = false;
  String _docSearchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  final TransformationController _zoomCtrl = TransformationController();

  List<String> _paragraphs = [];
  List<List<String>> _sheetRows = [];
  List<Map<String, dynamic>> _slides = [];
  List<Uint8List> _renderedPdfPages = [];
  String _fileSizeLabel = '';
  String _docCategory = 'DOC';

  @override
  void initState() {
    super.initState();
    _loadAndParseDocument();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _zoomCtrl.dispose();
    super.dispose();
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _loadAndParseDocument() async {
    final ext = widget.extension.toLowerCase().trim();
    Uint8List? bytes;

    if (widget.localFilePath != null && !kIsWeb && File(widget.localFilePath!).existsSync()) {
      bytes = await File(widget.localFilePath!).readAsBytes();
    } else if (widget.fileUrl.isNotEmpty) {
      try {
        final client = HttpClient();
        final req = await client.getUrl(Uri.parse(widget.fileUrl));
        final resp = await req.close();
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          final builder = BytesBuilder(copy: false);
          await for (final chunk in resp) {
            builder.add(chunk);
          }
          bytes = builder.takeBytes();
        }
        client.close();
      } catch (_) {}
    }

    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        setState(() {
          _parsing = false;
          _docCategory = ext.toUpperCase();
          _paragraphs = ['تعذر تحميل محتوى المستند للمعاينة الداخلية. يمكنك فتحه عبر الأزرار بالأسفل.'];
        });
      }
      return;
    }

    _fileSizeLabel = _formatSize(bytes.length);

    try {
      if (ext == 'docx') {
        _docCategory = 'DOCX';
        final entries = _PureDartZipReader.extractEntries(bytes);
        final docXml = entries['word/document.xml'];
        if (docXml != null) {
          final xmlStr = utf8.decode(docXml, allowMalformed: true);
          _paragraphs = _extractWordParagraphs(xmlStr);
        }
      } else if (ext == 'pptx') {
        _docCategory = 'PPTX';
        final entries = _PureDartZipReader.extractEntries(bytes);
        final slideKeys = entries.keys
            .where((k) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(k))
            .toList()
          ..sort((a, b) {
            final na = int.tryParse(RegExp(r'\d+').firstMatch(a)?.group(0) ?? '0') ?? 0;
            final nb = int.tryParse(RegExp(r'\d+').firstMatch(b)?.group(0) ?? '0') ?? 0;
            return na.compareTo(nb);
          });
        int slideIdx = 1;
        for (final key in slideKeys) {
          final xmlStr = utf8.decode(entries[key]!, allowMalformed: true);
          final lines = _extractXmlTextLines(xmlStr, tag: 'a:p');
          _slides.add({
            'number': slideIdx++,
            'lines': lines.isEmpty ? ['(شريحة مرئية بدون نص)'] : lines,
          });
        }
      } else if (ext == 'xlsx') {
        _docCategory = 'XLSX';
        final entries = _PureDartZipReader.extractEntries(bytes);
        final List<String> sharedStrings = [];
        if (entries.containsKey('xl/sharedStrings.xml')) {
          final ssXml = utf8.decode(entries['xl/sharedStrings.xml']!, allowMalformed: true);
          sharedStrings.addAll(_extractXmlTextLines(ssXml, tag: 'si'));
        }
        final sheetKeys = entries.keys
            .where((k) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(k))
            .toList()
          ..sort();
        if (sheetKeys.isNotEmpty) {
          final sheetXml = utf8.decode(entries[sheetKeys.first]!, allowMalformed: true);
          _sheetRows = _extractExcelRows(sheetXml, sharedStrings);
        }
      } else if (ext == 'csv') {
        _docCategory = 'XLSX';
        final text = utf8.decode(bytes, allowMalformed: true);
        _sheetRows = text
            .split(RegExp(r'\r?\n'))
            .where((l) => l.trim().isNotEmpty)
            .map((l) => l.split(',').map((c) => c.trim()).toList())
            .toList();
      } else if (ext == 'pdf') {
        _docCategory = 'PDF';
        _paragraphs = _extractPdfReadableText(bytes);
        // رسم صفحات ملف PDF الفعلية عالية الدقة عبر محرك Printing.raster
        try {
          final List<Uint8List> pagePngs = [];
          await for (final rasterPage in Printing.raster(bytes, dpi: 144)) {
            final pngBytes = await rasterPage.toPng();
            pagePngs.add(pngBytes);
            if (pagePngs.length >= 40) break;
          }
          _renderedPdfPages = pagePngs;
        } catch (_) {}
      } else {
        _docCategory = 'TEXT';
        final rawText = utf8.decode(bytes, allowMalformed: true);
        _paragraphs = rawText
            .split(RegExp(r'\r?\n'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _parsing = false);
    }
  }

  String _decodeXmlEntities(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#10;', '\n')
        .replaceAll('&#13;', '');
  }

  List<String> _extractWordParagraphs(String xml) {
    final List<String> out = [];
    final pMatches = RegExp(r'<w:p[\s>].*?</w:p>', dotAll: true).allMatches(xml);
    for (final pm in pMatches) {
      final pContent = pm.group(0) ?? '';
      final tMatches = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true).allMatches(pContent);
      final buf = StringBuffer();
      for (final tm in tMatches) {
        buf.write(_decodeXmlEntities(tm.group(1) ?? ''));
      }
      final line = buf.toString().trim();
      if (line.isNotEmpty) out.add(line);
    }
    return out;
  }

  List<String> _extractXmlTextLines(String xml, {required String tag}) {
    final List<String> out = [];
    final blockMatches = RegExp('<$tag[\\s>].*?</$tag>', dotAll: true).allMatches(xml);
    for (final bm in blockMatches) {
      final block = bm.group(0) ?? '';
      final stripped = _decodeXmlEntities(block.replaceAll(RegExp(r'<[^>]+>'), ' '))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (stripped.isNotEmpty) out.add(stripped);
    }
    return out;
  }

  List<List<String>> _extractExcelRows(String sheetXml, List<String> sharedStrings) {
    final List<List<String>> rows = [];
    final rowMatches = RegExp(r'<row[^>]*>(.*?)</row>', dotAll: true).allMatches(sheetXml);
    for (final rm in rowMatches) {
      final rowBody = rm.group(1) ?? '';
      final List<String> cells = [];
      final cellMatches = RegExp(r'<c([^>]*)>(.*?)</c>', dotAll: true).allMatches(rowBody);
      for (final cm in cellMatches) {
        final attrs = cm.group(1) ?? '';
        final inner = cm.group(2) ?? '';
        final isShared = attrs.contains('t="s"');
        final valMatch = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(inner);
        final inlineMatch = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).firstMatch(inner);
        if (inlineMatch != null) {
          cells.add(_decodeXmlEntities(inlineMatch.group(1) ?? ''));
        } else if (valMatch != null) {
          final rawVal = valMatch.group(1) ?? '';
          if (isShared) {
            final idx = int.tryParse(rawVal) ?? -1;
            cells.add(idx >= 0 && idx < sharedStrings.length ? sharedStrings[idx] : rawVal);
          } else {
            cells.add(rawVal);
          }
        } else {
          cells.add('');
        }
      }
      if (cells.any((c) => c.trim().isNotEmpty)) {
        rows.add(cells);
      }
    }
    return rows;
  }

  List<String> _extractPdfReadableText(Uint8List bytes) {
    final List<String> extracted = [];
    final rawLatin = latin1.decode(bytes, allowInvalid: true);
    final streamMatches = RegExp(r'stream\r?\n(.*?)\r?\nendstream', dotAll: true).allMatches(rawLatin);

    for (final sm in streamMatches) {
      final streamStr = sm.group(1);
      if (streamStr == null || streamStr.isEmpty) continue;
      final streamBytes = latin1.encode(streamStr);
      String decodedChunk = '';
      try {
        final inflated = zlib.decode(streamBytes);
        decodedChunk = utf8.decode(inflated, allowMalformed: true);
      } catch (_) {
        decodedChunk = streamStr;
      }

      final tjMatches = RegExp(r'\(([^()\\]{2,})\)\s*Tj').allMatches(decodedChunk);
      final buf = StringBuffer();
      for (final m in tjMatches) {
        final txt = (m.group(1) ?? '').trim();
        if (txt.isNotEmpty) {
          buf.write('$txt ');
        }
      }
      final line = buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (line.length > 3) {
        extracted.add(line);
      }
    }
    return extracted;
  }

  Future<void> _openInDeviceWpsOrPdfApp() async {
    AppLockGuard.isPickingExternalFile = true;
    try {
      if (widget.localFilePath != null && !kIsWeb && File(widget.localFilePath!).existsSync()) {
        await Share.shareXFiles([XFile(widget.localFilePath!)], subject: widget.title);
      } else {
        final uri = Uri.tryParse(widget.fileUrl);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } finally {
      AppLockGuard.isPickingExternalFile = false;
    }
  }

  Future<void> _openInOnlineOfficeViewer() async {
    AppLockGuard.isPickingExternalFile = true;
    try {
      final encoded = Uri.encodeComponent(widget.fileUrl);
      final viewerUrl = 'https://docs.google.com/gview?embedded=true&url=$encoded';
      await launchUrl(Uri.parse(viewerUrl), mode: LaunchMode.externalApplication);
    } finally {
      AppLockGuard.isPickingExternalFile = false;
    }
  }

  void _resetZoom() {
    _zoomCtrl.value = Matrix4.identity();
  }

  Color get _pageBackgroundColor {
    switch (_readingMode) {
      case 'sepia':
        return const Color(0xFFF6EEDB);
      case 'night':
        return const Color(0xFF12151C);
      default:
        return const Color(0xFFFFFFFF);
    }
  }

  Color get _canvasBackgroundColor {
    switch (_readingMode) {
      case 'sepia':
        return const Color(0xFFE7DEC8);
      case 'night':
        return const Color(0xFF0A0C10);
      default:
        return const Color(0xFFE2E8F0);
    }
  }

  Color get _pageTextColor {
    switch (_readingMode) {
      case 'sepia':
        return const Color(0xFF3E2F1C);
      case 'night':
        return const Color(0xFFE2E8F0);
      default:
        return const Color(0xFF1E293B);
    }
  }

  Color get _brandHeaderColor {
    switch (_docCategory) {
      case 'PDF':
        return const Color(0xFFC53030);
      case 'DOCX':
        return const Color(0xFF2B6CB0);
      case 'XLSX':
        return const Color(0xFF276749);
      case 'PPTX':
        return const Color(0xFFC05621);
      default:
        return widget.accentColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final headerBg = _brandHeaderColor;

    return Scaffold(
      backgroundColor: _canvasBackgroundColor,
      appBar: AppBar(
        backgroundColor: headerBg,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            Text(
              'WPS Reader • $_docCategory${_fileSizeLabel.isNotEmpty ? ' • $_fileSizeLabel' : ''} • محفوظ أوفلاين ✓',
              style: const TextStyle(fontSize: 10.5, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'إعادة ضبط التكبير',
            icon: const Icon(Icons.zoom_out_map_rounded),
            onPressed: _resetZoom,
          ),
          IconButton(
            tooltip: 'بحث داخل المستند',
            icon: Icon(_showSearchBar ? Icons.search_off_rounded : Icons.search_rounded),
            onPressed: () {
              setState(() {
                _showSearchBar = !_showSearchBar;
                if (!_showSearchBar) {
                  _searchCtrl.clear();
                  _docSearchQuery = '';
                }
              });
            },
          ),
          IconButton(
            tooltip: 'فتح في تطبيقات الهاتف / WPS',
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: _openInDeviceWpsOrPdfApp,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showSearchBar)
            Container(
              color: headerBg.withOpacity(0.92),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white),
                onChanged: (v) => setState(() => _docSearchQuery = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'ابحث عن كلمة داخل المستند...',
                  hintStyle: const TextStyle(color: Colors.white70, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  filled: true,
                  fillColor: Colors.black26,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ),

          Expanded(
            child: InteractiveViewer(
              transformationController: _zoomCtrl,
              minScale: 0.75,
              maxScale: 5.0,
              panEnabled: true,
              scaleEnabled: true,
              child: _parsing
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: headerBg),
                          const SizedBox(height: 14),
                          Text(
                            'جاري تجهيز وعرض صفحات المستند...',
                            style: TextStyle(color: _pageTextColor, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    )
                  : _buildDocumentBody(headerBg),
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _readingMode == 'night' ? const Color(0xFF1A202C) : Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.25))),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    tooltip: 'تصغير الخط',
                    icon: Icon(Icons.text_decrease_rounded, color: _readingMode == 'night' ? Colors.white : Colors.black87),
                    onPressed: () => setState(() => _fontSize = (_fontSize - 1.5).clamp(11.0, 28.0)),
                  ),
                  IconButton(
                    tooltip: 'تكبير الخط',
                    icon: Icon(Icons.text_increase_rounded, color: _readingMode == 'night' ? Colors.white : Colors.black87),
                    onPressed: () => setState(() => _fontSize = (_fontSize + 1.5).clamp(11.0, 28.0)),
                  ),
                  _modeDotBtn('paper', Colors.white, 'ورقي'),
                  _modeDotBtn('sepia', const Color(0xFFF6EEDB), 'مريح'),
                  _modeDotBtn('night', const Color(0xFF12151C), 'ليلي'),
                  IconButton(
                    tooltip: 'فتح في عارض PDF/WPS بالهاتف',
                    icon: Icon(Icons.ios_share_rounded, color: headerBg),
                    onPressed: _openInDeviceWpsOrPdfApp,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeDotBtn(String mode, Color fill, String label) {
    final active = _readingMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _readingMode = mode),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(
                color: active ? _brandHeaderColor : Colors.grey,
                width: active ? 2.5 : 1,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: _readingMode == 'night' ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentBody(Color headerBg) {
    if (_docCategory == 'PPTX' && _slides.isNotEmpty) {
      final filteredSlides = _docSearchQuery.isEmpty
          ? _slides
          : _slides.where((sl) {
              final lines = (sl['lines'] as List<String>).join(' ').toLowerCase();
              return lines.contains(_docSearchQuery);
            }).toList();

      return ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: filteredSlides.length,
        itemBuilder: (_, idx) {
          final sl = filteredSlides[idx];
          final lines = sl['lines'] as List<String>;
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _pageBackgroundColor,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 2))],
              border: Border.all(color: headerBg.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: headerBg, borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    'شريحة ${sl['number']} / ${_slides.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                ...lines.asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SelectableText(
                        e.key == 0 ? e.value : '• ${e.value}',
                        style: TextStyle(
                          fontSize: e.key == 0 ? _fontSize + 2 : _fontSize,
                          fontWeight: e.key == 0 ? FontWeight.bold : FontWeight.normal,
                          color: _pageTextColor,
                          height: 1.5,
                        ),
                      ),
                    )),
              ],
            ),
          );
        },
      );
    }

    if (_docCategory == 'XLSX' && _sheetRows.isNotEmpty) {
      final filteredRows = _docSearchQuery.isEmpty
          ? _sheetRows
          : _sheetRows.where((r) => r.join(' ').toLowerCase().contains(_docSearchQuery)).toList();

      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            decoration: BoxDecoration(
              color: _pageBackgroundColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.withOpacity(0.35)),
            ),
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder.all(color: Colors.grey.withOpacity(0.3)),
              children: List.generate(filteredRows.length, (rIdx) {
                final row = filteredRows[rIdx];
                final isHeader = rIdx == 0;
                return TableRow(
                  decoration: isHeader ? BoxDecoration(color: headerBg.withOpacity(0.18)) : null,
                  children: row.map((cell) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      child: SelectableText(
                        cell,
                        style: TextStyle(
                          fontSize: _fontSize - 1,
                          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                          color: _pageTextColor,
                        ),
                      ),
                    );
                  }).toList(),
                );
              }),
            ),
          ),
        ),
      );
    }

    // عرض صفحات ملف PDF كصور صفحات حقيقية عالية الدقة
    if (_docCategory == 'PDF' && _renderedPdfPages.isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _renderedPdfPages.length,
        itemBuilder: (_, idx) {
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: headerBg.withOpacity(0.12),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                  ),
                  child: Text(
                    'صفحة ${idx + 1} من ${_renderedPdfPages.length}  •  كبّر بإصبعيك للتقريب',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: headerBg),
                  ),
                ),
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                  child: Image.memory(
                    _renderedPdfPages[idx],
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    final visibleParagraphs = _docSearchQuery.isEmpty
        ? _paragraphs
        : _paragraphs.where((p) => p.toLowerCase().contains(_docSearchQuery)).toList();

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (_docCategory == 'PDF')
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: headerBg.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: headerBg.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📄 خيارات عرض ملف PDF الكامل:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: _pageTextColor),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: headerBg, foregroundColor: Colors.white),
                        icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                        label: const Text('فتح بالعارض الكامل (أوفلاين)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: _openInDeviceWpsOrPdfApp,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.cloud_done_rounded, size: 17),
                      label: const Text('عارض سحابي', style: TextStyle(fontSize: 12)),
                      onPressed: _openInOnlineOfficeViewer,
                    ),
                  ],
                ),
              ],
            ),
          ),

        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _pageBackgroundColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: visibleParagraphs.isEmpty
              ? Column(
                  children: [
                    Icon(Icons.picture_as_pdf_rounded, size: 46, color: headerBg),
                    const SizedBox(height: 10),
                    Text(
                      'اضغط على زر "فتح بالعارض الكامل (أوفلاين)" بالأعلى لعرض جميع صفحات المستند بدقتها الأصلية.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _pageTextColor, fontSize: 13.5, height: 1.6),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            style: TextStyle(fontSize: _fontSize + 2, fontWeight: FontWeight.bold, color: headerBg),
                          ),
                        ),
                        IconButton(
                          tooltip: 'نسخ كامل النص',
                          icon: Icon(Icons.copy_all_rounded, color: headerBg, size: 20),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: visibleParagraphs.join('\n\n')));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم نسخ نص المستند بالكامل ✓'), backgroundColor: Colors.teal),
                            );
                          },
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    ...visibleParagraphs.map((para) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SelectableText(
                            para,
                            style: TextStyle(
                              fontSize: _fontSize,
                              color: _pageTextColor,
                              height: 1.65,
                            ),
                          ),
                        )),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PureDartZipReader {
  static int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
  static int _u32(Uint8List b, int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  static Map<String, Uint8List> extractEntries(Uint8List bytes) {
    final Map<String, Uint8List> result = {};
    int eocdOffset = -1;
    final minSearch = (bytes.length - 65557) < 0 ? 0 : bytes.length - 65557;
    for (int i = bytes.length - 22; i >= minSearch; i--) {
      if (_u32(bytes, i) == 0x06054b50) {
        eocdOffset = i;
        break;
      }
    }
    if (eocdOffset == -1) return result;

    final totalEntries = _u16(bytes, eocdOffset + 10);
    int cdOffset = _u32(bytes, eocdOffset + 16);

    for (int i = 0; i < totalEntries; i++) {
      if (cdOffset + 46 > bytes.length) break;
      if (_u32(bytes, cdOffset) != 0x02014b50) break;

      final method = _u16(bytes, cdOffset + 10);
      final compSize = _u32(bytes, cdOffset + 20);
      final nameLen = _u16(bytes, cdOffset + 28);
      final extraLen = _u16(bytes, cdOffset + 30);
      final commentLen = _u16(bytes, cdOffset + 32);
      final localHeaderOffset = _u32(bytes, cdOffset + 42);

      final nameBytes = bytes.sublist(cdOffset + 46, cdOffset + 46 + nameLen);
      final fileName = utf8.decode(nameBytes, allowMalformed: true);
      cdOffset += 46 + nameLen + extraLen + commentLen;

      if (fileName.endsWith('/') || localHeaderOffset + 30 > bytes.length) continue;
      if (_u32(bytes, localHeaderOffset) != 0x04034b50) continue;

      final localNameLen = _u16(bytes, localHeaderOffset + 26);
      final localExtraLen = _u16(bytes, localHeaderOffset + 28);
      final dataStart = localHeaderOffset + 30 + localNameLen + localExtraLen;
      final dataEnd = dataStart + compSize;
      if (dataEnd > bytes.length) continue;

      final compData = bytes.sublist(dataStart, dataEnd);
      try {
        if (method == 0) {
          result[fileName] = Uint8List.fromList(compData);
        } else if (method == 8) {
          final raw = ZLibDecoder(raw: true).convert(compData);
          result[fileName] = Uint8List.fromList(raw);
        }
      } catch (_) {}
    }
    return result;
  }
}

class _InAppImageViewerScreen extends StatelessWidget {
  final String title;
  final String imageUrl;
  final String? localFilePath;
  final VoidCallback onShareFile;

  const _InAppImageViewerScreen({
    required this.title,
    required this.imageUrl,
    this.localFilePath,
    required this.onShareFile,
  });

  @override
  Widget build(BuildContext context) {
    final hasLocal = localFilePath != null && !kIsWeb && File(localFilePath!).existsSync();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title, style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            tooltip: 'حفظ ومشاركة الصورة',
            icon: const Icon(Icons.share_rounded),
            onPressed: onShareFile,
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: hasLocal
              ? Image.file(File(localFilePath!), fit: BoxFit.contain)
              : Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return const CircularProgressIndicator(color: Colors.tealAccent);
                  },
                ),
        ),
      ),
    );
  }
}
