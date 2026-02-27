import 'dart:async';

import 'package:flutter/material.dart';

import '../services/attendance_service.dart';

class AttendanceCard extends StatefulWidget {
  final String userId;
  final String userName;

  const AttendanceCard({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<AttendanceCard> createState() => _AttendanceCardState();
}

class _AttendanceCardState extends State<AttendanceCard> {
  Map<String, dynamic>? _summary;
  bool _isLoading = true;
  bool _isActionLoading = false;
  Timer? _timer;

  String get _status => _summary?['status'] ?? 'not_punched_in';

  @override
  void initState() {
    super.initState();
    _loadSummary();
    _startTicker();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    return 0;
  }

  void _startTicker() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _summary == null) return;
      final status = _summary!['status'];
      if (status != 'working' && status != 'on_break') return;
      // Just trigger rebuild; durations are computed from punch-in time.
      setState(() {});
    });
  }

  Future<void> _loadSummary() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final response = await AttendanceService.getToday(widget.userId);
      setState(() {
        _summary = response;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showSnack(
        e.toString().replaceFirst('Exception: ', '').trim(),
        isError: true,
      );
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String _formatTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '--';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '${hour.toString().padLeft(2, '0')}:$minute $period';
    } catch (_) {
      return '--';
    }
  }

  String _formatDuration(dynamic seconds) {
    final total = _asInt(seconds);
    final d = Duration(seconds: total);
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$secs';
  }

  Future<void> _handlePunchIn() async {
    if (_isActionLoading) return;
    setState(() => _isActionLoading = true);
    try {
      final response = await AttendanceService.punchIn(widget.userId);
      if (response['status'] == 'success') {
        _summary = response['data'] as Map<String, dynamic>?;
        _showSnack('Punched in successfully.');
      } else {
        _showSnack(
          (response['message'] ?? 'Unable to punch in.').toString(),
          isError: true,
        );
      }
      setState(() {});
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', '').trim(),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isActionLoading = false);
      }
    }
  }

  Future<void> _handlePunchOut() async {
    if (_isActionLoading) return;

    if (_status == 'not_punched_in') {
      _showSnack('Please punch in first.', isError: true);
      return;
    }

    if (_status == 'on_break') {
      _showSnack(
        'You are on break. End the break before punching out.',
        isError: true,
      );
      return;
    }

    final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Confirm Punch Out'),
            content: const Text('Are you sure you want to punch out now?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Punch Out'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    setState(() => _isActionLoading = true);
    try {
      final response = await AttendanceService.punchOut(widget.userId);
      if (response['status'] == 'success') {
        _summary = response['data'] as Map<String, dynamic>?;
        _showSnack('Punched out successfully.');
      } else {
        _showSnack(
          (response['message'] ?? 'Unable to punch out.').toString(),
          isError: true,
        );
      }
      setState(() {});
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', '').trim(),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isActionLoading = false);
      }
    }
  }

  Future<void> _handleBreakStart(String type) async {
    if (_status == 'not_punched_in') {
      _showSnack('Please punch in before starting a break.', isError: true);
      return;
    }

    if (_status == 'on_break') {
      final current = _summary?['current_break'] as Map<String, dynamic>?;
      final currentType = current?['type'] ?? '';
      _showSnack(
        'You are already on a $currentType break.',
        isError: true,
      );
      return;
    }

    String? reason;
    String title;
    String message;

    switch (type) {
      case 'tea':
        title = 'Start Tea Break';
        message = 'Do you want to start a tea break now?';
        break;
      case 'lunch':
        title = 'Start Lunch Break';
        message = 'Do you want to start a lunch break now?';
        break;
      default:
        title = 'Start Emergency Break';
        message = 'Enter a reason for emergency break:';
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            final isEmergency = type == 'emergency';
            final controller = TextEditingController();
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(title),
              content: isEmergency
                  ? TextField(
                      controller: controller,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Reason',
                        border: OutlineInputBorder(),
                      ),
                    )
                  : Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (isEmergency &&
                        controller.text.trim().isEmpty) {
                      return;
                    }
                    reason = controller.text.trim();
                    Navigator.pop(context, true);
                  },
                  child: const Text('Start'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _isActionLoading = true);
    try {
      final response = await AttendanceService.startBreak(
        userId: widget.userId,
        type: type,
        reason: reason,
      );
      if (response['status'] == 'success') {
        _summary = response['data'] as Map<String, dynamic>?;
        _showSnack(
          '${type[0].toUpperCase()}${type.substring(1)} break started.',
        );
      } else {
        _showSnack(
          (response['message'] ?? 'Unable to start break.').toString(),
          isError: true,
        );
      }
      setState(() {});
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', '').trim(),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isActionLoading = false);
      }
    }
  }

  Future<void> _handleEndBreak() async {
    if (_status != 'on_break') {
      _showSnack('No active break to end.', isError: true);
      return;
    }

    setState(() => _isActionLoading = true);
    try {
      final response = await AttendanceService.endBreak(widget.userId);
      if (response['status'] == 'success') {
        _summary = response['data'] as Map<String, dynamic>?;
        _showSnack('Break ended.');
      } else {
        _showSnack(
          (response['message'] ?? 'Unable to end break.').toString(),
          isError: true,
        );
      }
      setState(() {});
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', '').trim(),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isActionLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentBreak =
        _summary?['current_break'] as Map<String, dynamic>?;
    final onBreak = _status == 'on_break' && currentBreak != null;

    final breakLabel = onBreak
        ? '${(currentBreak['type'] as String).toString().toUpperCase()} BREAK'
        : 'No active break';
    final breakDuration = onBreak
        ? _formatDuration(currentBreak['duration_seconds'])
        : '--';

    final punchInIso = _summary?['punch_in_time'] as String?;
    final punchOutIso = _summary?['punch_out_time'] as String?;
    final punchInTime = _formatTime(punchInIso);

    int workSeconds = 0;
    if (punchInIso != null && punchInIso.isNotEmpty) {
      final punchIn = DateTime.parse(punchInIso).toLocal();
      final now = DateTime.now();
      final end = punchOutIso != null && punchOutIso.isNotEmpty
          ? DateTime.parse(punchOutIso).toLocal()
          : now;

      final baseBreak = _asInt(_summary?['break_duration_seconds']);
      int extraActiveBreak = 0;
      if (onBreak && currentBreak['started_at'] != null) {
        final started =
            DateTime.parse(currentBreak['started_at'] as String).toLocal();
        final already = _asInt(currentBreak['duration_seconds']);
        final currentTotal = now.difference(started).inSeconds;
        extraActiveBreak = (currentTotal - already).clamp(0, 1 << 31);
      }
      final totalBreakSeconds = baseBreak + extraActiveBreak;
      workSeconds =
          (end.difference(punchIn).inSeconds - totalBreakSeconds).clamp(0, 1 << 31);
    }

    final workDuration = _formatDuration(workSeconds);
    final totalBreakDuration =
        _formatDuration(_summary?['break_duration_seconds']);

    final isWorking = _status == 'working' || _status == 'on_break';
    final buttonLabel = isWorking ? 'Punch Out' : 'Punch In';
    final buttonIcon = isWorking ? Icons.logout : Icons.login;
    final buttonColor =
        isWorking ? Colors.red.shade600 : Colors.green.shade600;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFceb56e), Color(0xFFd4c088)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFceb56e).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _isLoading
            ? const SizedBox(
                height: 80,
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _infoChip(Icons.login, 'Punch In', punchInTime),
                      _infoChip(Icons.timer, 'Work', workDuration),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _infoChip(Icons.work_history, 'Breaks', totalBreakDuration),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Hi, ${widget.userName}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _status == 'not_punched_in'
                        ? 'Tap Punch In to start your day.'
                        : _status == 'completed'
                            ? 'You have completed today\'s attendance.'
                            : onBreak
                                ? 'On $breakLabel • $breakDuration'
                                : 'You are currently working.',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _breakButton(
                        context,
                        icon: Icons.coffee,
                        title: 'Tea',
                        onTap: _isActionLoading
                            ? null
                            : () => _handleBreakStart('tea'),
                        isActive:
                            onBreak && currentBreak['type'] == 'tea',
                      ),
                      _breakButton(
                        context,
                        icon: Icons.restaurant,
                        title: 'Lunch',
                        onTap: _isActionLoading
                            ? null
                            : () => _handleBreakStart('lunch'),
                        isActive:
                            onBreak && currentBreak['type'] == 'lunch',
                      ),
                      _breakButton(
                        context,
                        icon: Icons.emergency,
                        title: 'Emergency',
                        onTap: _isActionLoading
                            ? null
                            : () => _handleBreakStart('emergency'),
                        isActive:
                            onBreak && currentBreak['type'] == 'emergency',
                      ),
                    ],
                  ),
                  if (onBreak) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _isActionLoading ? null : _handleEndBreak,
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text(
                          'End Break & Resume Work',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: buttonColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      onPressed: _isActionLoading
                          ? null
                          : (isWorking ? _handlePunchOut : _handlePunchIn),
                      icon: _isActionLoading
                          ? const SizedBox.shrink()
                          : Icon(buttonIcon),
                      label: _isActionLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              buttonLabel,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFFceb56e)),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _breakButton(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback? onTap,
    required bool isActive,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            onPressed: onTap,
            icon: Icon(
              icon,
              color: isActive
                  ? Colors.red.shade600
                  : const Color(0xFFceb56e),
            ),
            iconSize: 24,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

