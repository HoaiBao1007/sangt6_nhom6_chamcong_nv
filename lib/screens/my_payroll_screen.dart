import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../state/auth_state.dart';
import '../widgets/config.dart';

enum Period { month, quarter, year }

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

  // ✅ Lọc dữ liệu theo kỳ
  List<dynamic> _filtered() {
    if (_payrolls.isEmpty) return [];
    final year = _anchor.year;
    switch (_period) {
      case Period.month:
        final month = _anchor.month.toString().padLeft(2, '0');
        return _payrolls.where((p) => p['period'] == '$year-$month').toList();
      case Period.quarter:
        final q = ((DateTime.now().month - 1) ~/ 3) + 1;
        final months = List.generate(3, (i) => ((q - 1) * 3 + i + 1).toString().padLeft(2, '0'));
        return _payrolls.where((p) {
          return p['period'].toString().startsWith('$year-') &&
              months.any((m) => p['period'].toString().endsWith(m));
        }).toList();
      case Period.year:
        return _payrolls.where((p) => p['period'].toString().startsWith('$year-')).toList();
    }
  }

  String _rangeLabel(Period p, DateTime d) {
    switch (p) {
      case Period.month:
        return 'Tháng ${d.month}/${d.year}';
      case Period.quarter:
        final q = ((d.month - 1) ~/ 3) + 1;
        return 'Quý $q/${d.year}';
      case Period.year:
        return 'Năm ${d.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered();
    final fmt = NumberFormat.currency(locale: "vi_VN", symbol: "₫");
    final total = list.fold<double>(0, (sum, e) => sum + (e['totalSalary'] as num).toDouble());

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
              children: [
                ToggleButtons(
                  borderRadius: BorderRadius.circular(12),
                  selectedColor: Colors.white,
                  fillColor: Theme.of(context).primaryColor,
                  isSelected: [
                    _period == Period.month,
                    _period == Period.quarter,
                    _period == Period.year,
                  ],
                  onPressed: (i) => setState(() => _period = Period.values[i]),
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text("Tháng"),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text("Quý"),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text("Năm"),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
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
                          "Giờ công: ${p['totalHours']}h\nLương: ${fmt.format(p['totalSalary'])}"),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Tổng lương kỳ này: ${fmt.format(total)}",
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal),
            ),
          ],
        ),
      ),
    );
  }
}
