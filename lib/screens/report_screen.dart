import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';
import '../widgets/config.dart';

enum Period { day, week, month, quarter, year }

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  Period _period = Period.month;
  DateTime _anchor = DateTime.now();
  bool _loading = false;
  String? _error;

  Map<String, dynamic>? _summary; // JSON từ /summary

  // ==== Helpers hiển thị ngày an toàn ====
  String _fmtDate(dynamic v) {
    final s = (v ?? '').toString();
    final dt = DateTime.tryParse(s);
    if (dt != null) {
      return DateFormat('yyyy-MM-dd').format(dt.toLocal());
    }
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  String _rangeLabel() {
    switch (_period) {
      case Period.day:
        return DateFormat('dd/MM/yyyy').format(_anchor);
      case Period.week:
        return 'Tuần ~ ${DateFormat('dd/MM').format(_anchor)}';
      case Period.month:
        return DateFormat('MM/yyyy').format(_anchor);
      case Period.quarter:
        final q = ((_anchor.month - 1) ~/ 3) + 1;
        return 'Q$q/${_anchor.year}';
      case Period.year:
        return '${_anchor.year}';
    }
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = context.read<AuthState>().token;
      final kind = _period.name; // day/week/month/quarter/year
      final anchorIso =
      DateTime(_anchor.year, _anchor.month, _anchor.day).toUtc().toIso8601String();

      // ĐÚNG PATH: /api/report/summary
      final uri = Uri.parse('${AppConfig.baseUrl}/api/report/summary').replace(
        queryParameters: {'kind': kind, 'anchor': anchorIso},
      );

      final res = await http.get(uri, headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      });

      if (res.statusCode >= 200 && res.statusCode < 300) {
        _summary = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      } else {
        _error = 'HTTP ${res.statusCode}: ${res.body}';
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shift(int dir) {
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
          _anchor = DateTime(_anchor.year, _anchor.month + 3 * dir, 1);
          break;
        case Period.year:
          _anchor = DateTime(_anchor.year + dir, 1, 1);
          break;
      }
    });
    _fetch();
  }

  Future<void> _pick() async {
    Period pick = _period;
    DateTime pickAnchor = _anchor;
    int pickYear = pickAnchor.year;
    int pickMonth = pickAnchor.month;
    int pickQuarter = ((pickAnchor.month - 1) ~/ 3) + 1;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) {
        Widget fields() {
          switch (pick) {
            case Period.day:
            case Period.week:
              return OutlinedButton.icon(
                icon: const Icon(Icons.date_range),
                label: Text(DateFormat('dd/MM/yyyy').format(pickAnchor)),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: pickAnchor,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(DateTime.now().year + 2),
                  );
                  if (d != null) setDialog(() => pickAnchor = d);
                },
              );
            case Period.month:
              return Row(children: [
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
              ]);
            case Period.quarter:
              return Row(children: [
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
              ]);
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
          title: const Text('Chọn kỳ báo cáo'),
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
            ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Áp dụng'),
              onPressed: () {
                setState(() {
                  _period = pick;
                  _anchor = pickAnchor;
                });
                Navigator.pop(ctx);
                _fetch();
              },
            ),
          ],
        );
      }),
    );
  }

  Future<void> _exportCsv() async {
    try {
      final token = context.read<AuthState>().token;
      final kind = _period.name;
      final anchorIso =
      DateTime(_anchor.year, _anchor.month, _anchor.day).toUtc().toIso8601String();

      // ĐÚNG PATH: /api/report/summary.csv
      final uri = Uri.parse('${AppConfig.baseUrl}/api/report/summary.csv').replace(
        queryParameters: {'kind': kind, 'anchor': anchorIso},
      );

      final res = await http.get(uri, headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      });

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final dir = await getTemporaryDirectory();
        final safeName = _rangeLabel().replaceAll('/', '-').replaceAll(' ', '');
        final path = '${dir.path}/report_$safeName.csv';
        final file = File(path);
        await file.writeAsBytes(res.bodyBytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã lưu: $path')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Xuất CSV lỗi: ${res.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_summary == null && !_loading) _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: "vi_VN", symbol: "₫");
    final items = (_summary?['items'] as List?) ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Báo cáo thống kê'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetch),
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Xuất CSV',
            onPressed: _exportCsv,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Lỗi: $_error'))
          : Padding(
        padding: const EdgeInsets.all(12),
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
                  onPressed: (i) {
                    setState(() => _period = [
                      Period.day,
                      Period.week,
                      Period.month,
                      Period.quarter,
                      Period.year
                    ][i]);
                    _fetch();
                  },
                  children: const [
                    Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('Ngày')),
                    Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('Tuần')),
                    Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('Tháng')),
                    Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('Quý')),
                    Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('Năm')),
                  ],
                ),
                IconButton(
                    onPressed: () => _shift(-1),
                    icon: const Icon(Icons.chevron_left)),
                TextButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(_rangeLabel()),
                  onPressed: _pick,
                ),
                IconButton(
                    onPressed: () => _shift(1),
                    icon: const Icon(Icons.chevron_right)),
              ],
            ),
            const SizedBox(height: 12),

            if (_summary != null) ...[
              Card(
                elevation: 0,
                color: Theme.of(context)
                    .colorScheme
                    .surfaceVariant
                    .withOpacity(0.4),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Kỳ: ${_summary!['period']}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold)),
                      Text(
                          'Từ: ${_fmtDate(_summary!['start'])}  '
                              'đến: ${_fmtDate(_summary!['end'])}'),
                      const SizedBox(height: 8),
                      Text('Số nhân viên: ${_summary!['employeeCount']}'),
                      Text('Tổng giờ: ${_summary!['totalHours']}h'),
                      Text(
                        'Tổng lương: ${fmt.format((_summary!['totalSalary'] as num?) ?? 0)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('Chưa có dữ liệu báo cáo.'))
                  : ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final it = items[i] as Map<String, dynamic>;
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.person),
                      title: Text(it['fullName'] ?? 'Nhân viên'),
                      subtitle: Text(
                        'Giờ: ${it['hours']}h\n'
                            'Lương: ${fmt.format((it['salary'] as num?) ?? 0)}',
                      ),
                      trailing: Text('#${it['employeeId']}'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
