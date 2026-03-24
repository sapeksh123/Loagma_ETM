import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/task_service.dart';
import '../../services/user_service.dart';
import '../../services/notification_service.dart';
import '../../models/task_model.dart';
import 'create_task_screen.dart';
import '../task/hidden_tasks_screen.dart';

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
  final TextEditingController _employeeSearchController =
      TextEditingController();

  // Preset reminder/update texts for the help dialog
  static const List<Map<String, String>> _presetMessages = [
    {
      'id': 'pending',
      'label': 'Reminder: pending task',
      'message':
          'Reminder: This task is still pending. Please review and update the status.',
    },
    {
      'id': 'deadline',
      'label': 'Update: deadline approaching',
      'message':
          'Update: The deadline for this task is approaching. Please prioritize and complete it as soon as possible.',
    },
    {
      'id': 'details_changed',
      'label': 'Update: task details changed',
      'message':
          'Update: Some details for this task have changed. Please open the task and review the latest information.',
    },
  ];

  bool get _isManagerRole =>
      widget.userRole == 'admin' ||
      widget.userRole == 'subadmin' ||
      widget.userRole == 'techincharge';

  List<Map<String, dynamic>> get _filteredEmployeesForList {
    final q = _employeeSearchController.text.trim().toLowerCase();
    if (q.isEmpty) return _employees;
    return _employees.where((e) {
      final name = (e['name'] as String? ?? '').toLowerCase();
      final role = _employeeRoleLabel(e['role'] as String? ?? '').toLowerCase();
      return name.contains(q) || role.contains(q);
    }).toList();
  }

  static String _employeeRoleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'Admin';
      case 'subadmin':
        return 'Sub Admin';
      case 'techincharge':
        return 'Tech Incharge';
      case 'employee':
        return 'Employee';
      default:
        return role.isEmpty ? '—' : role;
    }
  }

  @override
  void dispose() {
    _employeeSearchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Default to self-view; employees don't see extra options.
    // Manager roles can override via initialViewMode (from dashboard cards).
    if (_isManagerRole && widget.initialViewMode.toLowerCase() == 'employee') {
      _viewMode = 'employee';
    } else {
      _viewMode = 'self';
    }
    _fetchTasks();
    if (_isManagerRole) {
      _loadEmployees();
    }
  }

  Future<void> _openHiddenTasks() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => HiddenTasksScreen(
          userId: widget.userId,
          userRole: widget.userRole,
          title: 'Hidden Tasks',
        ),
      ),
    );
    if (!mounted) return;
    if (changed == true) {
      _fetchTasks();
    }
  }

  Future<void> _moveTaskToHidden(Task task) async {
    final canHide = task.isAssignedToSelf && task.assignedTo == widget.userId;
    if (!canHide) return;
    try {
      final response = await TaskService.hideTask(
        task.id,
        widget.userId,
        widget.userRole,
      );
      if (response['status'] != 'success') {
        throw Exception((response['message'] ?? 'Failed to hide task').toString());
      }

      if (!mounted) return;
      setState(() {
        _tasks.removeWhere((t) => t.id == task.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Task moved to hidden'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '').trim()),
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

  Future<void> _showTaskLongPressActions(Task task) async {
    final canHide = task.isAssignedToSelf && task.assignedTo == widget.userId;
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Task Actions',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                if (canHide)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.visibility_off_outlined),
                    title: const Text('Move to Hidden Tasks'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _moveTaskToHidden(task);
                    },
                  )
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.info_outline,
                      color: Colors.grey.shade600,
                    ),
                    title: const Text('Only self-assigned tasks can be hidden'),
                    onTap: () => Navigator.pop(ctx),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAdminModeSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(color: Colors.white),
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
                      if (_selectedCategory == 'personal') {
                        _selectedCategory = 'all';
                      }
                    });
                    _fetchTasks();
                  },
                ),
              ),
            ],
          ),
          if (_viewMode == 'employee') ...[
            const SizedBox(height: 10),
            if (_selectedEmployeeId == null)
              _buildEmployeeSearchBar()
            else
              _buildViewingEmployeeBar(),
          ],
        ],
      ),
    );
  }

  /// Header used when the view mode is locked from the dashboard cards.
  /// For employee mode, show search bar or "Viewing: Name" + Change.
  Widget _buildLockedAdminHeader() {
    if (_viewMode != 'employee') {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(color: Colors.white),
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
          if (_selectedEmployeeId == null)
            _buildEmployeeSearchBar()
          else
            _buildViewingEmployeeBar(),
        ],
      ),
    );
  }

  Widget _buildEmployeeSearchBar() {
    return TextField(
      controller: _employeeSearchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Search by name or role',
        prefixIcon: const Icon(Icons.search, size: 22),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
    );
  }

  Widget _buildViewingEmployeeBar() {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFceb56e).withValues(alpha: 0.2),
                child: Text(
                  (_selectedEmployeeName ?? '?').isNotEmpty
                      ? (_selectedEmployeeName![0].toUpperCase())
                      : '?',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFceb56e),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Viewing tasks for',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      _selectedEmployeeName ?? '—',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _buildEmployeeContactButtons(),
        const SizedBox(width: 6),
        TextButton(
          onPressed: () {
            setState(() {
              _selectedEmployeeId = null;
              _selectedEmployeeName = null;
              _selectedEmployeePhone = null;
            });
            _fetchTasks();
          },
          child: const Text('Change'),
        ),
      ],
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
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
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
      await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      final Uri webUri = Uri.parse("https://wa.me/$normalized");

      await launchUrl(webUri, mode: LaunchMode.externalApplication);
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
          border: Border.all(color: const Color(0xFFceb56e), width: 1.2),
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

  /// Content when in Employee Tasks view with no employee selected: list of employees.
  Widget _buildEmployeeListContent() {
    if (_isEmployeesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_employees.isEmpty) {
      return Center(
        child: Text(
          'No employees found.',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
      );
    }
    final filtered = _filteredEmployeesForList;
    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No employees match "${_employeeSearchController.text.trim()}"',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final emp = filtered[index];
        final name = emp['name'] as String? ?? 'Unknown';
        final role = emp['role'] as String? ?? '';
        final roleLabel = _employeeRoleLabel(role);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedEmployeeId = emp['id'] as String?;
                  _selectedEmployeeName = emp['name'] as String?;
                  _selectedEmployeePhone = emp['phone'] as String?;
                });
                _fetchTasks();
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: const Color(
                        0xFFceb56e,
                      ).withValues(alpha: 0.2),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFceb56e),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            roleLabel,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: Colors.grey.shade400,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _fetchTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Managers always query as themselves; optional employee scope is sent separately.
      String userId = widget.userId;
      String userRole = widget.userRole;
      String? targetUserId;

      if (_isManagerRole && _viewMode == 'employee') {
        // When viewing employee tasks, require a selected employee
        if (_selectedEmployeeId == null) {
          setState(() {
            _tasks = [];
            _isLoading = false;
          });
          return;
        }
        targetUserId = _selectedEmployeeId!;
      }

      final response = await TaskService.getTasks(
        userId,
        userRole,
        targetUserId: targetUserId,
      );

      if (response['status'] == 'success') {
        final List<dynamic> tasksData = response['data'] ?? [];
        var tasks = tasksData.map((json) => Task.fromJson(json)).toList();

        // For manager self view, show only true self tasks:
        // created_by == manager AND assigned_to == manager.
        if (_isManagerRole && _viewMode == 'self') {
          tasks = tasks
              .where(
                (task) =>
                    task.createdBy == widget.userId &&
                    task.assignedTo == widget.userId,
              )
              .toList();
        }

        setState(() {
          _tasks = tasks;
          _isLoading = false;
        });
      } else {
        final message = (response['message'] ?? 'Failed to load tasks')
            .toString();
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
      String message = e.toString().replaceFirst('Exception: ', '').trim();

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
    final selfCategoryOnly = _isManagerRole && _viewMode == 'self';
    if (!selfCategoryOnly && _selectedFilter != 'all') {
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
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '').trim()),
        ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.sticky_note_2_outlined,
                color: Colors.brown,
                size: 26,
              ),
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
          final date = entry.date.length >= 10
              ? entry.date.substring(8, 10)
              : '';
          final month = entry.date.length >= 7
              ? entry.date.substring(5, 7)
              : '';
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
                border: Border.all(color: color, width: 1),
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
                    Icon(Icons.sticky_note_2_outlined, size: 12, color: color),
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
          final date = entry.date.length >= 10
              ? entry.date.substring(8, 10)
              : '';
          final month = entry.date.length >= 7
              ? entry.date.substring(5, 7)
              : '';
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
                border: Border.all(color: color, width: 1),
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
                    Icon(Icons.circle, size: 8, color: color),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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
                  Icon(
                    Icons.calendar_today,
                    size: 14,
                    color: Colors.grey.shade700,
                  ),
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
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
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
            if (!(_isManagerRole &&
                _viewMode == 'employee' &&
                _selectedEmployeeId == null))
              _buildFilterChips(),
            Expanded(
              child:
                  _isManagerRole &&
                      _viewMode == 'employee' &&
                      _selectedEmployeeId == null
                  ? _buildEmployeeListContent()
                  : _isLoading
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
            final noEmployeeSelected =
                _selectedEmployeeId == null ||
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
        DailyStatusEntry(date: '$yyyy-$mm-$dd', status: 'assigned', note: null),
      );
    }
    return days;
  }

  Widget _buildFilterChips() {
    if (_isManagerRole && _viewMode == 'self') {
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
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
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
            ),
            IconButton(
              tooltip: 'Hidden tasks',
              icon: const Icon(Icons.visibility_off_outlined, size: 20),
              onPressed: _openHiddenTasks,
            ),
          ],
        ),
      );
    }

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
            if (_isManagerRole) ...[
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
    if (!_isManagerRole) {
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

    final String title = isAdminEmployeeView
        ? 'Select Employee'
        : 'No Tasks Found';
    final String subtitle = isAdminEmployeeView
        ? 'Choose an employee to view their tasks.'
        : 'Create your first task to get started';

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.task_outlined, size: 80, color: Colors.grey.shade400),
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
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
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
    final isSelfContextForHidden = !_isManagerRole || _viewMode == 'self';
    final categoryLabel = task.category.isNotEmpty
        ? task.category[0].toUpperCase() + task.category.substring(1)
        : 'Task';
    final statusLabel = task.status.replaceAll('_', ' ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () => _openTaskDetails(task),
        onLongPress: isSelfContextForHidden
            ? () => _showTaskLongPressActions(task)
            : null,
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
                            '$categoryLabel • $statusLabel',
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
                    if (_isManagerRole && _viewMode == 'employee') ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(
                          Icons.help_outline,
                          size: 18,
                          color: Color(0xFF9E9E9E),
                        ),
                        tooltip: 'Send reminder to employee',
                        onPressed: () {
                          _showTaskReminderDialog(task: task);
                        },
                      ),
                    ],
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
                  ...task.subtasksWithStatus.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final st = entry.value;
                    final color = _getSubtaskStatusColor(st.status);
                    final showSubtaskHelp =
                        st.needHelpNote != null && st.needHelpNote!.isNotEmpty;
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
                              if (_isManagerRole &&
                                  _viewMode == 'employee') ...[
                                IconButton(
                                  icon: const Icon(
                                    Icons.help_outline,
                                    size: 18,
                                    color: Color(0xFF9E9E9E),
                                  ),
                                  tooltip:
                                      'Send reminder for this subtask to employee',
                                  onPressed: () {
                                    _showTaskReminderDialog(
                                      task: task,
                                      subtaskIndex: idx,
                                    );
                                  },
                                ),
                                const SizedBox(width: 2),
                              ],
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
                                        color: color,
                                        width: 1.5,
                                      ),
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
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: color, width: 1.5),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                  }),
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
                    if (task.createdBy.isNotEmpty) {
                      final includeEmployeeNameForSelf =
                          task.isAssignedToSelf && task.assignedTo != widget.userId;
                      label = task.assignmentByLabel(
                        includeEmployeeNameForSelf: includeEmployeeNameForSelf,
                      );
                    }
                    if (label == null) return const SizedBox.shrink();
                    return Row(
                      children: [
                        Icon(
                          task.isAssignedToSelf
                              ? Icons.person
                              : Icons.admin_panel_settings,
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
    final descriptionController = TextEditingController(
      text: task.descriptionOnly ?? '',
    );
    String taskStatus = task.status;
    String priority = task.priority;
    String category = task.category;
    DateTime? deadlineDate = task.deadlineDate != null
        ? DateTime.tryParse(task.deadlineDate!)
        : null;
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
                          horizontal: 14,
                          vertical: 12,
                        ),
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
                          horizontal: 14,
                          vertical: 12,
                        ),
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
                              color: selected ? color : Colors.grey.shade700,
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
                      children: ['low', 'medium', 'high', 'critical'].map((p) {
                        final selected = priority == p;
                        final color = _getPriorityColor(p);
                        return ChoiceChip(
                          label: Text(p[0].toUpperCase() + p.substring(1)),
                          selected: selected,
                          onSelected: (_) => setModalState(() => priority = p),
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
                      children:
                          const [
                            'daily',
                            'project',
                            'monthly',
                            'quarterly',
                            'yearly',
                            'personal',
                            'other',
                          ].map((c) {
                            return Builder(
                              builder: (context) {
                                final selected = category == c;
                                return ChoiceChip(
                                  label: Text(
                                    c[0].toUpperCase() + c.substring(1),
                                  ),
                                  selected: selected,
                                  onSelected: (_) =>
                                      setModalState(() => category = c),
                                  selectedColor: const Color(
                                    0xFFceb56e,
                                  ).withValues(alpha: 0.2),
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
                                initialDate: deadlineDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setModalState(() => deadlineDate = picked);
                              }
                            },
                            icon: const Icon(Icons.calendar_today, size: 18),
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
                                initialTime: deadlineTime ?? TimeOfDay.now(),
                              );
                              if (picked != null) {
                                setModalState(() => deadlineTime = picked);
                              }
                            },
                            icon: const Icon(Icons.access_time, size: 18),
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
                            await TaskService.updateTask(task.id, updatedData);
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
                          style: TextStyle(fontWeight: FontWeight.bold),
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
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Task deleted')));
      _fetchTasks();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '').trim()),
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
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                if (task.descriptionOnly != null &&
                    task.descriptionOnly!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Description',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    task.descriptionOnly!,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                ],
                if (task.subtasksWithStatus.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Subtasks',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  ...task.subtasksWithStatus.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final st = entry.value;
                    final color = _getSubtaskStatusColor(st.status);
                    final showSubtaskHelp =
                        st.needHelpNote != null && st.needHelpNote!.isNotEmpty;
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
                                        color: color,
                                        width: 1.5,
                                      ),
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
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: color),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                  }),
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
                        children: [
                          const Icon(Icons.person_pin_circle_outlined, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            task.assignmentByLabel(
                              includeEmployeeNameForSelf:
                                  task.assignedTo != widget.userId,
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.admin_panel_settings, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            task.assignmentByLabel(),
                            style: const TextStyle(fontSize: 12),
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
                          style: TextStyle(fontSize: 13, color: statusColor),
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

  /// Show a reminder/update dialog for a specific task or subtask.
  ///
  /// Only available when a manager is viewing Employee Tasks with a selected employee.
  Future<void> _showTaskReminderDialog({
    required Task task,
    int? subtaskIndex,
  }) async {
    if (!_isManagerRole || _viewMode != 'employee') {
      return;
    }
    if (_selectedEmployeeId == null || _selectedEmployeeId!.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an employee first')),
      );
      return;
    }

    final employeeId = _selectedEmployeeId!;
    final senderRole = widget.userRole.toLowerCase();
    String selectedPresetId = _presetMessages.first['id']!;
    final customController = TextEditingController();
    String messageType = 'reminder';

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.help_outline, color: Color(0xFFceb56e)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subtaskIndex != null
                      ? 'Send reminder for subtask'
                      : 'Send reminder for task',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subtaskIndex != null &&
                          subtaskIndex >= 0 &&
                          subtaskIndex < task.subtasksWithStatus.length
                      ? task.subtasksWithStatus[subtaskIndex].text
                      : task.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Preset message',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Column(
                  children: _presetMessages.map((preset) {
                    final id = preset['id']!;
                    final label = preset['label']!;
                    final isSelected = selectedPresetId == id;
                    return RadioListTile<String>(
                      value: id,
                      groupValue: selectedPresetId,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        (ctx as Element).markNeedsBuild();
                        selectedPresetId = value;
                        if (value == 'pending' || value == 'deadline') {
                          messageType = 'reminder';
                        } else {
                          messageType = 'update';
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Additional message (optional)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: customController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText:
                        'Add any specific details or updates for the employee...',
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
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send'),
            ),
          ],
        );
      },
    );

    if (result != true || !mounted) return;

    final preset = _presetMessages.firstWhere(
      (p) => p['id'] == selectedPresetId,
      orElse: () {
        return _presetMessages.first;
      },
    );
    final baseMessage = preset['message'] ?? '';
    final extra = customController.text.trim();
    final fullMessage = extra.isEmpty
        ? baseMessage
        : '$baseMessage\n\nNote: $extra';

    BuildContext? loaderContext;
    try {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (loaderCtx) {
          loaderContext = loaderCtx;
          return const AlertDialog(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(child: Text('Sending reminder...')),
              ],
            ),
          );
        },
      );

      await NotificationService.sendTaskReminder(
        senderRole: senderRole,
        employeeId: employeeId,
        taskId: task.id,
        subtaskIndex: subtaskIndex,
        type: messageType,
        message: fullMessage,
      );
      if (!mounted) return;
      if (loaderContext != null) {
        Navigator.of(loaderContext!).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder sent to employee')),
      );
    } catch (e) {
      if (!mounted) return;
      if (loaderContext != null) {
        Navigator.of(loaderContext!).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '').trim()),
        ),
      );
    } finally {
      customController.dispose();
    }
  }
}

