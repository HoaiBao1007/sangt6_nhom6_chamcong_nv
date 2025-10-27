import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';
import '../widgets/config.dart';

enum Period { week, month, quarter, year }

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  bool _loading = false;
  String? _error;
  List<dynamic> _attendances = [];

  // Bộ lọc
  Period _period = Period.month;
  DateTime _anchor = DateTime.now(); // ngày gốc để tính tuần/tháng/quý/năm

  final _fmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  void initState() {
    super.initState();
    _fetchAttendances();
  }

  Future<void> _fetchAttendances() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = context.read<AuthState>().token;
      final uri = Uri.parse('${AppConfig.baseUrl}/api/Attendances'); // ĐỔI nếu route khác
      final res = await http.get(uri, headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      });
      if (res.statusCode == 200) {
        _attendances = jsonDecode(res.body) as List;
      } else {
        _error = 'HTTP ${res.statusCode}: ${res.body}';
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ====== Helpers thời gian ======
  DateTimeRange _rangeFor(Period p, DateTime d) {
    switch (p) {
      case Period.week:
        final monday = d.subtract(Duration(days: (d.weekday + 6) % 7))
            .copyWith(hour: 0, minute: 0, second: 0, millisecond: 0);
        final sunday = monday.add(const Duration(days: 7));
        return DateTimeRange(start: monday, end: sunday);
      case Period.month:
        final first = DateTime(d.year, d.month, 1);
        final next = DateTime(d.year, d.month + 1, 1);
        return DateTimeRange(start: first, end: next);
      case Period.quarter:
        final q = ((d.month - 1) ~/ 3) + 1; // 1..4
        final startMonth = (q - 1) * 3 + 1;
        final start = DateTime(d.year, startMonth, 1);
        final end = DateTime(d.year, startMonth + 3, 1);
        return DateTimeRange(start: start, end: end);
      case Period.year:
        final start = DateTime(d.year, 1, 1);
        final end = DateTime(d.year + 1, 1, 1);
        return DateTimeRange(start: start, end: end);
    }
  }

  String _rangeLabel(Period p, DateTime d) {
    final r = _rangeFor(p, d);
    final df = DateFormat('dd/MM/yyyy');
    switch (p) {
      case Period.week:
        return 'Tuần ${df.format(r.start)}–${df.format(r.end.subtract(const Duration(days:1)))}';
      case Period.month:
        return 'Tháng ${d.month}/${d.year}';
      case Period.quarter:
        final q = ((d.month - 1) ~/ 3) + 1;
        return 'Quý $q/${d.year}';
      case Period.year:
        return 'Năm ${d.year}';
    }
  }

  // parse bản ghi
  DateTime? _parseDt(dynamic v) {
    if (v == null) return null;
    if (v is String) {
      try { return DateTime.parse(v).toLocal(); } catch (_) {}
    }
    return null;
  }

  // Lọc theo khoảng thời gian
  List<Map<String, dynamic>> _filtered() {
    final r = _rangeFor(_period, _anchor);
    final start = r.start, end = r.end;
    return _attendances.map((a) {
      final checkIn = _parseDt(a['checkIn']);
      final checkOut = _parseDt(a['checkOut']);
      return {
        'name': a['fullName'] ?? a['employeeName'] ?? '',
        'email': a['email'] ?? a['employeeEmail'] ?? '',
        'checkIn': checkIn,
        'checkOut': checkOut,
        'hourlyRate': (a['hourlyRate'] ?? 0).toDouble(),
      };
    }).where((x) {
      final ci = x['checkIn'] as DateTime?;
      return ci != null && (ci.isAtSameMomentAs(start) || (ci.isAfter(start) && ci.isBefore(end)));
    }).toList();
  }

  // Tổng hợp theo nhân viên
  List<Map<String, dynamic>> _summaryByEmployee() {
    final data = _filtered();
    final byEmail = <String, Map<String, dynamic>>{};
    for (final r in data) {
      final email = r['email'] as String;
      final name = r['name'] as String;
      final hourly = r['hourlyRate'] as double;
      final ci = r['checkIn'] as DateTime?;
      final co = r['checkOut'] as DateTime? ?? ci;
      final hours = ci != null && co != null ? co.difference(ci).inMinutes / 60.0 : 0.0;

      byEmail.putIfAbsent(email, () => {
        'name': name,
        'email': email,
        'hourlyRate': hourly,
        'hours': 0.0,
        'salary': 0.0,
      });
      byEmail[email]!['hours'] += hours;
      byEmail[email]!['salary'] = (byEmail[email]!['hours'] as double) * hourly;
    }
    final list = byEmail.values.toList();
    list.sort((a,b)=> (b['salary'] as double).compareTo(a['salary'] as double));
    return list;
  }

  Future<void> _pickAnchorDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchor,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Chọn ngày gốc cho bộ lọc',
    );
    if (picked != null) setState(() => _anchor = picked);
  }

  // ========= Export Excel =========
  Future<void> _exportExcel() async {
    final detail = _filtered();
    if (detail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có dữ liệu trong khoảng đã chọn.')),
      );
      return;
    }
    final summary = _summaryByEmployee();

    final book = Excel.createExcel();
    final sheetDetail = book['Detail'];
    final sheetSummary = book['Summary-${_period.name.toUpperCase()}'];

    // Header
    sheetDetail.appendRow(['Họ tên', 'Email', 'Check-in', 'Check-out', 'Giờ công', 'Lương/Giờ', 'Tiền công']);
    for (final r in detail) {
      final ci = r['checkIn'] as DateTime?;
      final co = r['checkOut'] as DateTime?;
      final hours = (ci != null && co != null) ? co.difference(ci).inMinutes / 60.0 : 0.0;
      final hourly = r['hourlyRate'] as double;
      sheetDetail.appendRow([
        r['name'], r['email'],
        ci != null ? _fmt.format(ci) : '',
        co != null ? _fmt.format(co) : '',
        hours.toStringAsFixed(2),
        hourly.toStringAsFixed(0),
        (hours * hourly).toStringAsFixed(0),
      ]);
    }

    sheetSummary.appendRow(['Họ tên', 'Email', 'Tổng giờ', 'Lương/Giờ', 'Tổng lương']);
    double grand = 0;
    for (final s in summary) {
      sheetSummary.appendRow([
        s['name'], s['email'],
        (s['hours'] as double).toStringAsFixed(2),
        (s['hourlyRate'] as double).toStringAsFixed(0),
        (s['salary'] as double).toStringAsFixed(0),
      ]);
      grand += s['salary'] as double;
    }
    sheetSummary.appendRow([]);
    sheetSummary.appendRow(['', '', '', 'TỔNG', grand.toStringAsFixed(0)]);

    // Lưu file
    final bytes = book.encode()!;
    final dir = await getTemporaryDirectory();
    final label = _rangeLabel(_period, _anchor).replaceAll(' ', '');
    final path = '${dir.path}/Attendance_${_period.name}_$label.xlsx';
    final f = File(path)..writeAsBytesSync(bytes);

    // Share / mở file
    await Share.shareXFiles([XFile(path)], text: 'Báo cáo $_period - $label');
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered();
    final summary = _summaryByEmployee();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bảng chấm công & tính lương (ADMIN)'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchAttendances),
          IconButton(icon: const Icon(Icons.download), tooltip: 'Xuất Excel', onPressed: _exportExcel),
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
            // Bộ lọc
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<Period>(
                  value: _period,
                  items: const [
                    DropdownMenuItem(value: Period.week, child: Text('Tuần')),
                    DropdownMenuItem(value: Period.month, child: Text('Tháng')),
                    DropdownMenuItem(value: Period.quarter, child: Text('Quý')),
                    DropdownMenuItem(value: Period.year, child: Text('Năm')),
                  ],
                  onChanged: (v) => setState(()=> _period = v ?? Period.month),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text(_rangeLabel(_period, _anchor)),
                  onPressed: _pickAnchorDate,
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.download),
                  onPressed: _exportExcel,
                  label: const Text('Xuất Excel'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Chi tiết (${list.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Không có dữ liệu trong khoảng chọn.'))
                  : ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final r = list[i];
                  final ci = r['checkIn'] as DateTime?;
                  final co = r['checkOut'] as DateTime?;
                  final hours = (ci != null && co != null) ? co.difference(ci).inMinutes / 60.0 : 0.0;
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.access_time),
                      title: Text(r['name']),
                      subtitle: Text('${r['email']}\nVào: ${ci!=null?_fmt.format(ci):'-'}\nRa: ${co!=null?_fmt.format(co):'-'}\nGiờ: ${hours.toStringAsFixed(2)}'),
                      isThreeLine: true,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text('Tổng hợp theo nhân viên', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Nhân viên')),
                  DataColumn(label: Text('Email')),
                  DataColumn(label: Text('Giờ công')),
                  DataColumn(label: Text('Lương/Giờ')),
                  DataColumn(label: Text('Tổng lương')),
                ],
                rows: summary.map((s) {
                  return DataRow(cells: [
                    DataCell(Text(s['name'])),
                    DataCell(Text(s['email'])),
                    DataCell(Text((s['hours'] as double).toStringAsFixed(2))),
                    DataCell(Text((s['hourlyRate'] as double).toStringAsFixed(0))),
                    DataCell(Text((s['salary'] as double).toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.bold))),
                  ]);
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
