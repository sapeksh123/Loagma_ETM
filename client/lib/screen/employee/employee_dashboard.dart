import 'package:flutter/material.dart';

import '../../widgets/attendance_card.dart';
import '../../models/task_model.dart';
import '../../services/task_service.dart';
import '../admin/create_task_screen.dart';

class _EditSubtaskEntry {
  final TextEditingController controller;
  String status;
  _EditSubtaskEntry(this.controller, this.status);
}

class EmployeeDashboard extends StatefulWidget {
  final String userId;
  final String userRole;
  final String userName;

  const EmployeeDashboard({
    super.key,
    required this.userId,
    required this.userRole,
    required this.userName,
  });

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<Task> _tasks = [];
  bool _isLoadingTasks = true;
  String? _tasksError;
  /// Status filter: null = all, else one of assigned, in_progress, completed, paused, need_help
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _fetchTasks();
  }

  Future<void> _fetchTasks() async {
    setState(() {
      _isLoadingTasks = true;
      _tasksError = null;
    });

    try {
      final response = await TaskService.getTasks(
        widget.userId,
        widget.userRole,
      );

      if (response['status'] == 'success') {
        final List<dynamic> tasksData = response['data'] ?? [];
        setState(() {
          _tasks = tasksData.map((json) => Task.fromJson(json)).toList();
          _isLoadingTasks = false;
        });
      } else {
        setState(() {
          _tasksError =
              (response['message'] ?? 'Failed to load tasks').toString();
          _isLoadingTasks = false;
        });
      }
    } catch (e) {
      setState(() {
        _tasksError =
            e.toString().replaceFirst('Exception: ', '').trim();
        _isLoadingTasks = false;
      });
    }
  }

  static const Color _gold = Color(0xFFceb56e);

  void _showStatusFilterPopup(BuildContext context) {
    const statusOptions = [
      {'value': null, 'label': 'All statuses'},
      {'value': 'assigned', 'label': 'Assigned'},
      {'value': 'in_progress', 'label': 'In progress'},
      {'value': 'completed', 'label': 'Completed'},
      {'value': 'paused', 'label': 'Paused'},
      {'value': 'need_help', 'label': 'Need help'},
    ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Filter by status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Show only tasks with the selected status.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 16),
                ...statusOptions.map((opt) {
                  final value = opt['value'];
                  final label = opt['label']!;
                  final isSelected = _statusFilter == value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _statusFilter = value;
                        });
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 12,
                        ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _gold.withValues(alpha: 0.12)
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? _gold
                                  : Colors.grey.shade200,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF6B5B2E),
                                  size: 22,
                                ),
                              if (isSelected) const SizedBox(width: 12),
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight:
                                      isSelected ? FontWeight.w600 : FontWeight.normal,
                                  color: isSelected
                                      ? const Color(0xFF6B5B2E)
                                      : Colors.grey.shade800,
                                ),
                              ),
                            ],
                          ),
                      ),
                    ),
                  ),
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _showExitConfirmation(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 28,
                ),
                SizedBox(width: 12),
                Text('Confirm Exit'),
              ],
            ),
            content: const Text(
              'Are you sure you want to go back? You will be logged out.',
              style: TextStyle(fontSize: 16),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Exit'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showLogoutConfirmation(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text('Logout'),
          ],
        ),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _showExitConfirmation(context);
        if (shouldPop && context.mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
      },
      child: DefaultTabController(
        length: 5,
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: Colors.grey.shade50,
          appBar: AppBar(
            title: const Text(
              "Employee Dashboard",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            elevation: 0,
            actions: [
              IconButton(
                icon: Icon(
                  _statusFilter != null ? Icons.filter_list : Icons.filter_list_outlined,
                  color: _statusFilter != null ? Colors.black87 : Colors.white,
                ),
                tooltip: _statusFilter != null
                    ? 'Filter: ${_statusFilter!.replaceAll('_', ' ')} (tap to change)'
                    : 'Filter by status',
                onPressed: () => _showStatusFilterPopup(context),
              ),
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Logout',
                onPressed: () => _showLogoutConfirmation(context),
              ),
            ],
          ),

          drawer: Drawer(
            width: MediaQuery.of(context).size.width * 0.85,
            backgroundColor: Colors.grey.shade50,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Employee details header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.userName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D2D2D),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.badge_outlined,
                                  size: 16, color: Colors.grey.shade600),
                              const SizedBox(width: 6),
                              Text(
                                widget.userRole.isEmpty
                                    ? 'Employee'
                                    : widget.userRole[0].toUpperCase() +
                                        widget.userRole.substring(1),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.tag,
                                  size: 16, color: Colors.grey.shade600),
                              const SizedBox(width: 6),
                              Text(
                                'ID: ${widget.userId}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 16),
                      child: Text(
                        'Today\'s Attendance',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    AttendanceCard(
                      userId: widget.userId,
                      userName: widget.userName,
                    ),
                  ],
                ),
              ),
            ),
          ),

          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateTaskScreen(
                    userId: widget.userId,
                    userRole: widget.userRole,
                  ),
                ),
              ).then((value) {
                if (value == true) {
                  _fetchTasks();
                }
              });
            },
            icon: const Icon(Icons.add_task),
            label: const Text('New Task'),
            elevation: 4,
          ),

          body: Column(
            children: [
              const SizedBox(height: 16),

              /// 🔹 Category Tabs
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  padding: const EdgeInsets.symmetric(horizontal:4 ),
                  labelColor: const Color(0xFFceb56e),
                  unselectedLabelColor: Colors.grey,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: 12,
                  ),
                  indicator: const UnderlineTabIndicator(
                    borderSide: BorderSide(color: Color(0xFFceb56e), width: 3),
                  ),
                  tabs: const [
                    Tab(icon: Icon(Icons.today, size: 22), text: "Daily"),
                    Tab(
                      icon: Icon(Icons.work_outline, size: 22),
                      text: "Project",
                    ),
                    Tab(
                      icon: Icon(Icons.person_outline, size: 22),
                      text: "Personal",
                    ),
                    Tab(
                      icon: Icon(Icons.calendar_month, size: 22),
                      text: "Monthly",
                    ),
                    Tab(
                      icon: Icon(Icons.date_range, size: 22),
                      text: "Quarterly",
                    ),
                    Tab(
                      icon: Icon(Icons.calendar_today, size: 22),
                      text: "Yearly",
                    ),
                    Tab(icon: Icon(Icons.more_horiz, size: 22), text: "Other"),
                  ],
                ),
              ),

              /// 🔹 Task List
              Expanded(
                child: TabBarView(
                  children: [
                    _buildTaskTab('daily'),
                    _buildTaskTab('project'),
                    _buildTaskTab('personal'),
                    _buildTaskTab('monthly'),
                    _buildTaskTab('quarterly'),
                    _buildTaskTab('yearly'),
                    _buildTaskTab('other'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskTab(String category) {
    if (_isLoadingTasks) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_tasksError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Colors.red.shade300),
            const SizedBox(height: 8),
            Text(
              _tasksError!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _fetchTasks,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    var tasksForCategory =
        _tasks.where((t) => t.category == category).toList();
    if (_statusFilter != null) {
      tasksForCategory = tasksForCategory
          .where((t) => t.status == _statusFilter)
          .toList();
    }

    if (tasksForCategory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.task_outlined,
                size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'No tasks in this category',
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

    return RefreshIndicator(
      onRefresh: _fetchTasks,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: tasksForCategory.length,
        itemBuilder: (context, index) {
          final task = tasksForCategory[index];
          return _buildTaskCard(task);
        },
      ),
    );
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
      default:
        return Colors.grey;
    }
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
      default:
        return Colors.grey.shade50;
    }
  }

  /// Subtask uses same status colors as task
  Color _getSubtaskStatusColor(String status) => _getStatusColor(status);

  /// Build updated subtasks list with one item's status changed; then call API.
  Future<void> _updateSubtaskStatus(Task task, int index, String newStatus) async {
    final list = task.subtasksWithStatus;
    if (index < 0 || index >= list.length) return;
    final updated = list.asMap().entries.map((e) {
      final st = e.value;
      return {
        'text': st.text,
        'status': e.key == index ? newStatus : st.status,
      };
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

  /// Show small popup to pick subtask status; then call onSelected and optionally update task.
  Future<void> _showSubtaskStatusPicker({
    required BuildContext context,
    required String currentStatus,
    required void Function(String) onSelected,
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
                      onSelected: (_) {
                        onSelected(s);
                        Navigator.pop(ctx);
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

  Widget _buildTaskCard(Task task) {
    final statusColor = _getStatusColor(task.status);

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
                      child: Text(
                        task.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
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
                    style:
                        TextStyle(fontSize: 14, color: Colors.grey.shade600),
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
                  ...task.subtasksWithStatus.take(3).toList().asMap().entries.map(
                    (entry) {
                      final idx = entry.key;
                      final st = entry.value;
                      final color = _getSubtaskStatusColor(st.status);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
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
                                onTap: () => _showSubtaskStatusPicker(
                                  context: context,
                                  currentStatus: st.status,
                                  onSelected: (s) =>
                                      _updateSubtaskStatus(task, idx, s),
                                ),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: color, width: 1.5),
                                  ),
                                  child: Icon(
                                    Icons.flag,
                                    size: 16,
                                    color: color,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  if (task.subtasksWithStatus.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '+${task.subtasksWithStatus.length - 3} more',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openTaskDetails(Task task) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final statusColor = _getStatusColor(task.status);
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
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
                      onPressed: () => Navigator.pop(context),
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
                if (task.descriptionOnly != null &&
                    task.descriptionOnly!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Description',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
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
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...task.subtasksWithStatus.toList().asMap().entries.map(
                    (entry) {
                      final idx = entry.key;
                      final st = entry.value;
                      final color = _getSubtaskStatusColor(st.status);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
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
                                onTap: () => _showSubtaskStatusPicker(
                                  context: context,
                                  currentStatus: st.status,
                                  onSelected: (s) =>
                                      _updateSubtaskStatus(task, idx, s),
                                ),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: color, width: 1.5),
                                  ),
                                  child: Icon(
                                    Icons.flag,
                                    size: 18,
                                    color: color,
                                  ),
                                ),
                              ),
                            ),
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
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _openTaskEdit(task);
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit Task'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _openStatusChange(task);
                        },
                        icon: const Icon(Icons.flag_outlined),
                        label: const Text('Change Status'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static const _categories = [
    'daily', 'project', 'personal', 'monthly', 'quarterly', 'yearly', 'other',
  ];
  static const _priorities = ['low', 'medium', 'high', 'critical'];
  static const _taskStatuses = [
    'assigned', 'in_progress', 'completed', 'paused', 'need_help',
  ];

  Future<void> _openTaskEdit(Task task) async {
    final titleController = TextEditingController(text: task.title);
    final descriptionController =
        TextEditingController(text: task.descriptionOnly ?? '');
    String taskStatus = task.status;
    String priority = task.priority;
    String category = task.category;
    DateTime? deadlineDate = task.deadlineDate != null
        ? _parseDate(task.deadlineDate!)
        : null;
    TimeOfDay? deadlineTime = task.deadlineTime != null
        ? _parseTime(task.deadlineTime!)
        : null;

    final subtaskEntries = <_EditSubtaskEntry>[];
    for (final st in task.subtasksWithStatus) {
      subtaskEntries.add(_EditSubtaskEntry(
        TextEditingController(text: st.text),
        st.status,
      ));
    }
    if (subtaskEntries.isEmpty) {
      subtaskEntries.add(_EditSubtaskEntry(
        TextEditingController(),
        'assigned',
      ));
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 8,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  ),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                              onPressed: () {
                                for (final e in subtaskEntries) {
                                  e.controller.dispose();
                                }
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                        _buildEditSection('Task Title'),
                        TextField(
                          controller: titleController,
                          decoration: _inputDecoration('Title'),
                        ),
                        const SizedBox(height: 16),
                        _buildEditSection('Description'),
                        TextField(
                          controller: descriptionController,
                          maxLines: 3,
                          decoration: _inputDecoration('Description'),
                        ),
                        const SizedBox(height: 16),
                        _buildEditSection('Task Status'),
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
                              onSelected: (_) =>
                                  setModalState(() => taskStatus = s),
                              selectedColor: color.withValues(alpha: 0.2),
                              backgroundColor: Colors.grey.shade100,
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        _buildEditSection('Priority'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _priorities.map((p) {
                            final selected = priority == p;
                            return ChoiceChip(
                              label: Text(p[0].toUpperCase() + p.substring(1)),
                              selected: selected,
                              onSelected: (_) =>
                                  setModalState(() => priority = p),
                              selectedColor: _gold.withValues(alpha: 0.2),
                              backgroundColor: Colors.grey.shade100,
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        _buildEditSection('Category'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _categories.map((c) {
                            final selected = category == c;
                            return ChoiceChip(
                              label: Text(c[0].toUpperCase() + c.substring(1)),
                              selected: selected,
                              onSelected: (_) =>
                                  setModalState(() => category = c),
                              selectedColor: _gold.withValues(alpha: 0.2),
                              backgroundColor: Colors.grey.shade100,
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        _buildEditSection('Deadline'),
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
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: _gold,
                                    side: const BorderSide(color: _gold)),
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
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: _gold,
                                    side: const BorderSide(color: _gold)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildEditSection('Subtasks'),
                        ...subtaskEntries.asMap().entries.map((entry) {
                          final i = entry.key;
                          final e = entry.value;
                          final stColor = _getSubtaskStatusColor(e.status);
                          return Padding(
                            key: ValueKey('$i-${e.status}'),
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: e.controller,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                    decoration: _inputDecoration('Subtask'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _showSubtaskStatusPicker(
                                      context: context,
                                      currentStatus: e.status,
                                      onSelected: (s) =>
                                          setModalState(() => e.status = s),
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: stColor.withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: stColor, width: 1.5),
                                      ),
                                      child: Icon(
                                        Icons.flag,
                                        size: 18,
                                        color: stColor,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: subtaskEntries.length > 1
                                      ? () {
                                          e.controller.dispose();
                                          setModalState(() {
                                            subtaskEntries.removeAt(i);
                                          });
                                        }
                                      : null,
                                ),
                              ],
                            ),
                          );
                        }),
                        OutlinedButton.icon(
                          onPressed: () => setModalState(() {
                            subtaskEntries.add(_EditSubtaskEntry(
                              TextEditingController(),
                              'assigned',
                            ));
                          }),
                          icon: const Icon(Icons.add, size: 20),
                          label: const Text('Add subtask'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _gold,
                            side: const BorderSide(color: _gold),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: () async {
                              final subtasksPayload = subtaskEntries
                                  .map((e) => {
                                        'text': e.controller.text.trim(),
                                        'status': e.status,
                                      })
                                  .where((m) => m['text']!.toString().isNotEmpty)
                                  .toList();
                              final updatedData = {
                                'title': titleController.text.trim(),
                                'description':
                                    descriptionController.text.trim().isEmpty
                                        ? null
                                        : descriptionController.text.trim(),
                                'status': taskStatus,
                                'priority': priority,
                                'category': category,
                                'subtasks': subtasksPayload.isEmpty
                                    ? null
                                    : subtasksPayload,
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
                                for (final e in subtaskEntries) {
                                  e.controller.dispose();
                                }
                                Navigator.pop(context);
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
                                      e.toString()
                                          .replaceFirst('Exception: ', '')
                                          .trim(),
                                    ),
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _gold,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text(
                              'Save',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEditSection(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String? hint) {
    return InputDecoration(
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  DateTime? _parseDate(String d) {
    final parts = d.split(RegExp(r'[-/]'));
    if (parts.length >= 3) {
      final y = int.tryParse(parts[0].length == 4 ? parts[0] : parts[2]);
      final m = int.tryParse(parts[1]);
      final day = int.tryParse(parts[0].length == 4 ? parts[2] : parts[0]);
      if (y != null && m != null && day != null) {
        return DateTime(y, m, day);
      }
    }
    return null;
  }

  TimeOfDay? _parseTime(String t) {
    final parts = t.split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) return TimeOfDay(hour: h, minute: m);
    }
    return null;
  }

  Future<void> _openStatusChange(Task task) async {
    String selectedStatus = task.status;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Change Status',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _statusChoiceChip(
                        'assigned',
                        'Assigned',
                        selectedStatus,
                        (val) => setModalState(() {
                          selectedStatus = val;
                        }),
                      ),
                      _statusChoiceChip(
                        'in_progress',
                        'In Progress',
                        selectedStatus,
                        (val) => setModalState(() {
                          selectedStatus = val;
                        }),
                      ),
                      _statusChoiceChip(
                        'completed',
                        'Completed',
                        selectedStatus,
                        (val) => setModalState(() {
                          selectedStatus = val;
                        }),
                      ),
                      _statusChoiceChip(
                        'paused',
                        'Paused',
                        selectedStatus,
                        (val) => setModalState(() {
                          selectedStatus = val;
                        }),
                      ),
                      _statusChoiceChip(
                        'need_help',
                        'Need Help',
                        selectedStatus,
                        (val) => setModalState(() {
                          selectedStatus = val;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await TaskService.updateTaskStatus(
                            task.id,
                            selectedStatus,
                          );
                          if (!mounted) return;
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Status updated'),
                            ),
                          );
                          _fetchTasks();
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                e.toString()
                                    .replaceFirst('Exception: ', '')
                                    .trim(),
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text(
                        'Apply',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _statusChoiceChip(
    String value,
    String label,
    String selected,
    void Function(String) onSelected,
  ) {
    final isSelected = value == selected;
    final color = _getStatusColor(value);
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(value),
      selectedColor: color.withValues(alpha: 0.15),
      backgroundColor: Colors.grey.shade100,
      labelStyle: TextStyle(
        color: isSelected ? color : Colors.grey.shade700,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }
}