/// Bottom sheet for selecting an employee: search box + list showing name and role only.
class _EmployeeSelectSheet extends StatefulWidget {
  final List<Map<String, dynamic>> employees;
  final void Function(Map<String, dynamic>) onSelect;

  const _EmployeeSelectSheet({required this.employees, required this.onSelect});

  @override
  State<_EmployeeSelectSheet> createState() => _EmployeeSelectSheetState();
}

class _EmployeeSelectSheetState extends State<_EmployeeSelectSheet> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  static String _roleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'Admin';
      case 'subadmin':
        return 'Sub Admin';
      case 'techincharge':
        return 'Tech Incharge';
      case 'employee':
        return 'Employee';
      default:
        return role.isEmpty ? '—' : role;
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return widget.employees;
    return widget.employees.where((e) {
      final name = (e['name'] as String? ?? '').toLowerCase();
      final role = _roleLabel(e['role'] as String? ?? '').toLowerCase();
      return name.contains(q) || role.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Column(
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
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Choose Employee',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search by name or role',
                    prefixIcon: const Icon(Icons.search, size: 22),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No employees match "${_searchController.text.trim()}"',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: filtered.length,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemBuilder: (context, index) {
                          final emp = filtered[index];
                          final name = emp['name'] as String? ?? 'Unknown';
                          final role = emp['role'] as String? ?? '';
                          final roleLabel = _roleLabel(role);
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => widget.onSelect(emp),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                margin: const EdgeInsets.only(bottom: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.04,
                                      ),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: const Color(
                                        0xFFceb56e,
                                      ).withValues(alpha: 0.2),
                                      child: Text(
                                        name.isNotEmpty
                                            ? name[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFFceb56e),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            name,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            roleLabel,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey.shade600,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right,
                                      color: Colors.grey.shade400,
                                      size: 22,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
