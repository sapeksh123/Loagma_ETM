import 'package:flutter/material.dart';

import '../../widgets/attendance_card.dart';
import '../../models/task_model.dart';
import '../../services/auth_service.dart';
import '../../services/task_service.dart';
import '../../services/notification_service.dart';
import '../../services/chat_service.dart';
import 'employee_notifications_screen.dart';
import 'employee_chat_list_screen.dart';
import '../admin/create_task_screen.dart';
import '../admin/admin_dashboard.dart';
import '../admin/notepad_list_screen.dart';
import '../task/hidden_tasks_screen.dart';
import '../../widgets/calculator_app_bar_action.dart';
import '../../widgets/notepad_app_bar_action.dart';
import '../../widgets/developer_switch_dialog.dart';

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
  String? _assignmentByFilter;
  int _unreadNotifications = 0;
  int _unreadChats = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    await Future.wait([
      _fetchTasks(),
      _loadNotificationsSummary(),
      _loadChatSummary(),
    ]);
  }

  Future<void> _fetchTasks() async {
    final hasExistingTasks = _tasks.isNotEmpty;
    setState(() {
      _isLoadingTasks = !hasExistingTasks;
      _tasksError = null;
    });

    try {
      final response = await TaskService.getTasks(
        widget.userId,
        widget.userRole,
        view: 'minimal',
        includeHistory: false,
      );

      if (response['status'] == 'success') {
        final List<dynamic> tasksData = response['data'] ?? [];
        setState(() {
          _tasks = tasksData.map((json) => Task.fromJson(json)).toList();
          _isLoadingTasks = false;
        });
      } else {
        setState(() {
          _tasksError = (response['message'] ?? 'Failed to load tasks')
              .toString();
          _isLoadingTasks = false;
        });
      }
    } catch (e) {
      setState(() {
        _tasksError = e.toString().replaceFirst('Exception: ', '').trim();
        _isLoadingTasks = false;
      });
    }
  }

  Future<void> _loadNotificationsSummary() async {
    try {
      final list = await NotificationService.fetchNotifications(widget.userId);
      if (!mounted) return;
      setState(() {
        _unreadNotifications = list.where((n) => !n.isRead).length.clamp(0, 99);
      });
    } catch (_) {
      // Ignore errors for badge; keep badge at 0 on failure.
    }
  }

  Future<void> _loadChatSummary() async {
    try {
      final threads = await ChatService.getThreads(
        userId: widget.userId,
        role: widget.userRole,
      );
      if (!mounted) return;
      final unread = threads
          .where((t) => t.unreadCount > 0)
          .fold<int>(0, (sum, t) => sum + t.unreadCount);
      setState(() {
        _unreadChats = unread.clamp(0, 99);
      });
    } catch (_) {
      // Ignore errors for badge.
    }
  }

  static const Color _gold = Color(0xFFceb56e);

  Future<void> _openDeveloperSwitch() async {
    final switchedUser = await DeveloperSwitchDialog.show(context);
    if (!mounted || switchedUser == null) return;

    if (switchedUser.role == 'employee') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => EmployeeDashboard(
            userId: switchedUser.id,
            userRole: switchedUser.role,
            userName: switchedUser.name,
          ),
        ),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AdminDashboard(
          userId: switchedUser.id,
          userName: switchedUser.name,
          userRole: switchedUser.role,
        ),
      ),
    );
  }

  Future<void> _onDeveloperTriggerFromDrawer() async {
    Navigator.of(context).pop();
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    await _openDeveloperSwitch();
  }

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
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
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
                              color: isSelected ? _gold : Colors.grey.shade200,
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
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
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

  String _assignmentFilterLabel(String value) {
    switch (value) {
      case 'self':
        return 'Assigned to Self';
      case 'admin':
        return 'Assigned by Admin';
      case 'subadmin':
        return 'Assigned by Sub-Admin';
      case 'techincharge':
        return 'Assigned by Tech Incharge';
      default:
        return 'All assignment types';
    }
  }

  void _showAssignmentByFilterPopup(BuildContext context) {
    final options = const [
      {'value': null, 'label': 'All assignment types'},
      {'value': 'self', 'label': 'Assigned to Self'},
      {'value': 'admin', 'label': 'Assigned by Admin'},
      {'value': 'subadmin', 'label': 'Assigned by Sub-Admin'},
      {'value': 'techincharge', 'label': 'Assigned by Tech Incharge'},
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
                      'Filter by assignment',
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
                  'Show tasks by assignment source.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                ...options.map((opt) {
                  final value = opt['value'];
                  final label = opt['label']!;
                  final isSelected = _assignmentByFilter == value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _assignmentByFilter = value;
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
                              color: isSelected ? _gold : Colors.grey.shade200,
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
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
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
      await AuthService.logout();
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
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

  Future<void> _moveTaskToCurrent(Task task) async {
    if (!_canChangeTaskStatus(task)) return;
    try {
      await TaskService.moveToCurrentTask(
        task.id,
        userId: widget.userId,
        userRole: widget.userRole,
      );
      if (!mounted) return;
      await _fetchTasks();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Moved "${task.title}" to current task'),
          backgroundColor: Colors.blue.shade700,
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
    final canMoveCurrent = _canChangeTaskStatus(task);
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
                if (canMoveCurrent)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.blue,
                    ),
                    title: const Text('Move to Current Task'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _moveTaskToCurrent(task);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: DefaultTabController(
        length: 7, // one for each category tab
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
              buildNotepadAppBarAction(
                context,
                userId: widget.userId,
                userRole: widget.userRole,
                userName: widget.userName,
              ),
              buildCalculatorAppBarAction(context),
              IconButton(
                icon: const Icon(Icons.visibility_off_outlined),
                tooltip: 'Hidden tasks',
                onPressed: _openHiddenTasks,
              ),
              IconButton(
                icon: Icon(
                  _assignmentByFilter != null
                      ? Icons.assignment_ind
                      : Icons.assignment_ind_outlined,
                  color: _assignmentByFilter != null
                      ? Colors.black87
                      : Colors.white,
                ),
                tooltip: _assignmentByFilter != null
                    ? 'Filter: ${_assignmentFilterLabel(_assignmentByFilter!)} (tap to change)'
                    : 'Filter by assignment',
                onPressed: () => _showAssignmentByFilterPopup(context),
              ),
              IconButton(
                icon: Icon(
                  _statusFilter != null
                      ? Icons.filter_list
                      : Icons.filter_list_outlined,
                  color: _statusFilter != null ? Colors.black87 : Colors.white,
                ),
                tooltip: _statusFilter != null
                    ? 'Filter: ${_statusFilter!.replaceAll('_', ' ')} (tap to change)'
                    : 'Filter by status',
                onPressed: () => _showStatusFilterPopup(context),
              ),
              IconButton(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.chat_bubble_outline),
                    if (_unreadChats > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _unreadChats > 9 ? '9+' : _unreadChats.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                tooltip: 'Chat',
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EmployeeChatListScreen(
                        userId: widget.userId,
                        userRole: widget.userRole,
                      ),
                    ),
                  );
                  _loadChatSummary();
                },
              ),
              IconButton(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_outlined),
                    if (_unreadNotifications > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _unreadNotifications > 9
                                ? '9+'
                                : _unreadNotifications.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                tooltip: 'Notifications',
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EmployeeNotificationsScreen(
                        userId: widget.userId,
                        userRole: widget.userRole,
                      ),
                    ),
                  );
                  _loadNotificationsSummary();
                },
              ),
            ],
          ),

          drawer: Drawer(
            width: MediaQuery.of(context).size.width * 0.85,
            backgroundColor: Colors.grey.shade50,
            child: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 24,
                      ),
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
                                    Icon(
                                      Icons.badge_outlined,
                                      size: 16,
                                      color: Colors.grey.shade600,
                                    ),
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
                                    Icon(
                                      Icons.tag,
                                      size: 16,
                                      color: Colors.grey.shade600,
                                    ),
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
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ListTile(
                              leading: Icon(
                                Icons.note_alt_outlined,
                                color: Colors.amber.shade700,
                              ),
                              title: const Text(
                                'My Notepad',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                'Only your personal notes',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () async {
                                Navigator.of(context).pop();
                                await Future.delayed(
                                  const Duration(milliseconds: 100),
                                );
                                if (!context.mounted) return;
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => NotepadListScreen(
                                      userId: widget.userId,
                                      userRole: widget.userRole,
                                      userName: widget.userName,
                                      showAppBar: true,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onDoubleTap: _onDeveloperTriggerFromDrawer,
                            child: const SizedBox(
                              width: double.infinity,
                              height: 26,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade100),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text(
                        'Logout',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    
                      onTap: () async {
                        Navigator.of(context).pop(); // close drawer first
                        await Future.delayed(const Duration(milliseconds: 120));
                        if (!context.mounted) return;
                        await _showLogoutConfirmation(context);
                      },
                    ),
                  ),
                ],
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
                    showAssignToSelector: false,
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
                  padding: const EdgeInsets.symmetric(horizontal: 4),
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
                    Tab(
                      icon: Icon(Icons.person_outline, size: 22),
                      text: "Personal",
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
                    _buildTaskTab('monthly'),
                    _buildTaskTab('quarterly'),
                    _buildTaskTab('yearly'),
                    _buildTaskTab('personal'),
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
    if (_isLoadingTasks && _tasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_tasksError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
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

    var tasksForCategory = _tasks.where((t) => t.category == category).toList();
    if (_statusFilter != null) {
      tasksForCategory = tasksForCategory
          .where((t) => t.status == _statusFilter)
          .toList();
    }
    if (_assignmentByFilter != null) {
      tasksForCategory = tasksForCategory.where((t) {
        if (_assignmentByFilter == 'self') {
          return t.isAssignedToSelf;
        }
        return t.normalizedCreatorRole == _assignmentByFilter;
      }).toList();
    }

    if (tasksForCategory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.task_outlined, size: 60, color: Colors.grey.shade400),
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
        itemCount: tasksForCategory.length + (_isLoadingTasks ? 1 : 0),
        itemBuilder: (context, index) {
          if (_isLoadingTasks && index == 0) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(minHeight: 3),
            );
          }
          final task = tasksForCategory[_isLoadingTasks ? index - 1 : index];
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

  /// Subtask uses same status colors as task
  Color _getSubtaskStatusColor(String status) => _getStatusColor(status);

  bool _isManagerCreatedTask(Task task) {
    return const {'admin', 'subadmin', 'techincharge'}.contains(
      task.normalizedCreatorRole,
    );
  }

  bool _canEditTask(Task task) {
    return task.createdBy == widget.userId;
  }

  bool _canDeleteTask(Task task) {
    return _canEditTask(task);
  }

  bool _canChangeTaskStatus(Task task) {
    if (task.createdBy == widget.userId) return true;
    // Employee can update status when a manager-created task is assigned to them.
    return task.assignedTo == widget.userId && _isManagerCreatedTask(task);
  }

  /// Shows a status-note dialog. Empty note is allowed, but dialog is always shown.
  Future<String?> _showNeedHelpNoteDialog({
    String title = 'Status Note',
    String hint = 'Add a note for this status (optional)',
  }) async {
    final controller = TextEditingController();
    final scaffoldContext = this.context;
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
              const Icon(Icons.sticky_note_2_outlined, color: Colors.brown, size: 26),
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
                Navigator.pop(ctx, note);
              },
              style: ElevatedButton.styleFrom(backgroundColor: _gold),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  /// Build updated subtasks list with one item's status changed; then call API.
  /// When [newStatus] is need_help, [needHelpNote] can be set to update task-level help note.
  Future<void> _updateSubtaskStatus(
    Task task,
    int index,
    String newStatus, {
    String? needHelpNote,
  }) async {
    final list = task.subtasksWithStatus;
    if (index < 0 || index >= list.length) return;
    final updated = list.asMap().entries.map((e) {
      final st = e.value;
      final isTarget = e.key == index;
      final status = isTarget ? newStatus : st.status;
      final map = <String, dynamic>{'text': st.text, 'status': status};
      if (status == 'need_help') {
        if (isTarget && needHelpNote != null && needHelpNote.isNotEmpty) {
          map['need_help_note'] = needHelpNote;
        } else if (st.needHelpNote != null && st.needHelpNote!.isNotEmpty) {
          map['need_help_note'] = st.needHelpNote;
        }
      }
      return map;
    }).toList();
    try {
      if (newStatus == 'need_help') {
        await TaskService.updateTaskStatus(
          task.id,
          'need_help',
          userId: widget.userId,
          userRole: widget.userRole,
        );
      }
      await TaskService.updateTask(
        task.id,
        {'subtasks': updated},
        widget.userId,
        widget.userRole,
      );
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

  /// Show small popup to pick subtask status; then call onSelected (async supported for need_help note).
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
    final currentColor = Colors.blue.shade700;
    final accentColor = task.isCurrent ? currentColor : statusColor;
    final canChangeStatus = _canChangeTaskStatus(task);
    final canEdit = _canEditTask(task);
    final canDelete = _canDeleteTask(task);
    final priorityColor = _getPriorityColor(task.priority);
    final isNeedHelp = task.status == 'need_help';
    final cardBorderColor = isNeedHelp ? Colors.grey : accentColor;
    final cardBackground = task.isCurrent
      ? Colors.blue.shade50.withValues(alpha: 0.5)
      : isNeedHelp
        ? Colors.grey.shade50
        : _getStatusBackground(task.status);
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
        onLongPress: () => _showTaskLongPressActions(task),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border(left: BorderSide(color: cardBorderColor, width: 4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
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
                    if (task.deadlineDate != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 12,
                              color: Colors.grey.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              task.deadlineDate!,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade700,
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
                            softWrap: true,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$categoryLabel • $statusLabel',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          if (task.isCurrent) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'CURRENT',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: currentColor,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: canChangeStatus
                            ? () => _openStatusChange(task)
                            : null,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: statusColor,
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.flag,
                            size: 16,
                            color: canChangeStatus
                                ? statusColor
                                : statusColor.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (task.descriptionOnly != null &&
                    task.descriptionOnly!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    task.descriptionOnly!,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      height: 1.35,
                    ),
                    softWrap: true,
                  ),
                ],
                if (task.subtasksWithStatus.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Subtasks',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...task.subtasksWithStatus
                      .toList()
                      .asMap()
                      .entries
                      .map((entry) {
                        final idx = entry.key;
                        final st = entry.value;
                        final color = _getSubtaskStatusColor(st.status);
                        final showSubtaskHelp =
                            st.status == 'need_help' &&
                            st.needHelpNote != null &&
                            st.needHelpNote!.isNotEmpty;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
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
                                          height: 1.35,
                                          decoration: st.status == 'completed'
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                        softWrap: true,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: canChangeStatus
                                            ? () => _showSubtaskStatusPicker(
                                                context: context,
                                                currentStatus: st.status,
                                                onSelected: (s) async {
                                                  final note =
                                                      await _showNeedHelpNoteDialog(
                                                        title: 'Status Note',
                                                        hint:
                                                            'Add a note for status: ${s.replaceAll('_', ' ').toUpperCase()} (optional)',
                                                      );
                                                  if (note == null) return;
                                                  await _updateSubtaskStatus(
                                                    task,
                                                    idx,
                                                    s,
                                                    needHelpNote: note,
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
                                            color: canChangeStatus
                                                ? color
                                                : color.withValues(alpha: 0.5),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
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
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.red.shade200,
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.help_outline,
                                          size: 14,
                                          color: Colors.red.shade700,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            st.needHelpNote!,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade800,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
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
                if (task.status == 'need_help' &&
                    task.needHelpNote != null &&
                    task.needHelpNote!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.help_outline,
                              size: 16,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Your help request',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          task.needHelpNote!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade800,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (task.assigneeName != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
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
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey.shade700,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                task.isAssignedToSelf
                                    ? Icons.person
                                    : Icons.admin_panel_settings,
                                size: 14,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                task.assignmentByLabel(),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade700,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (canEdit)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 18),
                        onSelected: (value) async {
                          if (value == 'edit') {
                            await _openTaskEdit(task);
                          } else if (value == 'delete') {
                            await _deleteTaskFromCard(task);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit task'),
                          ),
                          if (canDelete)
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete task'),
                            ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteTaskFromCard(Task task) async {
    if (!_canDeleteTask(task)) return;
    final confirm =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Delete task?'),
            content: const Text('This will permanently delete this task.'),
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
    if (!confirm) return;

    try {
      await TaskService.deleteTask(task.id, widget.userId, widget.userRole);
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
      builder: (context) {
        final statusColor = _getStatusColor(task.status);
        final canEdit = _canEditTask(task);
        final canChangeStatus = _canChangeTaskStatus(task);
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
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
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
                  ...task.subtasksWithStatus.toList().asMap().entries.map((
                    entry,
                  ) {
                    final idx = entry.key;
                    final st = entry.value;
                    final color = _getSubtaskStatusColor(st.status);
                    final showSubtaskHelp =
                        st.status == 'need_help' &&
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
                                  onTap: canChangeStatus
                                      ? () => _showSubtaskStatusPicker(
                                          context: context,
                                          currentStatus: st.status,
                                          onSelected: (s) async {
                                            final note =
                                                await _showNeedHelpNoteDialog(
                                                  title: 'Status Note',
                                                  hint:
                                                      'Add a note for status: ${s.replaceAll('_', ' ').toUpperCase()} (optional)',
                                                );
                                            if (note == null) return;
                                            await _updateSubtaskStatus(
                                              task,
                                              idx,
                                              s,
                                              needHelpNote: note,
                                            );
                                          },
                                        )
                                      : null,
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
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
                                      size: 18,
                                      color: canChangeStatus
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
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Colors.red.shade200,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.help_outline,
                                      size: 14,
                                      color: Colors.red.shade700,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        st.needHelpNote!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade800,
                                        ),
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
                    if (task.isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'CURRENT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
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
                    SizedBox(
                      width: double.infinity,
                      child: Text(
                        task.assignmentByLabel(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (task.status == 'need_help' &&
                        task.needHelpNote != null &&
                        task.needHelpNote!.isNotEmpty)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.help_outline,
                                  size: 16,
                                  color: Colors.red.shade700,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Your help request',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              task.needHelpNote!,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (canEdit) ...[
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
                          onPressed: canChangeStatus
                              ? () {
                                  Navigator.pop(context);
                                  _openStatusChange(task);
                                }
                              : null,
                          icon: const Icon(Icons.flag_outlined),
                          label: const Text('Change Status'),
                        ),
                      ),
                    ],
                  ),
                ] else if (canChangeStatus) ...[
                  SizedBox(
                    width: double.infinity,
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
              ],
            ),
          ),
        );
      },
    );
  }

  static const _categories = [
    'daily',
    'project',
    'monthly',
    'quarterly',
    'yearly',
    'personal',
    'other',
  ];
  static const _priorities = ['low', 'medium', 'high', 'critical'];
  static const _taskStatuses = [
    'assigned',
    'in_progress',
    'completed',
    'paused',
    'need_help',
  ];

  Future<void> _openTaskEdit(Task task) async {
    final titleController = TextEditingController(text: task.title);
    final descriptionController = TextEditingController(
      text: task.descriptionOnly ?? '',
    );
    String taskStatus = task.status;
    final String initialTaskStatus = task.status;
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
      subtaskEntries.add(
        _EditSubtaskEntry(TextEditingController(text: st.text), st.status),
      );
    }
    if (subtaskEntries.isEmpty) {
      subtaskEntries.add(
        _EditSubtaskEntry(TextEditingController(), 'assigned'),
      );
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
                                  color: selected
                                      ? color
                                      : Colors.grey.shade700,
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
                                icon: const Icon(
                                  Icons.calendar_today,
                                  size: 18,
                                ),
                                label: Text(
                                  deadlineDate != null
                                      ? '${deadlineDate!.day}/${deadlineDate!.month}/${deadlineDate!.year}'
                                      : 'Date',
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _gold,
                                  side: const BorderSide(color: _gold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime:
                                        deadlineTime ?? TimeOfDay.now(),
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
                                  side: const BorderSide(color: _gold),
                                ),
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
                                      onSelected: (s) async {
                                        final note =
                                            await _showNeedHelpNoteDialog(
                                              title: 'Status Note',
                                              hint:
                                                  'Add a note for status: ${s.replaceAll('_', ' ').toUpperCase()} (optional)',
                                            );
                                        if (note == null) return;
                                        if (s == 'need_help') {
                                          await TaskService.updateTaskStatus(
                                            task.id,
                                            'need_help',
                                            needHelpNote: note,
                                            userId: widget.userId,
                                            userRole: widget.userRole,
                                          );
                                        }
                                        setModalState(() => e.status = s);
                                      },
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: stColor.withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: stColor,
                                          width: 1.5,
                                        ),
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
                            subtaskEntries.add(
                              _EditSubtaskEntry(
                                TextEditingController(),
                                'assigned',
                              ),
                            );
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
                                  .map(
                                    (e) => {
                                      'text': e.controller.text.trim(),
                                      'status': e.status,
                                    },
                                  )
                                  .where(
                                    (m) => m['text']!.toString().isNotEmpty,
                                  )
                                  .toList();
                              final updatedData = {
                                'title': titleController.text.trim(),
                                'description':
                                    descriptionController.text.trim().isEmpty
                                    ? null
                                    : descriptionController.text.trim(),
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
                                if (taskStatus != initialTaskStatus) {
                                  final statusNote =
                                      await _showNeedHelpNoteDialog(
                                        title: 'Status Note',
                                        hint:
                                            'Add a note for status: ${taskStatus.replaceAll('_', ' ').toUpperCase()} (optional)',
                                      );
                                  if (statusNote == null) return;
                                  await TaskService.updateTaskStatus(
                                    task.id,
                                    taskStatus,
                                    needHelpNote: statusNote,
                                    userId: widget.userId,
                                    userRole: widget.userRole,
                                  );
                                }
                                await TaskService.updateTask(
                                  task.id,
                                  updatedData,
                                  widget.userId,
                                  widget.userRole,
                                );
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
                                      e
                                          .toString()
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
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_canDeleteTask(task))
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: OutlinedButton.icon(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              label: const Text(
                                'Delete Task',
                                style: TextStyle(color: Colors.red),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.red),
                              ),
                              onPressed: () async {
                                final confirm =
                                    await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        title: const Text('Delete task?'),
                                        content: const Text(
                                          'This will permanently delete this task.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
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
                                if (!confirm) return;
                                try {
                                  await TaskService.deleteTask(
                                    task.id,
                                    widget.userId,
                                    widget.userRole,
                                  );
                                  if (!mounted) return;
                                  for (final e in subtaskEntries) {
                                    e.controller.dispose();
                                  }
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Task deleted'),
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
    final scaffoldContext = this.context;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                MediaQuery.of(context).viewInsets.bottom + 16,
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
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _moveTaskToCurrent(task);
                        },
                        icon: const Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.blue,
                        ),
                        label: const Text(
                          'Move To Current Task',
                          style: TextStyle(color: Colors.blue),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.blue.shade200),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        onPressed: () async {
                          final note = await _showNeedHelpNoteDialog(
                            title: 'Status Note',
                            hint:
                                'Add a note for status: ${selectedStatus.replaceAll('_', ' ').toUpperCase()} (optional)',
                          );
                          if (note == null) return;
                          try {
                            await TaskService.updateTaskStatus(
                              task.id,
                              selectedStatus,
                              needHelpNote: note,
                              userId: widget.userId,
                              userRole: widget.userRole,
                            );
                            if (!mounted) return;
                            Navigator.pop(context);
                            ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                              SnackBar(
                                content: const Text('Status updated'),
                                backgroundColor: Colors.green.shade700,
                              ),
                            );
                            _fetchTasks();
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(scaffoldContext).showSnackBar(
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _gold,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          'Submit',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
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
