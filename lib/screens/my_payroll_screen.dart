import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../state/auth_state.dart';
import '../widgets/config.dart';

enum Period { day, week, month, quarter, year }

class MyPayrollScreen extends StatefulWidget {
  const MyPayrollScreen({super.key});

  @override
  State<MyPayrollScreen> createState() => _MyPayrollScreenState();
}

class _MyPayrollScreenState extends State<MyPayrollScreen> {
  bool _loading = false;
  String? _error;
  List<dynamic> _payrolls = [];

  Period _period = Period.month;
  DateTime _anchor = DateTime.now();

  @override
  void initState() {
    super.initState();
    _fetchPayrolls();
  }

  // -------------------- FETCH --------------------
  Future<void> _fetchPayrolls() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = context.read<AuthState>().token;
      final uri = Uri.parse('${AppConfig.baseUrl}/api/payroll/my-history');
      final res = await http.get(uri, headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      });

      if (res.statusCode == 200) {
        _payrolls = jsonDecode(res.body) as List;
      } else {
        _error = 'HTTP ${res.statusCode}: ${res.body}';
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------- RANGE HELPERS --------------------
  String _isoUtc(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day, 0, 0, 0).toIso8601String();

  DateTime _startOfWeek(DateTime d) {
    // Tuần bắt đầu Thứ 2
    final wd = d.weekday; // 1..7
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: wd - 1));
  }

  int _weekNumber(DateTime d) {
    final firstDay = DateTime(d.year, 1, 1);
    final days = d.difference(firstDay).inDays + firstDay.weekday;
    return ((days) / 7).ceil();
  }

  ({String startIso, String endIso, String label}) _makeRange(Period p, DateTime anchor) {
    switch (p) {
      case Period.day:
        final start = DateTime(anchor.year, anchor.month, anchor.day);
        final end = start.add(const Duration(days: 1));
        final label = DateFormat('yyyy-MM-dd').format(start);
        return (startIso: _isoUtc(start), endIso: _isoUtc(end), label: label);

      case Period.week:
        final start = _startOfWeek(anchor);
        final end = start.add(const Duration(days: 7));
        final weekNo = _weekNumber(anchor);
        final label = '${anchor.year}-W${weekNo.toString().padLeft(2, '0')}';
        return (startIso: _isoUtc(start), endIso: _isoUtc(end), label: label);

      case Period.month:
        final start = DateTime(anchor.year, anchor.month, 1);
        final end = DateTime(anchor.year, anchor.month + 1, 1);
        final label = '${anchor.year}-${anchor.month.toString().padLeft(2, '0')}';
        return (startIso: _isoUtc(start), endIso: _isoUtc(end), label: label);

      case Period.quarter:
        final q = ((anchor.month - 1) ~/ 3) + 1;
        final startMonth = (q - 1) * 3 + 1;
        final start = DateTime(anchor.year, startMonth, 1);
        final end = DateTime(anchor.year, startMonth + 3, 1);
        final label = '${anchor.year}-Q$q';
        return (startIso: _isoUtc(start), endIso: _isoUtc(end), label: label);

      case Period.year:
        final start = DateTime(anchor.year, 1, 1);
        final end = DateTime(anchor.year + 1, 1, 1);
        final label = '${anchor.year}';
        return (startIso: _isoUtc(start), endIso: _isoUtc(end), label: label);
    }
  }

  String _currentLabel() => _makeRange(_period, _anchor).label;

  // -------------------- MATCH & FILTER (CHUẨN ĐỊNH DẠNG) --------------------
  // Day:     2025-01-03
  // Week:    2025-W05
  // Month:   2025-01
  // Quarter: 2025-Q1
  // Year:    2025
  bool _labelMatches(String label, Period p, DateTime anchor) {
    final want = _makeRange(p, anchor).label;

    switch (p) {
      case Period.day:
        final r = RegExp(r'^\d{4}-\d{2}-\d{2}$');
        return r.hasMatch(label) && label == want;

      case Period.week:
        final r = RegExp(r'^\d{4}-W\d{2}$');
        return r.hasMatch(label) && label == want;

      case Period.month:
        final r = RegExp(r'^\d{4}-\d{2}$');
        return r.hasMatch(label) && label == want;

      case Period.quarter:
        final r = RegExp(r'^\d{4}-Q[1-4]$');
        return r.hasMatch(label) && label == want;

      case Period.year:
        final r = RegExp(r'^\d{4}$');
        return r.hasMatch(label) && label == want;
    }
  }

  List<dynamic> _filtered() {
    if (_payrolls.isEmpty) return [];
    return _payrolls.where((p) {
      final label = (p['period'] ?? '').toString();
      return _labelMatches(label, _period, _anchor);
    }).toList();
  }

  // -------------------- NAVIGATION (prev/next) --------------------
  void _shiftAnchor(int dir) {
    setState(() {
      switch (_period) {
        case Period.day:
          _anchor = _anchor.add(Duration(days: 1 * dir));
          break;
        case Period.week:
          _anchor = _anchor.add(Duration(days: 7 * dir));
          break;
        case Period.month:
          _anchor = DateTime(_anchor.year, _anchor.month + dir, 1);
          break;
        case Period.quarter:
          _anchor = DateTime(_anchor.year, _anchor.month + (3 * dir), 1);
          break;
        case Period.year:
          _anchor = DateTime(_anchor.year + dir, 1, 1);
          break;
      }
    });
  }

  // -------------------- PICKER --------------------
  Future<void> _openViewPicker() async {
    Period pick = _period;
    DateTime pickAnchor = _anchor;
    int pickYear = pickAnchor.year;
    int pickMonth = pickAnchor.month;
    int pickQuarter = ((pickAnchor.month - 1) ~/ 3) + 1;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          Widget fields() {
            switch (pick) {
              case Period.day:
              case Period.week:
                return Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.date_range),
                        label: Text(DateFormat('dd/MM/yyyy').format(pickAnchor)),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: pickAnchor,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(DateTime.now().year + 2),
                          );
                          if (d != null) {
                            setDialog(() {
                              pickAnchor = d;
                              pickYear = d.year;
                              pickMonth = d.month;
                              pickQuarter = ((d.month - 1) ~/ 3) + 1;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                );

              case Period.month:
                return Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: pickMonth,
                        decoration: const InputDecoration(labelText: 'Tháng'),
                        items: List.generate(12, (i) => i + 1)
                            .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(m.toString().padLeft(2, '0')),
                        ))
                            .toList(),
                        onChanged: (v) => setDialog(() {
                          pickMonth = v ?? pickMonth;
                          pickAnchor = DateTime(pickYear, pickMonth, 1);
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: pickYear,
                        decoration: const InputDecoration(labelText: 'Năm'),
                        items: List.generate(7, (i) => DateTime.now().year + 1 - i)
                            .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                            .toList(),
                        onChanged: (v) => setDialog(() {
                          pickYear = v ?? pickYear;
                          pickAnchor = DateTime(pickYear, pickMonth, 1);
                        }),
                      ),
                    ),
                  ],
                );

              case Period.quarter:
                return Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: pickQuarter,
                        decoration: const InputDecoration(labelText: 'Quý'),
                        items: [1, 2, 3, 4]
                            .map((q) => DropdownMenuItem(value: q, child: Text('Q$q')))
                            .toList(),
                        onChanged: (v) => setDialog(() {
                          pickQuarter = v ?? pickQuarter;
                          final sm = (pickQuarter - 1) * 3 + 1;
                          pickAnchor = DateTime(pickYear, sm, 1);
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: pickYear,
                        decoration: const InputDecoration(labelText: 'Năm'),
                        items: List.generate(7, (i) => DateTime.now().year + 1 - i)
                            .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                            .toList(),
                        onChanged: (v) => setDialog(() {
                          pickYear = v ?? pickYear;
                          final sm = (pickQuarter - 1) * 3 + 1;
                          pickAnchor = DateTime(pickYear, sm, 1);
                        }),
                      ),
                    ),
                  ],
                );

              case Period.year:
                return DropdownButtonFormField<int>(
                  value: pickYear,
                  decoration: const InputDecoration(labelText: 'Năm'),
                  items: List.generate(7, (i) => DateTime.now().year + 1 - i)
                      .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                      .toList(),
                  onChanged: (v) => setDialog(() {
                    pickYear = v ?? pickYear;
                    pickAnchor = DateTime(pickYear, 1, 1);
                  }),
                );
            }
          }

          return AlertDialog(
            title: const Text('Chọn kỳ để xem'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Period>(
                    value: pick,
                    decoration: const InputDecoration(labelText: 'Loại kỳ'),
                    items: const [
                      DropdownMenuItem(value: Period.day, child: Text('Ngày')),
                      DropdownMenuItem(value: Period.week, child: Text('Tuần')),
                      DropdownMenuItem(value: Period.month, child: Text('Tháng')),
                      DropdownMenuItem(value: Period.quarter, child: Text('Quý')),
                      DropdownMenuItem(value: Period.year, child: Text('Năm')),
                    ],
                    onChanged: (v) => setDialog(() => pick = v ?? pick),
                  ),
                  const SizedBox(height: 10),
                  fields(),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Đóng')),
              ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Áp dụng'),
                onPressed: () {
                  setState(() {
                    _period = pick;
                    _anchor = pickAnchor;
                  });
                  Navigator.of(ctx).pop();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // -------------------- LABEL FOR UI --------------------
  String _rangeLabel(Period p, DateTime d) {
    switch (p) {
      case Period.day:
        return DateFormat('dd/MM/yyyy').format(d);
      case Period.week:
        final w = _weekNumber(d);
        return 'Tuần $w/${d.year}';
      case Period.month:
        return DateFormat('MM/yyyy').format(d);
      case Period.quarter:
        final q = ((d.month - 1) ~/ 3) + 1;
        return 'Quý $q/${d.year}';
      case Period.year:
        return 'Năm ${d.year}';
    }
  }

  // -------------------- BUILD --------------------
  @override
  Widget build(BuildContext context) {
    final list = _filtered();
    final fmt = NumberFormat.currency(locale: "vi_VN", symbol: "₫");
    final total =
    list.fold<double>(0, (sum, e) => sum + (e['totalSalary'] as num).toDouble());

    return Scaffold(
      appBar: AppBar(
        title: const Text("Bảng lương của tôi"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchPayrolls),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text("Lỗi: $_error"))
          : Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ToggleButtons(
                  borderRadius: BorderRadius.circular(12),
                  selectedColor: Colors.white,
                  fillColor: Theme.of(context).primaryColor,
                  isSelected: [
                    _period == Period.day,
                    _period == Period.week,
                    _period == Period.month,
                    _period == Period.quarter,
                    _period == Period.year,
                  ],
                  onPressed: (i) => setState(() {
                    _period = [Period.day, Period.week, Period.month, Period.quarter, Period.year][i];
                  }),
                  children: const [
                    Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text("Ngày")),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text("Tuần")),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text("Tháng")),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text("Quý")),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text("Năm")),
                  ],
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Kỳ trước',
                  onPressed: () => _shiftAnchor(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(_rangeLabel(_period, _anchor)),
                  onPressed: _openViewPicker,
                ),
                IconButton(
                  tooltip: 'Kỳ tiếp',
                  onPressed: () => _shiftAnchor(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Text(
              '📅 Kỳ: ${_rangeLabel(_period, _anchor)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text("Chưa có bảng lương cho kỳ này."))
                  : ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final p = list[i];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.payments),
                      title: Text("Kỳ: ${p['period']}"),
                      subtitle: Text(
                        "Giờ công: ${p['totalHours']}h\nLương: ${fmt.format(p['totalSalary'])}",
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Tổng lương kỳ này: ${fmt.format(total)}",
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
