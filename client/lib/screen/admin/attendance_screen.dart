import 'package:flutter/material.dart';

import '../../services/attendance_service.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _items = [];
  Map<String, dynamic>? _meta;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadOverview();
  }

  String get _selectedDateString =>
      '${_selectedDate.year.toString().padLeft(4, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      await _loadOverview();
    }
  }

  Future<void> _loadOverview() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response =
          await AttendanceService.getOverview(date: _selectedDateString);
      if (response['status'] == 'success') {
        setState(() {
          _items = (response['data'] as List<dynamic>? ?? []);
          _meta = response['meta'] as Map<String, dynamic>?;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage =
              (response['message'] ?? 'Failed to load attendance.').toString();
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage =
            e.toString().replaceFirst('Exception: ', '').trim();
        _isLoading = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'working':
        return Colors.green.shade600;
      case 'on_break':
        return Colors.orange.shade600;
      case 'completed':
        return Colors.blue.shade600;
      default:
        return Colors.grey.shade500;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'working':
        return 'Active';
      case 'on_break':
        return 'On Break';
      case 'completed':
        return 'Completed';
      case 'not_punched_in':
      default:
        return 'Absent';
    }
  }

  String _formatDuration(dynamic seconds) {
    int total;
    if (seconds == null) {
      total = 0;
    } else if (seconds is int) {
      total = seconds;
    } else if (seconds is double) {
      total = seconds.round();
    } else if (seconds is String) {
      total = int.tryParse(seconds) ?? 0;
    } else {
      total = 0;
    }

    final d = Duration(seconds: total);
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  @override
  Widget build(BuildContext context) {
    final date = _meta?['date']?.toString() ?? _selectedDateString;
    final present = _meta?['present_count'] ?? 0;
    final absent = _meta?['absent_count'] ?? 0;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadOverview,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time_outlined,
                size: 70, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'No employees found.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 18, color: Color(0xFFceb56e)),
                    const SizedBox(width: 8),
                    Text(
                      date,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down,
                        size: 18, color: Colors.black54),
                  ],
                ),
              ),
              const Spacer(),
              _chipSummary(
                color: Colors.green.shade600,
                icon: Icons.circle,
                label: 'Present',
                value: present.toString(),
              ),
              const SizedBox(width: 8),
              _chipSummary(
                color: Colors.red.shade500,
                icon: Icons.circle,
                label: 'Absent',
                value: absent.toString(),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadOverview,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index] as Map<String, dynamic>;
                final summary =
                    (item['attendance'] as Map<String, dynamic>?) ?? {};
                final status = (summary['status'] ?? 'not_punched_in').toString();
                final work = _formatDuration(summary['work_duration_seconds']);
                final breaks = _formatDuration(summary['break_duration_seconds']);

                return _attendanceCard(
                  name: (item['name'] ?? 'Unknown').toString(),
                  phone: (item['phone'] ?? '').toString(),
                  status: status,
                  work: work,
                  breaks: breaks,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _chipSummary({
    required Color color,
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _attendanceCard({
    required String name,
    required String phone,
    required String status,
    required String work,
    required String breaks,
  }) {
    final color = _statusColor(status);
    final label = _statusLabel(status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFFceb56e).withValues(alpha: 0.15),
                    child: Icon(
                      Icons.person_outline,
                      size: 20,
                      color: const Color(0xFFceb56e),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (phone.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            phone,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: color,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.timer_outlined,
                      size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    'Work: $work hrs',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.coffee_outlined,
                      size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    'Breaks: $breaks hrs',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

