import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/task_service.dart';
import '../../services/user_service.dart';
import '../../models/task_model.dart';
import 'create_task_screen.dart';

class TasksScreen extends StatefulWidget {
  final String userId;
  final String userRole;
  /// For admin: 'self' or 'employee'. Ignored for non-admin.
  final String initialViewMode;
  /// When true (from dashboard cards), hide the internal self/employee switch
  /// and lock the view to [initialViewMode].
  final bool lockViewMode;

  const TasksScreen({
    super.key,
    required this.userId,
    required this.userRole,
    this.initialViewMode = 'self',
    this.lockViewMode = false,
  });

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<Task> _tasks = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedFilter = 'all';
  String _selectedCategory = 'all';

  // Admin-specific state
  String _viewMode = 'self'; // 'self' or 'employee'
  List<Map<String, dynamic>> _employees = [];
  bool _isEmployeesLoading = false;
  String? _selectedEmployeeId;
  String? _selectedEmployeeName;
  String? _selectedEmployeePhone;
  bool _filtersExpanded = false;

  bool get _isManagerRole =>
      widget.userRole == 'admin' ||
      widget.userRole == 'subadmin' ||
      widget.userRole == 'techincharge';

  @override
  void initState() {
    super.initState();
    // Default to self-view; employees don't see extra options.
    // Manager roles can override via initialViewMode (from dashboard cards).
    if (_isManagerRole &&
        widget.initialViewMode.toLowerCase() == 'employee') {
      _viewMode = 'employee';
    } else {
      _viewMode = 'self';
    }
    _fetchTasks();
    if (_isManagerRole) {
      _loadEmployees();
    }
  }

