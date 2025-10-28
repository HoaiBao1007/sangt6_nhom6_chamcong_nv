import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sangt6_nhom6_chamcong_nv/screens/report_screen.dart';
import '../state/auth_state.dart';
import '../widgets/config.dart';
import 'change_password_screen.dart'; // ✅ Trang đổi mật khẩu

// Đủ 5 kỳ
enum Period { day, week, month, quarter, year }

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
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

  // =================== PAYROLL CALC HELPERS ===================

  String _isoUtc(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day, 0, 0, 0).toIso8601String();

  DateTime _startOfWeek(DateTime d) {
    final weekday = d.weekday; // 1..7 (Mon..Sun)
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: weekday - 1));
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
        final q = ((anchor.month - 1) ~/ 3) + 1; // 1..4
        final startMonth = (q - 1) * 3 + 1; // 1,4,7,10
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

  Future<void> _callCalculateRange({
    required String startIso,
    required String endIso,
    required String label,
  }) async {
    final token = context.read<AuthState>().token;
    if (token == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Bạn chưa đăng nhập!')),
      );
      return;
    }

    final uri = Uri.parse('${AppConfig.baseUrl}/api/payroll/calculate-range')
        .replace(queryParameters: {
      'start': startIso,
      'end': endIso,
      'label': label,
    });

    try {
      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: '{}',
      );

      if (!mounted) return;

      final bodyText = res.body.isEmpty ? '(empty body)' : res.body;

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = res.body.isEmpty ? {} : jsonDecode(res.body);
        final msg = data['message'] ?? 'Đã tính lương.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ $msg (label: ${data['label'] ?? label})')),
        );
        _fetchPayrolls();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi tính lương [${res.statusCode} ${res.reasonPhrase}]: $bodyText'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ Lỗi kết nối: $e')),
      );
    }
  }

  // =================== SEND EMAIL SUMMARY (NEW) ===================

  // Gửi email báo cáo theo kỳ đang chọn: chỉ áp dụng Month/Quarter/Year.

  // Gửi email báo cáo THÁNG (tự tính lương nếu chưa có, rồi gửi lại).
  Future<void> _sendMonthlyEmails() async {
    final token = context.read<AuthState>().token;
    if (token == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Bạn chưa đăng nhập!')),
      );
      return;
    }

    // Dù đang ở Day/Week/Quarter/Year thì API gửi mail vẫn cần THÁNG
    final int year = _anchor.year;
    final int month = _anchor.month;

    Future<http.Response> _postSend() {
      final uri = Uri.parse('${AppConfig.baseUrl}/api/report/send-summary')
          .replace(queryParameters: {'year': '$year', 'month': '$month'});
      return http.post(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      });
    }

    // Thử gửi ngay lần 1
    http.Response res;
    try {
      res = await _postSend();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ Lỗi kết nối: $e')),
      );
      return;
    }

    // Thành công
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = res.body.isEmpty ? {} : jsonDecode(res.body);
      final sent = data['sent'] ?? 0;
      final failed = data['failed'] ?? 0;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Đã gửi báo cáo tháng $month/$year — thành công: $sent, lỗi: $failed')),
      );
      return;
    }

    // Nếu 400 vì chưa có payroll -> tự tính lương tháng rồi gửi lại
    final bodyText = res.body;
    final isNoPayroll =
        res.statusCode == 400 && bodyText.toLowerCase().contains('chưa có payroll');

    if (isNoPayroll) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⏳ Chưa có bảng lương tháng này. Đang tự tính lương và gửi lại...')),
      );

      // Tính lương THÁNG hiện tại của anchor
      final start = DateTime(year, month, 1);
      final end = DateTime(year, month + 1, 1);
      final label = '${year}-${month.toString().padLeft(2, '0')}';

      try {
        final calcUri = Uri.parse('${AppConfig.baseUrl}/api/payroll/calculate-range')
            .replace(queryParameters: {
          'start': DateTime.utc(start.year, start.month, start.day).toIso8601String(),
          'end': DateTime.utc(end.year, end.month, end.day).toIso8601String(),
          'label': label,
        });

        final calcRes = await http.post(
          calcUri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: '{}',
        );

        if (calcRes.statusCode < 200 || calcRes.statusCode >= 300) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Tính lương lỗi: ${calcRes.statusCode} ${calcRes.body}')),
          );
          return;
        }

        // Tính lương xong, gửi lại
        final retry = await _postSend();
        if (retry.statusCode >= 200 && retry.statusCode < 300) {
          final data = retry.body.isEmpty ? {} : jsonDecode(retry.body);
          final sent = data['sent'] ?? 0;
          final failed = data['failed'] ?? 0;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ Đã gửi báo cáo tháng $month/$year — thành công: $sent, lỗi: $failed')),
          );
          // refresh bảng lương sau khi tính
          _fetchPayrolls();
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Gửi lại thất bại: ${retry.statusCode} ${retry.body}')),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ Lỗi khi tự tính/gửi lại: $e')),
        );
      }
      return;
    }

    // Các lỗi khác
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('❌ Lỗi gửi email: ${res.statusCode} $bodyText')),
    );
  }

  // =================== DATA FETCH & FILTER ===================

  Future<void> _fetchPayrolls() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = context.read<AuthState>().token;
      final uri = Uri.parse('${AppConfig.baseUrl}/api/payroll/all');
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

  // ======== Lọc CHUẨN theo định dạng label của từng kỳ ========
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

  // ✅ Lọc chính xác theo kỳ (không lẫn ngày/tuần khi xem tháng/quý/năm)
  List<Map<String, dynamic>> _filteredPayrolls() {
    return _payrolls.where((p) {
      final label = (p['period'] ?? '').toString();
      return _labelMatches(label, _period, _anchor);
    }).map((p) => {
      'period': p['period'],
      'employeeName': p['employeeName'] ?? '',
      'totalHours': p['totalHours'] ?? 0,
      'totalSalary': p['totalSalary'] ?? 0,
    }).toList();
  }

  String _rangeLabel(Period p, DateTime d) {
    switch (p) {
      case Period.day:
        return DateFormat('dd/MM/yyyy').format(d);
      case Period.week:
        final weekNumber = _weekNumber(d);
        return 'Tuần $weekNumber/${d.year}';
      case Period.month:
        return DateFormat('MM/yyyy').format(d);
      case Period.quarter:
        final q = ((d.month - 1) ~/ 3) + 1;
        return 'Q$q/${d.year}';
      case Period.year:
        return '${d.year}';
    }
  }

  // ======= Bộ điều hướng kỳ: lùi/tiến theo Period =======
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

  // ======= Picker chọn kỳ để nhảy tới bất kỳ thời điểm =======
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
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Đóng'),
              ),
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

  // =================== BUILD ===================

  @override
  Widget build(BuildContext context) {
    final list = _filteredPayrolls();
    final totalSalary =
    list.fold<double>(0, (sum, s) => sum + (s['totalSalary'] as num).toDouble());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bảng lương & chấm công (ADMIN)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calculate),
            tooltip: 'Tính lương theo kỳ',
            onPressed: () async {
              final r = _makeRange(_period, _anchor);
              await _callCalculateRange(startIso: r.startIso, endIso: r.endIso, label: r.label);
            },
          ),
          IconButton(
            icon: const Icon(Icons.email),
            tooltip: 'Gửi email báo cáo (Tháng/Quý/Năm)',
            onPressed: _sendMonthlyEmails, // ✅ NÚT GỬI EMAIL
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchPayrolls,
          ),
          IconButton(
            icon: const Icon(Icons.lock_reset),
            tooltip: "Đổi mật khẩu",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
              );
            },
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
            // ======= Thanh chọn kỳ + điều hướng =======
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
                IconButton(
                  icon: const Icon(Icons.assessment),
                  tooltip: 'Báo cáo thống kê',
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportScreen()));
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            Text(
              'Bảng lương (${list.length}) kỳ: ${_rangeLabel(_period, _anchor)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Không có dữ liệu lương.'))
                  : ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final p = list[i];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.payments),
                      title: Text(p['employeeName']),
                      subtitle: Text(
                        'Kỳ: ${p['period']}\nGiờ: ${p['totalHours']}h\nLương: ${NumberFormat.currency(locale: "vi_VN", symbol: "₫").format(p['totalSalary'])}',
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '💰 Tổng chi phí kỳ này: ${NumberFormat.currency(locale: "vi_VN", symbol: "₫").format(totalSalary)}',
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
