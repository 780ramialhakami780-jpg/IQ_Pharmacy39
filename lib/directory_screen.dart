import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_prefs.dart';

class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key});

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _studentGender = 'male';

  @override
  void initState() {
    super.initState();
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    _studentGender = prefs.getString('student_gender') ?? 'male';

    try {
      final rawCached = prefs.getString('cache_batch_directory');
      if (rawCached != null && rawCached.isNotEmpty) {
        final decoded = jsonDecode(rawCached) as List<dynamic>;
        _items = decoded
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where(_matchesGender)
            .toList();
      }
    } catch (_) {}

    if (mounted && _items.isNotEmpty) {
      setState(() => _loading = false);
    }

    try {
      final row = await Supabase.instance.client
          .from('app_settings')
          .select('value')
          .eq('key', 'batch_directory')
          .maybeSingle();

      if (row != null && row['value'] != null && row['value'].toString().trim().isNotEmpty) {
        final rawVal = row['value'].toString().trim();
        await prefs.setString('cache_batch_directory', rawVal);
        final decoded = jsonDecode(rawVal) as List<dynamic>;
        _items = decoded
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where(_matchesGender)
            .toList();
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  bool _matchesGender(Map<String, dynamic> item) {
    final target = (item['target_gender'] ?? 'all').toString().trim().toLowerCase();
    if (target.isEmpty || target == 'all') return true;
    return target == _studentGender;
  }

  bool _isLinkItem(Map<String, dynamic> item) {
    final type = (item['type'] ?? '').toString().trim();
    final val = (item['value'] ?? '').toString().trim().toLowerCase();
    if (type == 'رابط') return true;
    return val.startsWith('http://') || val.startsWith('https://') || val.startsWith('www.');
  }

  Future<void> _openItemAction(Map<String, dynamic> item) async {
    final rawVal = (item['value'] ?? '').toString().trim();
    if (rawVal.isEmpty) return;

    if (_isLinkItem(item)) {
      final normalizedUrl = rawVal.startsWith('http://') || rawVal.startsWith('https://')
          ? rawVal
          : 'https://$rawVal';
      final uri = Uri.tryParse(normalizedUrl);
      if (uri != null) {
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched && mounted) {
          await launchUrl(uri, mode: LaunchMode.platformDefault);
        }
      }
    } else {
      final cleanPhone = rawVal.replaceAll(RegExp(r'[^\d+]'), '');
      final telUri = Uri.tryParse('tel:$cleanPhone');
      if (telUri != null) {
        await launchUrl(telUri, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Theme.of(context).cardColor;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppPrefs.tr('دليل الطلاب والروابط المهمة', 'Batch Directory & Important Links')),
        actions: [
          IconButton(
            tooltip: AppPrefs.tr('تحديث', 'Refresh'),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              setState(() => _loading = true);
              _loadDirectory();
            },
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: accent))
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      AppPrefs.tr('لا توجد روابط أو جهات تواصل مضافة حالياً.', 'No links or contacts added yet.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadDirectory,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    itemBuilder: (_, idx) {
                      final item = _items[idx];
                      final title = (item['title'] ?? '').toString();
                      final value = (item['value'] ?? '').toString();
                      final isLink = _isLinkItem(item);

                      return Card(
                        color: cardBg,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.grey.withOpacity(0.2)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: accent.withOpacity(0.16),
                                child: Icon(
                                  isLink ? Icons.link_rounded : Icons.phone_rounded,
                                  color: accent,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                                    ),
                                    const SizedBox(height: 4),
                                    Directionality(
                                      textDirection: TextDirection.ltr,
                                      child: Text(
                                        value,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: Icon(isLink ? Icons.open_in_new_rounded : Icons.call_rounded, size: 17),
                                label: Text(
                                  isLink
                                      ? AppPrefs.tr('فتح الرابط', 'Open Link')
                                      : AppPrefs.tr('اتصال', 'Call'),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                ),
                                onPressed: () => _openItemAction(item),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