  Widget _buildAdminModeSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'View tasks as',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildModeButton(
                  label: 'Self Tasks',
                  isSelected: _viewMode == 'self',
                  onTap: () {
                    if (_viewMode == 'self') return;
                    setState(() {
                      _viewMode = 'self';
                    });
                    _fetchTasks();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildModeButton(
                  label: 'Employee Tasks',
                  isSelected: _viewMode == 'employee',
                  onTap: () {
                    if (_viewMode == 'employee') return;
                    setState(() {
                      _viewMode = 'employee';
                    });
                    _fetchTasks();
                  },
                ),
              ),
            ],
          ),
          if (_viewMode == 'employee') ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _buildEmployeeSelector()),
                const SizedBox(width: 8),
                _buildEmployeeContactButtons(),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Header used when the view mode is locked from the dashboard cards.
  /// For employee mode, we still want to show which employee's tasks
  /// are being viewed, and allow changing the employee.
  Widget _buildLockedAdminHeader() {
    if (_viewMode != 'employee') {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Employee tasks',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildEmployeeSelector()),
              const SizedBox(width: 8),
              _buildEmployeeContactButtons(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeContactButtons() {
    final phone = _selectedEmployeePhone;
    final hasPhone = phone != null && phone.trim().isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCircleIconButton(
          icon: Icons.call,
          color: Colors.grey,
          enabled: hasPhone,
          onTap: hasPhone ? () => _launchPhone(phone) : null,
        ),
        const SizedBox(width: 6),
        _buildCircleIconButton(
          icon: Icons.call,
          color: Colors.green,
          enabled: hasPhone,
          onTap: hasPhone ? () => _launchWhatsApp(phone) : null,
        ),
      ],
    );
  }

  Widget _buildCircleIconButton({
    required IconData icon,
    required Color color,
    required bool enabled,
    VoidCallback? onTap,
  }) {
    final bg = enabled ? color.withValues(alpha: 0.1) : Colors.grey.shade200;
    final fg = enabled ? color : Colors.grey.shade400;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: fg),
        ),
      ),
    );
  }

  Future<void> _launchPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _launchWhatsApp(String phone) async {
  String normalized = phone.replaceAll(RegExp(r'[^0-9+]'), '');

  if (normalized.isEmpty) return;

  // Add India country code if missing
  if (!normalized.startsWith('+') && normalized.length == 10) {
    normalized = '91$normalized';
  }

  final Uri whatsappUri = Uri.parse("whatsapp://send?phone=$normalized");

  try {
    await launchUrl(
      whatsappUri,
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    final Uri webUri = Uri.parse("https://wa.me/$normalized");

    await launchUrl(
      webUri,
      mode: LaunchMode.externalApplication,
    );
  }
}

  Widget _buildModeButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFceb56e) : Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: const Color(0xFFceb56e),
            width: 1.2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFFceb56e),
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeSelector() {
    if (_isEmployeesLoading) {
      return Row(
        children: const [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text(
            'Loading employees...',
            style: TextStyle(fontSize: 12),
          ),
        ],
      );
    }

    if (_employees.isEmpty) {
      return const Text(
        'No employees found.',
        style: TextStyle(fontSize: 12, color: Colors.redAccent),
      );
    }

    final selectedText = _selectedEmployeeName ??
        'Select employee (${_employees.length} available)';

    return OutlinedButton.icon(
      onPressed: () async {
        final result = await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (context) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Choose Employee',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _employees.length,
                      itemBuilder: (context, index) {
                        final emp = _employees[index];
                        final code = emp['employeeCode'] as String? ?? '';
                        final name = emp['name'] as String? ?? 'Unknown';
                        final subtitle =
                            code.isNotEmpty ? 'Code: $code' : null;
                        return ListTile(
                          title: Text(name),
                          subtitle:
                              subtitle != null ? Text(subtitle) : null,
                          onTap: () {
                            Navigator.pop(context, emp);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );

        if (result != null && mounted) {
          setState(() {
            _selectedEmployeeId = result['id'] as String?;
            _selectedEmployeeName = result['name'] as String?;
            _selectedEmployeePhone = result['phone'] as String?;
          });
          _fetchTasks();
        }
      },
      icon: const Icon(Icons.people_alt_outlined, size: 18),
      label: Text(
        selectedText,
        style: const TextStyle(fontSize: 13),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: const BorderSide(color: Color(0xFFceb56e)),
        foregroundColor: const Color(0xFFceb56e),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
    );
  }

  Future<void> _fetchTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Decide which user and role to use based on current view
      String userId = widget.userId;
      String userRole = widget.userRole;

      if (_isManagerRole && _viewMode == 'employee') {
        // When viewing employee tasks, require a selected employee
        if (_selectedEmployeeId == null) {
          setState(() {
            _tasks = [];
            _isLoading = false;
          });
          return;
        }
        userId = _selectedEmployeeId!;
        userRole = 'employee';
      }

      final response = await TaskService.getTasks(
        userId,
        userRole,
      );

      if (response['status'] == 'success') {
        final List<dynamic> tasksData = response['data'] ?? [];
        var tasks = tasksData.map((json) => Task.fromJson(json)).toList();

        // For manager self view, show only true self tasks:
        // created_by == manager AND assigned_to == manager.
        if (_isManagerRole && _viewMode == 'self') {
          tasks = tasks
              .where((task) =>
                  task.createdBy == widget.userId &&
                  task.assignedTo == widget.userId)
              .toList();
        }

        setState(() {
          _tasks = tasks;
          _isLoading = false;
        });
      } else {
        final message =
            (response['message'] ?? 'Failed to load tasks').toString();
        setState(() {
          _errorMessage = message;
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.red.shade600,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    } catch (e) {
      String message =
          e.toString().replaceFirst('Exception: ', '').trim();

      if (message.contains('Connection refused') ||
          message.contains('Failed host lookup')) {
        message =
            'Cannot connect to server.\nPlease ensure the Laravel backend is running.';
      } else if (message.isEmpty) {
        message = 'Unexpected error while loading tasks.';
      }

      setState(() {
        _errorMessage = message;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _isEmployeesLoading = true;
    });

    try {
      final response = await UserService.getUsers(perPage: 100);
      if (response['status'] == 'success') {
        final List<dynamic> data = response['data'] ?? [];

        String _mapAppRole(Map<String, dynamic> u) {
          final roleId = u['roleId']?.toString();
          switch (roleId) {
            case 'R001':
              return 'admin';
            case 'R006':
              return 'subadmin';
            case 'R007':
              return 'techincharge';
            default:
              return 'employee';
          }
        }

        bool _canCurrentUserAssignTo(String appRole) {
          switch (widget.userRole) {
            case 'admin':
              // Admin -> subadmin, techincharge, employee
              return appRole == 'subadmin' ||
                  appRole == 'techincharge' ||
                  appRole == 'employee';
            case 'subadmin':
              // Subadmin -> techincharge, employee
              return appRole == 'techincharge' || appRole == 'employee';
            case 'techincharge':
              // Tech incharge -> employee only
              return appRole == 'employee';
            default:
              return false;
          }
        }

        setState(() {
          _employees = data
              .map<Map<String, dynamic>?>((raw) {
                final map = Map<String, dynamic>.from(raw as Map);
                final appRole = _mapAppRole(map);
                if (!_canCurrentUserAssignTo(appRole)) return null;
                final id = map['id']?.toString() ?? '';
                if (id.isEmpty) return null;
                return {
                  'id': id,
                  'name': map['name']?.toString() ?? 'Unknown',
                  'employeeCode': map['employeeCode']?.toString() ?? '',
                  'phone': map['contactNumber']?.toString() ?? '',
                  'role': appRole,
                };
              })
              .whereType<Map<String, dynamic>>()
              .toList();
          _isEmployeesLoading = false;
        });
      } else {
        setState(() {
          _isEmployeesLoading = false;
        });
      }
    } catch (_) {
      setState(() {
        _isEmployeesLoading = false;
      });
    }
  }

  List<Task> get _filteredTasks {
    var list = _tasks;
    if (_selectedFilter != 'all') {
      list = list.where((task) => task.status == _selectedFilter).toList();
    }
    if (_selectedCategory != 'all') {
      list = list.where((task) => task.category == _selectedCategory).toList();
    }
    return list;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'assigned':
        return Colors.grey;
      case 'in_progress':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'paused':
        return Colors.amber;
      case 'need_help':
        return Colors.red;
      case 'ignore':
        return Colors.brown;
      default:
        return Colors.grey;
    }
  }

  static const _taskStatuses = [
    'assigned',
    'in_progress',
    'completed',
    'paused',
    'need_help',
    'ignore',
  ];

  Color _getSubtaskStatusColor(String status) => _getStatusColor(status);

  bool _canChangeTaskStatus(Task task) {
    return task.assignedTo == widget.userId;
  }

  Future<void> _updateSubtaskStatus(
    Task task,
    int index,
    String newStatus, {
    String? statusNote,
  }) async {
    final list = task.subtasksWithStatus;
    if (index < 0 || index >= list.length) return;
    final updated = list.asMap().entries.map((e) {
      final st = e.value;
      final isTarget = e.key == index;
      final status = isTarget ? newStatus : st.status;
      final map = <String, dynamic>{'text': st.text, 'status': status};
      if (isTarget && statusNote != null && statusNote.isNotEmpty) {
        map['need_help_note'] = statusNote;
      } else if (st.needHelpNote != null && st.needHelpNote!.isNotEmpty) {
        map['need_help_note'] = st.needHelpNote;
      }
      return map;
    }).toList();
    try {
      await TaskService.updateTask(task.id, {'subtasks': updated});
      if (!mounted) return;
      _fetchTasks();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '').trim())),
      );
    }
  }

  Future<void> _showSubtaskStatusPicker({
    required BuildContext context,
    required String currentStatus,
    required Future<void> Function(String) onSelected,
  }) async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Subtask status',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _taskStatuses.map((s) {
                    final selected = s == currentStatus;
                    final color = _getStatusColor(s);
                    return ChoiceChip(
                      label: Text(
                        s.replaceAll('_', ' '),
                        style: TextStyle(
                          fontSize: 13,
                          color: selected ? color : Colors.grey.shade800,
                        ),
                      ),
                      selected: selected,
                      onSelected: (_) async {
                        Navigator.pop(ctx);
                        await onSelected(s);
                      },
                      selectedColor: color.withValues(alpha: 0.2),
                      backgroundColor: Colors.grey.shade100,
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getStatusBackground(String status) {
    switch (status) {
      case 'assigned':
        return Colors.grey.shade50;
      case 'in_progress':
        return Colors.orange.shade50;
      case 'completed':
        return Colors.green.shade50;
      case 'paused':
        return Colors.amber.shade50;
      case 'need_help':
        return Colors.red.shade50;
      case 'ignore':
        return Colors.brown.shade50;
      default:
        return Colors.grey.shade50;
    }
  }

  Future<String?> _showNeedHelpNoteDialog({
    String title = 'Status Note',
    String hint = 'Add a note for this status (optional)',
    bool allowEmpty = true,
  }) async {
    final controller = TextEditingController();
    final scaffoldContext = context;
    final result = await showDialog<String>(
      context: scaffoldContext,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.sticky_note_2_outlined,
                  color: Colors.brown, size: 26),
              const SizedBox(width: 10),
              Text(title),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Type note here...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final note = controller.text.trim();
                if (!allowEmpty && note.isEmpty) {
                  ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a note'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx, note);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    // Let Flutter dispose the controller with the dialog's widget tree.
    // Manually disposing here can cause lifecycle assertions if the
    // TextField is still mounted when this future completes.
    return result;
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'low':
        return Colors.blue;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.deepOrange;
      case 'critical':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'daily':
        return Icons.today;
      case 'project':
        return Icons.work;
      case 'personal':
        return Icons.person;
      case 'monthly':
        return Icons.calendar_month;
      case 'quarterly':
        return Icons.date_range;
      case 'yearly':
        return Icons.calendar_today;
      case 'other':
        return Icons.more_horiz;
      default:
        return Icons.task;
    }
  }

  Widget _buildTaskHistoryStrip(Task task) {
    // Use task history when available; for daily tasks fall back to a synthetic
    // 7-day window so the strip is always visible.
    List<DailyStatusEntry>? history = task.taskHistory;
    if ((history == null || history.isEmpty) && task.category == 'daily') {
      history = _buildDefaultDailyHistory();
    }
    if (history == null || history.isEmpty) return const SizedBox.shrink();

    final nonNullHistory = history;
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: nonNullHistory.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final entry = nonNullHistory[index];
          final color = _getStatusColor(entry.status);
          final date = entry.date.length >= 10 ? entry.date.substring(8, 10) : '';
          final month = entry.date.length >= 7 ? entry.date.substring(5, 7) : '';
          final label = '$date-$month';
          final hasNote = entry.note != null && entry.note!.isNotEmpty;

          return GestureDetector(
            onTap: () {
              _showHistoryEntryDialog(
                context: context,
                title: 'Task history',
                dateLabel: label,
                status: entry.status,
                note: entry.note,
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                // Always tint by status color so the strip clearly reflects
                // the status (e.g. green for completed) regardless of note.
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: color,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  if (hasNote) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.sticky_note_2_outlined,
                      size: 12,
                      color: color,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSubtaskHistoryStrip(Task task, int subtaskIndex) {
    // First try to read history coming from backend; for daily tasks without
    // history for this index, fall back to a synthetic 7-day window so the
    // strip is always visible.
    final map = task.subtaskHistory;
    List<DailyStatusEntry>? history =
        (map != null && map.containsKey(subtaskIndex))
            ? map[subtaskIndex]
            : null;
    if ((history == null || history.isEmpty) && task.category == 'daily') {
      history = _buildDefaultDailyHistory();
    }
    if (history == null || history.isEmpty) return const SizedBox.shrink();

    final nonNullHistory = history;
    return SizedBox(
      height: 26,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: nonNullHistory.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final entry = nonNullHistory[index];
          final color = _getStatusColor(entry.status);
          final date = entry.date.length >= 10 ? entry.date.substring(8, 10) : '';
          final month = entry.date.length >= 7 ? entry.date.substring(5, 7) : '';
          final label = '$date-$month';
          final hasNote = entry.note != null && entry.note!.isNotEmpty;

          return GestureDetector(
            onTap: () {
              _showHistoryEntryDialog(
                context: context,
                title: 'Subtask history',
                dateLabel: label,
                status: entry.status,
                note: entry.note,
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                // Always tint by status color so the strip clearly reflects
                // the status (e.g. green for completed) regardless of note.
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: color,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  if (hasNote) ...[
                    const SizedBox(width: 3),
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: color,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showHistoryEntryDialog({
    required BuildContext context,
    required String title,
    required String dateLabel,
    required String status,
    String? note,
  }) {
    final color = _getStatusColor(status);
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.history, color: color, size: 22),
              const SizedBox(width: 8),
              Text(title),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade700),
                  const SizedBox(width: 4),
                  Text(
                    dateLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.circle, size: 10, color: color),
                  const SizedBox(width: 6),
                  Text(
                    status.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
              if (note != null && note.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Status note',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  note,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Column(
          children: [
            if (_isManagerRole)
              widget.lockViewMode
                  ? _buildLockedAdminHeader()
                  : _buildAdminModeSelector(),
            _buildFilterChips(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? _buildErrorView()
                      : _filteredTasks.isEmpty
                          ? _buildEmptyView()
                          : _buildTaskList(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          // When admin is in "Employee Tasks" view, require an employee selection
          if (widget.userRole == 'admin' && _viewMode == 'employee') {
            final noEmployeeSelected = _selectedEmployeeId == null ||
                _selectedEmployeeId!.trim().isEmpty;
            if (noEmployeeSelected) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Please select an employee first'),
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
              return;
            }
          }

          CreateTaskAssignMode? assignMode;
          String? assignedToEmployeeId;
          String? assignedToEmployeeName;
          if (widget.userRole == 'admin') {
            if (_viewMode == 'self') {
              assignMode = CreateTaskAssignMode.self;
            } else if (_viewMode == 'employee' &&
                _selectedEmployeeId != null &&
                _selectedEmployeeId!.trim().isNotEmpty) {
              assignMode = CreateTaskAssignMode.employee;
              assignedToEmployeeId = _selectedEmployeeId;
              assignedToEmployeeName = _selectedEmployeeName;
            }
          }
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateTaskScreen(
                userId: widget.userId,
                userRole: widget.userRole,
                assignMode: assignMode,
                assignedToEmployeeId: assignedToEmployeeId,
                assignedToEmployeeName: assignedToEmployeeName,
              ),
            ),
          );
          if (result == true) {
            _fetchTasks();
          }
        },
        icon: const Icon(Icons.add_task),
        label: const Text('New Task'),
      ),
    );
  }

  /// Build a default 7-day history window (today and previous 6 days)
  /// with status `assigned` and no note, used when the backend has not yet
  /// recorded any daily history for a task or subtask.
  List<DailyStatusEntry> _buildDefaultDailyHistory() {
    final now = DateTime.now();
    final days = <DailyStatusEntry>[];
    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final yyyy = date.year.toString().padLeft(4, '0');
      final mm = date.month.toString().padLeft(2, '0');
      final dd = date.day.toString().padLeft(2, '0');
      days.add(
        DailyStatusEntry(
          date: '$yyyy-$mm-$dd',
          status: 'assigned',
          note: null,
        ),
      );
    }
    return days;
  }

  Widget _buildFilterChips() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _filtersExpanded
                      ? Icons.filter_list
                      : Icons.filter_list_outlined,
                  size: 20,
                  color: const Color(0xFF9E9E9E),
                ),
                padding: EdgeInsets.zero,
                onPressed: () {
                  setState(() => _filtersExpanded = !_filtersExpanded);
                },
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filters',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _buildFilterSummary(),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  _filtersExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                  color: const Color(0xFF9E9E9E),
                ),
                padding: EdgeInsets.zero,
                onPressed: () {
                  setState(() => _filtersExpanded = !_filtersExpanded);
                },
              ),
            ],
          ),
          if (_filtersExpanded) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All', 'all'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Assigned', 'assigned'),
                  const SizedBox(width: 8),
                  _buildFilterChip('In Progress', 'in_progress'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Completed', 'completed'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Paused', 'paused'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Need Help', 'need_help'),
                ],
              ),
            ),
            if (_isManagerRole && _viewMode == 'self') ...[
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildCategoryChip('All', 'all'),
                    const SizedBox(width: 8),
                    _buildCategoryChip('Daily', 'daily'),
                    const SizedBox(width: 8),
                    _buildCategoryChip('Project', 'project'),
                    const SizedBox(width: 8),
                    _buildCategoryChip('Personal', 'personal'),
                    const SizedBox(width: 8),
                    _buildCategoryChip('Monthly', 'monthly'),
                    const SizedBox(width: 8),
                    _buildCategoryChip('Quarterly', 'quarterly'),
                    const SizedBox(width: 8),
                    _buildCategoryChip('Yearly', 'yearly'),
                    const SizedBox(width: 8),
                    _buildCategoryChip('Other', 'other'),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = value;
        });
      },
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFceb56e).withValues(alpha: 0.2),
      checkmarkColor: const Color(0xFFceb56e),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFFceb56e) : Colors.grey.shade700,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  String _buildFilterSummary() {
    String statusLabel;
    switch (_selectedFilter) {
      case 'assigned':
        statusLabel = 'Assigned';
        break;
      case 'in_progress':
        statusLabel = 'In progress';
        break;
      case 'completed':
        statusLabel = 'Completed';
        break;
      case 'paused':
        statusLabel = 'Paused';
        break;
      case 'need_help':
        statusLabel = 'Need help';
        break;
      default:
        statusLabel = 'All statuses';
    }

    String categoryLabel;
    if (!_isManagerRole || _viewMode != 'self') {
      categoryLabel = '';
    } else {
      switch (_selectedCategory) {
        case 'daily':
          categoryLabel = ' • Daily';
          break;
        case 'project':
          categoryLabel = ' • Project';
          break;
        case 'personal':
          categoryLabel = ' • Personal';
          break;
        case 'monthly':
          categoryLabel = ' • Monthly';
          break;
        case 'quarterly':
          categoryLabel = ' • Quarterly';
          break;
        case 'yearly':
          categoryLabel = ' • Yearly';
          break;
        case 'other':
          categoryLabel = ' • Other';
          break;
        default:
          categoryLabel = '';
      }
    }

    return '$statusLabel$categoryLabel';
  }

  Widget _buildCategoryChip(String label, String value) {
    final isSelected = _selectedCategory == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedCategory = value;
        });
      },
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFceb56e).withValues(alpha: 0.2),
      checkmarkColor: const Color(0xFFceb56e),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFFceb56e) : Colors.grey.shade700,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'Something went wrong',
            style: const TextStyle(fontSize: 16, color: Colors.red),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _fetchTasks,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    final bool isAdminEmployeeView =
        widget.userRole == 'admin' && _viewMode == 'employee';

    final String title =
        isAdminEmployeeView ? 'Select Employee' : 'No Tasks Found';
    final String subtitle = isAdminEmployeeView
        ? 'Choose an employee to view their tasks.'
        : 'Create your first task to get started';

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.task_outlined,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList() {
    return RefreshIndicator(
      onRefresh: _fetchTasks,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _filteredTasks.length,
        itemBuilder: (context, index) {
          final task = _filteredTasks[index];
          return _buildTaskCard(task);
        },
      ),
    );
  }

  Widget _buildTaskCard(Task task) {
    final statusColor = _getStatusColor(task.status);
    final priorityColor = _getPriorityColor(task.priority);
    final isSelfTask = task.createdBy == task.assignedTo;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () => _openTaskDetails(task),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: _getStatusBackground(task.status),
            borderRadius: BorderRadius.circular(14),
            border: Border(left: BorderSide(color: statusColor, width: 4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFceb56e).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getCategoryIcon(task.category),
                        size: 18,
                        color: const Color(0xFFceb56e),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            task.category[0].toUpperCase() +
                                task.category.substring(1) +
                                ' task',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: priorityColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.flag_rounded,
                            size: 12,
                            color: priorityColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            task.priority.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: priorityColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (task.createdBy == widget.userId) ...[
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 18),
                        onSelected: (value) async {
                          if (value == 'edit') {
                            await _openAdminTaskEdit(task);
                          } else if (value == 'delete') {
                            await _deleteTask(task);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit task'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete task'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                if (task.needHelpNote != null &&
                    task.needHelpNote!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.sticky_note_2_outlined,
                          size: 16,
                          color: Colors.red.shade700,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Status note',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red.shade800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                task.needHelpNote!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade800,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (task.category == 'daily') ...[
                  const SizedBox(height: 8),
                  _buildTaskHistoryStrip(task),
                ],
                if (task.descriptionOnly != null &&
                    task.descriptionOnly!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Description',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    task.descriptionOnly!,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (task.subtasksWithStatus.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Subtasks',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...task.subtasksWithStatus.asMap().entries.map(
                    (entry) {
                      final idx = entry.key;
                      final st = entry.value;
                      final color = _getSubtaskStatusColor(st.status);
                      final showSubtaskHelp = st.needHelpNote != null &&
                          st.needHelpNote!.isNotEmpty;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    st.text,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade800,
                                      decoration: st.status == 'completed'
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _canChangeTaskStatus(task)
                                        ? () => _showSubtaskStatusPicker(
                                              context: context,
                                              currentStatus: st.status,
                                              onSelected: (s) async {
                                                final note =
                                                    await _showNeedHelpNoteDialog(
                                                  title: 'Status Note',
                                                  hint:
                                                      'Add a note for status: ${s.replaceAll('_', ' ').toUpperCase()} (optional)',
                                                  allowEmpty: true,
                                                );
                                                await _updateSubtaskStatus(
                                                  task,
                                                  idx,
                                                  s,
                                                  statusNote: note,
                                                );
                                              },
                                            )
                                        : null,
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: color, width: 1.5),
                                      ),
                                      child: Icon(
                                        Icons.flag,
                                        size: 16,
                                        color: _canChangeTaskStatus(task)
                                            ? color
                                            : color.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (showSubtaskHelp) ...[
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: color, width: 1.5),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.sticky_note_2_outlined,
                                            size: 16,
                                            color: color,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Status note',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: color,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        st.needHelpNote!,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: color,
                                          height: 1.3,
                                        ),
                                        maxLines: 5,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            if (task.category == 'daily') ...[
                              const SizedBox(height: 4),
                              _buildSubtaskHistoryStrip(task, idx),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle,
                            size: 8,
                            color: statusColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            task.status.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (task.deadlineDate != null) ...[
                      Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        task.deadlineDate!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
                if (task.assigneeName != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Assigned to: ${task.assigneeName}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Builder(
                  builder: (context) {
                    String? label;
                    if (task.assignedTo.isNotEmpty &&
                        task.createdBy == task.assignedTo) {
                      label = 'Self task';
                    } else if (task.creatorName != null &&
                        task.creatorName!.isNotEmpty) {
                      label = 'Assigned by: ${task.creatorName}';
                    } else if (task.createdBy.isNotEmpty) {
                      label = 'Assigned by admin';
                    }
                    if (label == null) return const SizedBox.shrink();
                    return Row(
                      children: [
                        Icon(
                          isSelfTask ? Icons.person : Icons.admin_panel_settings,
                          size: 14,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openAdminTaskEdit(Task task) async {
    final titleController = TextEditingController(text: task.title);
    final descriptionController =
        TextEditingController(text: task.descriptionOnly ?? '');
    String taskStatus = task.status;
    String priority = task.priority;
    String category = task.category;
    DateTime? deadlineDate =
        task.deadlineDate != null ? DateTime.tryParse(task.deadlineDate!) : null;
    TimeOfDay? deadlineTime = task.deadlineTime != null
        ? TimeOfDay(
            hour: int.tryParse(task.deadlineTime!.split(':')[0]) ?? 0,
            minute: int.tryParse(task.deadlineTime!.split(':')[1]) ?? 0,
          )
        : null;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Edit Task',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Task Title',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        hintText: 'Title',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Description',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Description',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Task Status',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _taskStatuses.map((s) {
                        final selected = taskStatus == s;
                        final color = _getStatusColor(s);
                        return ChoiceChip(
                          label: Text(
                            s.replaceAll('_', ' '),
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  selected ? color : Colors.grey.shade700,
                            ),
                          ),
                          selected: selected,
                          onSelected: (_) async {
                            final note = await _showNeedHelpNoteDialog(
                              title: 'Status Note',
                              hint:
                                  'Add a note for status: ${s.replaceAll('_', ' ').toUpperCase()} (optional)',
                              allowEmpty: true,
                            );
                            setModalState(() {
                              taskStatus = s;
                            });
                            if (note != null && note.isNotEmpty) {
                              await TaskService.updateTaskStatus(
                                task.id,
                                s,
                                needHelpNote: note,
                              );
                            } else {
                              await TaskService.updateTaskStatus(task.id, s);
                            }
                          },
                          selectedColor: color.withValues(alpha: 0.2),
                          backgroundColor: Colors.grey.shade100,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Priority',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['low', 'medium', 'high', 'critical']
                          .map((p) {
                        final selected = priority == p;
                        final color = _getPriorityColor(p);
                        return ChoiceChip(
                          label: Text(
                            p[0].toUpperCase() + p.substring(1),
                          ),
                          selected: selected,
                          onSelected: (_) =>
                              setModalState(() => priority = p),
                          selectedColor: color.withValues(alpha: 0.2),
                          backgroundColor: Colors.grey.shade100,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Category',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: const [
                        'daily',
                        'project',
                        'personal',
                        'monthly',
                        'quarterly',
                        'yearly',
                        'other',
                      ].map((c) {
                        return Builder(
                          builder: (context) {
                            final selected = category == c;
                            return ChoiceChip(
                              label: Text(
                                  c[0].toUpperCase() + c.substring(1)),
                              selected: selected,
                              onSelected: (_) =>
                                  setModalState(() => category = c),
                              selectedColor:
                                  const Color(0xFFceb56e).withValues(
                                      alpha: 0.2),
                              backgroundColor: Colors.grey.shade100,
                            );
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Deadline',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate:
                                    deadlineDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setModalState(() => deadlineDate = picked);
                              }
                            },
                            icon:
                                const Icon(Icons.calendar_today, size: 18),
                            label: Text(
                              deadlineDate != null
                                  ? '${deadlineDate!.day}/${deadlineDate!.month}/${deadlineDate!.year}'
                                  : 'Date',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: deadlineTime ??
                                    TimeOfDay.now(),
                              );
                              if (picked != null) {
                                setModalState(() => deadlineTime = picked);
                              }
                            },
                            icon:
                                const Icon(Icons.access_time, size: 18),
                            label: Text(
                              deadlineTime != null
                                  ? '${deadlineTime!.hour}:${deadlineTime!.minute.toString().padLeft(2, '0')}'
                                  : 'Time',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        onPressed: () async {
                          final updatedData = {
                            'title': titleController.text.trim(),
                            'description':
                                descriptionController.text.trim().isEmpty
                                    ? null
                                    : descriptionController.text.trim(),
                            'status': taskStatus,
                            'priority': priority,
                            'category': category,
                          };
                          final d = deadlineDate;
                          if (d != null) {
                            updatedData['deadline_date'] =
                                '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                          }
                          final t = deadlineTime;
                          if (t != null) {
                            updatedData['deadline_time'] =
                                '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
                          }
                          try {
                            await TaskService.updateTask(
                                task.id, updatedData);
                            if (!mounted) return;
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Task updated successfully'),
                              ),
                            );
                            _fetchTasks();
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  e
                                      .toString()
                                      .replaceFirst('Exception: ', '')
                                      .trim(),
                                ),
                              ),
                            );
                          }
                        },
                        child: const Text(
                          'Save',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _deleteTask(Task task) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Delete task?'),
            content: const Text(
              'This will permanently delete the task and its subtasks.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await TaskService.deleteTask(task.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task deleted')),
      );
      _fetchTasks();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', '').trim(),
          ),
        ),
      );
    }
  }

  Future<void> _openTaskDetails(Task task) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final statusColor = _getStatusColor(task.status);
        final isSelfTask = task.createdBy == task.assignedTo;
        final canEdit = task.createdBy == widget.userId;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Task Details',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  task.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  task.category[0].toUpperCase() +
                      task.category.substring(1) +
                      ' task',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (task.descriptionOnly != null &&
                    task.descriptionOnly!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Description',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    task.descriptionOnly!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
                if (task.subtasksWithStatus.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Subtasks',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...task.subtasksWithStatus.asMap().entries.map(
                    (entry) {
                      final idx = entry.key;
                      final st = entry.value;
                      final color = _getSubtaskStatusColor(st.status);
                      final showSubtaskHelp =
                          st.needHelpNote != null &&
                              st.needHelpNote!.isNotEmpty;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    st.text,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87,
                                      decoration: st.status == 'completed'
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _canChangeTaskStatus(task)
                                        ? () => _showSubtaskStatusPicker(
                                              context: ctx,
                                              currentStatus: st.status,
                                              onSelected: (s) async {
                                                final note =
                                                    await _showNeedHelpNoteDialog(
                                                  title: 'Status Note',
                                                  hint:
                                                      'Add a note for status: ${s.replaceAll('_', ' ').toUpperCase()} (optional)',
                                                  allowEmpty: true,
                                                );
                                                await _updateSubtaskStatus(
                                                  task,
                                                  idx,
                                                  s,
                                                  statusNote: note,
                                                );
                                              },
                                            )
                                        : null,
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: color, width: 1.5),
                                      ),
                                      child: Icon(
                                        Icons.flag,
                                        size: 16,
                                        color: _canChangeTaskStatus(task)
                                            ? color
                                            : color.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (showSubtaskHelp) ...[
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: color),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.sticky_note_2_outlined,
                                        size: 14,
                                        color: color,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Status note',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: color,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              st.needHelpNote!,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: color,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, size: 8, color: statusColor),
                          const SizedBox(width: 6),
                          Text(
                            task.status.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (task.deadlineDate != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            task.deadlineDate!,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    if (task.assigneeName != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_outline, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'Assigned to: ${task.assigneeName}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    if (isSelfTask)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.person_pin_circle_outlined, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Self task',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                  ],
                ),
                if (task.needHelpNote != null &&
                    task.needHelpNote!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.sticky_note_2_outlined,
                              size: 16,
                              color: statusColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Status note',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          task.needHelpNote!,
                          style: TextStyle(
                            fontSize: 13,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (canEdit) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _openAdminTaskEdit(task);
                          },
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit Task'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _deleteTask(task);
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete Task'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
