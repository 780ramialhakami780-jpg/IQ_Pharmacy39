import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DirectoryItem {
  final String title;
  final String value;
  final String type;

  DirectoryItem({required this.title, required this.value, required this.type});
}

class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key});

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  bool _loading = true;
  List<DirectoryItem> _items = [
    DirectoryItem(title: 'بوابة الطالب الجامعية - جامعة صنعاء', value: 'https://portal.su.edu.ye', type: 'رابط'),
    DirectoryItem(title: 'قناة الدفعة 39 على تيليجرام', value: 'أضف رابط القناة من لوحة الإدارة', type: 'رابط'),
    DirectoryItem(title: 'مندوب الدفعة العام (بنين)', value: 'أضف الاسم والرقم من لوحة الإدارة', type: 'تواصل'),
    DirectoryItem(title: 'مندوبة الدفعة (بنات)', value: 'أضف الاسم والرقم من لوحة الإدارة', type: 'تواصل'),
  ];

  @override
  void initState() {
    super.initState();
    _fetchDirectory();
  }

  Future<void> _fetchDirectory() async {
    try {
      final res = await Supabase.instance.client
          .from('app_settings')
          .select('value')
          .eq('key', 'batch_directory')
          .maybeSingle();
      if (res != null && res['value'] != null && res['value'].toString().isNotEmpty) {
        final decoded = jsonDecode(res['value']) as List<dynamic>;
        setState(() {
          _items = decoded.map((e) {
            final map = e as Map<String, dynamic>;
            return DirectoryItem(
              title: (map['title'] ?? '').toString(),
              value: (map['value'] ?? '').toString(),
              type: (map['type'] ?? 'رابط').toString(),
            );
          }).toList();
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('دليل المناديب والروابط المهمة'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final isLink = item.type == 'رابط';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF4FD1C5).withOpacity(0.15),
                        child: Icon(
                          isLink ? Icons.link : Icons.support_agent,
                          color: const Color(0xFF4FD1C5),
                        ),
                      ),
                      title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(item.value, style: const TextStyle(fontSize: 13)),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        tooltip: 'نسخ',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: item.value));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تم النسخ إلى الحافظة'), duration: Duration(seconds: 2)),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
