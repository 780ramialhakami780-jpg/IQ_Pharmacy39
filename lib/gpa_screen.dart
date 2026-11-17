import 'package:flutter/material.dart';

class GpaScreen extends StatefulWidget {
  const GpaScreen({super.key});

  @override
  State<GpaScreen> createState() => _GpaScreenState();
}

class _GpaScreenState extends State<GpaScreen> {
  final List> _courses = [
    {'name': TextEditingController(text: 'كيمياء صيدلانية'), 'hours': 3.0, 'grade': TextEditingController()},
    {'name': TextEditingController(text: 'صيدلانيات'), 'hours': 3.0, 'grade': TextEditingController()},
    {'name': TextEditingController(text: 'علم الأدوية'), 'hours': 3.0, 'grade': TextEditingController()},
    {'name': TextEditingController(text: 'عقاقير'), 'hours': 2.0, 'grade': TextEditingController()},
  ];

  final _prevGpaCtrl = TextEditingController();
  final _prevHoursCtrl = TextEditingController();

  double _semesterGpa = 0.0;
  double _cumulativeGpa = 0.0;
  double _totalSemesterHours = 0.0;

  void _calculate() {
    double totalPoints = 0;
    double totalHours = 0;

    for (var c in _courses) {
      final grade = double.tryParse(c['grade'].text.trim());
      final hours = (c['hours'] as double);
      if (grade != null && grade >= 0 && grade <= 100) {
        totalPoints += grade * hours;
        totalHours += hours;
      }
    }

    final semGpa = totalHours > 0 ? totalPoints / totalHours : 0.0;
    final prevGpa = double.tryParse(_prevGpaCtrl.text.trim()) ?? 0.0;
    final prevHours = double.tryParse(_prevHoursCtrl.text.trim()) ?? 0.0;

    double cumGpa = semGpa;
    if (prevHours > 0 && prevGpa > 0) {
      cumGpa = ((prevGpa * prevHours) + totalPoints) / (prevHours + totalHours);
    }

    setState(() {
      _totalSemesterHours = totalHours;
      _semesterGpa = semGpa;
      _cumulativeGpa = cumGpa;
    });
  }

  String _getEstimate(double avg) {
    if (avg == 0) return '-';
    if (avg >= 90) return 'ممتاز';
    if (avg >= 80) return 'جيد جداً';
    if (avg >= 65) return 'جيد';
    if (avg >= 50) return 'مقبول';
    return 'راسب';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('حاسبة المعدل الفصلي والتراكمي'),
          actions: [
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'إضافة مادة',
              onPressed: () {
                setState(() {
                  _courses.add({
                    'name': TextEditingController(),
                    'hours': 2.0,
                    'grade': TextEditingController(),
                  });
                });
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF4FD1C5).withOpacity(0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('المعدل الفصلي', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        '${_semesterGpa.toStringAsFixed(2)}%',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF4FD1C5)),
                      ),
                      Text(_getEstimate(_semesterGpa), style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  Container(width: 1, height: 45, color: Colors.white24),
                  Column(
                    children: [
                      const Text('المعدل التراكمي', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        '${_cumulativeGpa.toStringAsFixed(2)}%',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                      ),
                      Text('الساعات: ${_totalSemesterHours.toInt()}', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ExpansionTile(
              title: const Text('إضافة المعدل التراكمي السابق (اختياري)', style: TextStyle(fontSize: 14)),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _prevGpaCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => _calculate(),
                          decoration: const InputDecoration(
                            labelText: 'المعدل السابق (%)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _prevHoursCtrl,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _calculate(),
                          decoration: const InputDecoration(
                            labelText: 'الساعات المنجزة سابقاً',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(_courses.length, (index) {
              final item = _courses[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: item['name'],
                          decoration: InputDecoration(
                            labelText: 'المادة ${index + 1}',
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<double>(
                        value: item['hours'],
                        items: [1.0, 2.0, 3.0, 4.0]
                            .map((h) => DropdownMenuItem(value: h, child: Text('${h.toInt()} س')))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => item['hours'] = val);
                            _calculate();
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: item['grade'],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => _calculate(),
                          decoration: const InputDecoration(
                            labelText: 'الدرجة',
                            border: OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        onPressed: () {
                          setState(() => _courses.removeAt(index));
                          _calculate();
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
