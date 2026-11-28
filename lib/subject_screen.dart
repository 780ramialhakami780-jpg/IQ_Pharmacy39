import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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

  bool _loading = true;
  String _searchQuery = '';
  String _selectedFilter = 'الكل';

  final Map<dynamic, int> _selectedAnswers = {};
  bool _quizSubmitted = false;

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

  @override
  Widget build(BuildContext context) {
    final cardBg = Theme.of(context).cardColor;
    final accent = widget.defaultColor;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_subjectName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          actions: [
            IconButton(
              tooltip: AppPrefs.tr('تحديث محتوى المادة', 'Refresh Subject'),
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loadLocalAndSync,
            ),
          ],
          bottom: TabBar(
            indicatorColor: accent,
            tabs: [
              Tab(
                icon: const Icon(Icons.folder_copy_rounded, size: 18),
                text: '${AppPrefs.tr('المحاضرات والملفات', 'Files & Lectures')} (${_materials.length})',
              ),
              Tab(
                icon: const Icon(Icons.quiz_rounded, size: 18),
                text: '${AppPrefs.tr('بنك الأسئلة', 'Question Bank')} (${_questions.length})',
              ),
            ],
          ),
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: accent))
            : TabBarView(
                children: [
                  _buildMaterialsTab(cardBg, accent),
                  _buildQuestionsTab(cardBg, accent),
                ],
              ),
      ),
    );
  }

  Widget _buildMaterialsTab(Color cardBg, Color accent) {
    final filters = ['الكل', 'PDF', 'WORD', 'EXCEL', 'PPT', 'AUDIO', 'VIDEO', 'صور'];

    final filtered = _materials.where((item) {
      final m = Map<String, dynamic>.from(item);
      final title = (m['title'] ?? '').toString().toLowerCase();
      final ext = _guessExtension(m);
      final fType = (m['file_type'] ?? '').toString().toUpperCase();

      if (_searchQuery.isNotEmpty && !title.contains(_searchQuery.toLowerCase())) {
        return false;
      }

      if (_selectedFilter == 'PDF') return ext == 'pdf' || fType == 'PDF';
      if (_selectedFilter == 'WORD') return ['doc', 'docx'].contains(ext) || fType == 'DOCX';
      if (_selectedFilter == 'EXCEL') return ['xls', 'xlsx', 'csv'].contains(ext) || fType == 'XLSX';
      if (_selectedFilter == 'PPT') return ['ppt', 'pptx'].contains(ext) || fType == 'PPTX';
      if (_selectedFilter == 'AUDIO') return ['mp3', 'm4a', 'wav'].contains(ext) || fType == 'AUDIO' || fType == 'MP3';
      if (_selectedFilter == 'VIDEO') return ['mp4', 'mkv', 'mov'].contains(ext) || fType == 'VIDEO' || fType == 'MP4';
      if (_selectedFilter == 'صور') return ['jpg', 'jpeg', 'png', 'webp'].contains(ext) || fType == 'JPG';
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadLocalAndSync,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v.trim()),
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
                final sel = _selectedFilter == f;
                return ChoiceChip(
                  label: Text(f, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: sel ? Colors.white : null)),
                  selected: sel,
                  selectedColor: accent,
                  onSelected: (_) => setState(() => _selectedFilter = f),
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

  Widget _buildQuestionsTab(Color cardBg, Color accent) {
    if (_questions.isEmpty) {
      return Center(
        child: Text(
          AppPrefs.tr('لا توجد أسئلة مضافة في بنك هذه المادة بعد.', 'No questions in this subject bank yet.'),
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    int score = 0;
    if (_quizSubmitted) {
      for (final q in _questions) {
        final qid = q['id'];
        if (_selectedAnswers[qid] == (q['correct_index'] ?? 0)) {
          score++;
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_quizSubmitted)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.16),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.teal),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'النتيجة: $score من ${_questions.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('إعادة المحاولة'),
                  onPressed: () {
                    setState(() {
                      _selectedAnswers.clear();
                      _quizSubmitted = false;
                    });
                  },
                ),
              ],
            ),
          ),
        ...List.generate(_questions.length, (idx) {
          final q = Map<String, dynamic>.from(_questions[idx]);
          final qid = q['id'];
          final qKey = qid.toString();
          final isFav = _favQuestionIds.contains(qKey);
          final List<dynamic> opts = q['options'] is String ? jsonDecode(q['options']) : (q['options'] ?? []);
          final int correctIdx = q['correct_index'] ?? 0;
          final int? chosenIdx = _selectedAnswers[qid];
          final explanation = (q['explanation'] ?? '').toString().trim();

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
                      Expanded(
                        child: Text(
                          '${idx + 1}. ${q['question_text'] ?? ''}',
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
                    final isSelected = chosenIdx == oIdx;
                    final isRight = oIdx == correctIdx;
                    Color? tileColor;
                    if (_quizSubmitted) {
                      if (isRight) {
                        tileColor = Colors.green.withOpacity(0.18);
                      } else if (isSelected && !isRight) {
                        tileColor = Colors.redAccent.withOpacity(0.18);
                      }
                    } else if (isSelected) {
                      tileColor = accent.withOpacity(0.16);
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: tileColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _quizSubmitted && isRight
                              ? Colors.green
                              : (isSelected ? accent : Colors.grey.withOpacity(0.25)),
                        ),
                      ),
                      child: RadioListTile<int>(
                        dense: true,
                        value: oIdx,
                        groupValue: chosenIdx,
                        activeColor: accent,
                        title: Text(opts[oIdx].toString(), style: const TextStyle(fontSize: 13.5)),
                        onChanged: _quizSubmitted
                            ? null
                            : (val) => setState(() => _selectedAnswers[qid] = val!),
                      ),
                    );
                  }),
                  if (_quizSubmitted && explanation.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('💡 التوضيح: $explanation', style: const TextStyle(fontSize: 12.5)),
                    ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        if (!_quizSubmitted)
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
              icon: const Icon(Icons.check_circle_rounded),
              label: const Text('تصحيح الإجابات وعرض النتيجة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              onPressed: () => setState(() => _quizSubmitted = true),
            ),
          ),
      ],
    );
  }
}

/// ============================================================================
/// عارض المستندات المتكامل شبيه تطبيق WPS Office
/// - يدعم تكبير وتصغير تلقائي بالأصابع (InteractiveViewer) لأي نوع ملف
/// - يستخرج صفحات/صور PDF المضمنة ويعرضها مباشرة مع إمكانية الفتح الكامل
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
  String _readingMode = 'paper'; // 'paper' | 'sepia' | 'night'
  double _fontSize = 15.5;
  bool _showSearchBar = false;
  String _docSearchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  final TransformationController _zoomCtrl = TransformationController();

  List<String> _paragraphs = [];
  List<List<String>> _sheetRows = [];
  List<Map<String, dynamic>> _slides = [];
  List<Uint8List> _pdfEmbeddedImages = [];
  int _estimatedPdfPages = 0;
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
        _pdfEmbeddedImages = _extractPdfImages(bytes);
        _estimatedPdfPages = _countPdfPages(bytes);
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

  int _countPdfPages(Uint8List bytes) {
    final raw = latin1.decode(bytes, allowInvalid: true);
    final matches = RegExp(r'/Type\s*/Page\b').allMatches(raw).length;
    return matches > 0 ? matches : 1;
  }

  /// استخراج الصور المضمنة داخل ملف PDF (مثل JPEG أو FlateDecode) لعرض صفحات PDF المصوّرة مباشرة
  List<Uint8List> _extractPdfImages(Uint8List bytes) {
    final List<Uint8List> images = [];
    final rawLatin = latin1.decode(bytes, allowInvalid: true);

    // 1. استخراج صور JPEG المضمنة مباشرة داخل PDF (FFD8FF ... FFD9)
    int idx = 0;
    while (idx < bytes.length - 4 && images.length < 30) {
      if (bytes[idx] == 0xFF && bytes[idx + 1] == 0xD8 && bytes[idx + 2] == 0xFF) {
        int endIdx = -1;
        for (int j = idx + 3; j < bytes.length - 1; j++) {
          if (bytes[j] == 0xFF && bytes[j + 1] == 0xD9) {
            endIdx = j + 2;
            break;
          }
        }
        if (endIdx != -1 && endIdx - idx > 500) {
          images.add(Uint8List.sublistView(bytes, idx, endIdx));
          idx = endIdx;
          continue;
        }
      }
      idx++;
    }

    // 2. محاولة فك ضغط تدفقات الصور (DCTDecode / FlateDecode) إن لم تُلتقط صور JPEG خامة
    if (images.isEmpty) {
      final streamMatches = RegExp(r'stream\r?\n(.*?)\r?\nendstream', dotAll: true).allMatches(rawLatin);
      for (final sm in streamMatches) {
        if (images.length >= 25) break;
        final sStr = sm.group(1);
        if (sStr == null || sStr.length < 200) continue;
        final sBytes = latin1.encode(sStr);
        try {
          final inflated = Uint8List.fromList(zlib.decode(sBytes));
          if (inflated.length > 2000) {
            images.add(inflated);
          }
        } catch (_) {}
      }
    }

    return images;
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

          // تكبير وتصغير تلقائي بالأصابع لأي مستند أيا كان نوعه
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
                            'جاري تجهيز وعرض المستند...',
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

    final visibleParagraphs = _docSearchQuery.isEmpty
        ? _paragraphs
        : _paragraphs.where((p) => p.toLowerCase().contains(_docSearchQuery)).toList();

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (_docCategory == 'PDF') ...[
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
                  '📄 ملف PDF ($_estimatedPdfPages صفحة) — يمكنك التكبير والتصغير بإصبعيك مباشرة:',
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
          if (_pdfEmbeddedImages.isNotEmpty)
            ...List.generate(_pdfEmbeddedImages.length, (idx) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _pageBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('صفحة / لوحة ${idx + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: headerBg)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _pdfEmbeddedImages[idx],
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],

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
                      _docCategory == 'PDF'
                          ? 'تم عرض المحتوى المرئي المتاح داخل التطبيق ($_estimatedPdfPages صفحة). للعرض الكامل لكل صفحة بدقتها الأصلية استخدم زر "فتح بالعارض الكامل" بالأعلى.'
                          : 'لا توجد نصوص قابلة للعرض المباشر في هذا الملف.',
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
