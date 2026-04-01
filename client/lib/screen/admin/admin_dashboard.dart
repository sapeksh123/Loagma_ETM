import 'package:flutter/material.dart';
import '../../widgets/app_drawer.dart';
import '../../services/auth_service.dart';
import '../../services/dashboard_service.dart';
import '../../services/task_service.dart';
import '../../models/task_model.dart';
import 'employees_screen.dart';
import 'tasks_screen.dart';
import 'attendance_screen.dart';
import 'admin_chat_list_screen.dart';
import 'notepad_list_screen.dart';
import '../../widgets/developer_switch_dialog.dart';
import '../../widgets/calculator_app_bar_action.dart';
import '../../widgets/notepad_app_bar_action.dart';
import '../employee/employee_dashboard.dart';

class AdminDashboard extends StatefulWidget {
  final String? userId;
  final String? userName;
  final String userRole;

  const AdminDashboard({
    super.key,
    this.userId,
    this.userName,
    this.userRole = 'admin',
  });

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  String _tasksInitialViewMode = 'self'; // 'self' or 'employee'
  bool _lockTasksViewMode = false;

  bool _isStatsLoading = true;
  int _totalEmployees = 0;
  int _activeEmployees = 0;
  int _pendingSelfTasks = 0;
  int _pendingEmployeeTasks = 0;
  bool _hasTaskBreakdown = false;
  int _presentToday = 0;

  final List<String> _menuTitles = [
    'Dashboard',
    'Employees',
    'Tasks',
    'Attendance',
    'Reports',
    "Notepad",
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    _loadDashboardStats();
  }

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Future<void> _loadDashboardStats() async {
    setState(() {
      _isStatsLoading = true;
    });
    try {
      final response = await DashboardService.getSummary();

      int totalEmployees = 0;
      int activeEmployees = 0;
      int presentToday = 0;

      int pendingSelfTasks = 0;
      int pendingEmployeeTasks = 0;
      bool hasBreakdown = false;

      if (response['status'] == 'success') {
        final data =
            (response['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};

        totalEmployees = _asInt(data['employees_total']);
        activeEmployees = _asInt(data['employees_active']);
        presentToday = _asInt(data['present_today']);

        // Optional breakdown coming directly from backend, if available.
        final backendSelf =
            _asInt(data['tasks_self_pending'] ?? data['tasks_pending_self']);
        final backendEmployees = _asInt(
            data['tasks_employee_pending'] ?? data['tasks_pending_employee']);

        if (backendSelf > 0 || backendEmployees > 0) {
          pendingSelfTasks = backendSelf;
          pendingEmployeeTasks = backendEmployees;
          hasBreakdown = true;
        }
      }

      // If backend did not provide a breakdown but we know the admin ID,
      // fall back to computing it from the task list.
      if (!hasBreakdown && widget.userId != null && widget.userId!.isNotEmpty) {
        final tasksResponse =
            await TaskService.getTasks(
              widget.userId!,
              widget.userRole,
              view: 'minimal',
              includeHistory: false,
            );
        if (tasksResponse['status'] == 'success') {
          final List<dynamic> tasksData = tasksResponse['data'] ?? [];
          final tasks =
              tasksData.map<Task>((json) => Task.fromJson(json)).toList();

          bool isPendingStatus(String status) {
            return status == 'assigned' ||
                status == 'in_progress' ||
                status == 'paused' ||
                status == 'need_help';
          }

          final selfTasks = tasks.where((t) =>
              t.assignedTo == widget.userId && isPendingStatus(t.status));
          final employeeTasks = tasks.where((t) =>
              t.assignedTo != widget.userId && isPendingStatus(t.status));

          pendingSelfTasks = selfTasks.length;
          pendingEmployeeTasks = employeeTasks.length;
          hasBreakdown = true;
        }
      }

      setState(() {
        _totalEmployees = totalEmployees;
        _activeEmployees = activeEmployees;
        _presentToday = presentToday;
        _pendingSelfTasks = pendingSelfTasks;
        _pendingEmployeeTasks = pendingEmployeeTasks;
        _hasTaskBreakdown = hasBreakdown;
        _isStatsLoading = false;
      });
    } catch (e) {
      setState(() {
        _isStatsLoading = false;
      });
    }
  }

  Widget _getSelectedScreen() {
    switch (_selectedIndex) {
      case 0:
        return _buildDashboardHome();
      case 1:
        return _buildEmployeesScreen();
      case 2:
        return _buildTasksScreen();
      case 3:
        return _buildAttendanceScreen();
      case 4:
        return _buildReportsScreen();
      case 5:
        return _buildNotepadScreen();
      case 6:
        return _buildSettingsScreen();
      default:
        return _buildDashboardHome();
    }
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
          });
        }
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          leading: _selectedIndex == 0
              ? Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () {
                      Scaffold.of(context).openDrawer();
                    },
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      _selectedIndex = 0;
                    });
                  },
                ),
          title: Text(
            _menuTitles[_selectedIndex],
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          elevation: 0,
          actions: [
            buildCalculatorAppBarAction(context),
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              tooltip: 'Chat',
              onPressed: () {
                if (widget.userId == null || widget.userId!.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('User id missing. Please re-login as admin.'),
                    ),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminChatListScreen(
                      userId: widget.userId!,
                      userRole: widget.userRole,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.note_add_outlined),
              tooltip: 'Notepad',
              onPressed: () async {
                await showNotepadPopup(
                  context,
                  userId: widget.userId,
                  userRole: widget.userRole,
                  userName: widget.userName,
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () {},
            ),
         
          ],
        ),
        drawer: AppDrawer(
          selectedIndex: _selectedIndex,
          onItemSelected: (index) {
            setState(() {
              _selectedIndex = index;
              if (index == 2) {
                _tasksInitialViewMode = 'self';
                _lockTasksViewMode = false; // opened from drawer, allow switching
              }
            });
          },
          onLogout: () => _showLogoutConfirmation(context),
          onDeveloperSwitch: _openDeveloperSwitch,
          userName: widget.userName ?? '',
          userRole: widget.userRole,
        ),
        body: SafeArea(
          top: false,
          child: _getSelectedScreen(),
        ),
      ),
    );
  }

  Widget _buildDashboardHome() {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset + 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.1,
              children: [
                _buildDashboardCard(
                  context,
                  'Employees',
                  Icons.people_outline,
                  Colors.blue,
                  _isStatsLoading
                      ? 'Loading...'
                      : '${_activeEmployees > 0 ? _activeEmployees : _totalEmployees} Active',
                  () {
                    setState(() => _selectedIndex = 1);
                  },
                ),
                _buildDashboardCard(
                  context,
                  'Self Tasks',
                  Icons.task_alt,
                  Colors.orange,
                  _isStatsLoading
                      ? 'Loading...'
                      : _hasTaskBreakdown
                          ? '$_pendingSelfTasks Pending'
                          : 'Pending',
                  () {
                    setState(() {
                      _tasksInitialViewMode = 'self';
                      _selectedIndex = 2;
                      _lockTasksViewMode = true; // opened from card, lock mode
                    });
                  },
                ),
                _buildDashboardCard(
                  context,
                  'Employee Tasks',
                  Icons.group_outlined,
                  Colors.deepOrange,
                  _isStatsLoading
                      ? 'Loading...'
                      : _hasTaskBreakdown
                          ? '$_pendingEmployeeTasks Pending'
                          : 'Pending',
                  () {
                    setState(() {
                      _tasksInitialViewMode = 'employee';
                      _selectedIndex = 2;
                      _lockTasksViewMode = true; // opened from card, lock mode
                    });
                  },
                ),
                _buildDashboardCard(
                  context,
                  'Attendance',
                  Icons.access_time_outlined,
                  Colors.green,
                  _isStatsLoading ? 'Loading...' : '$_presentToday Present',
                  () {
                    setState(() => _selectedIndex = 3);
                  },
                ),
                _buildDashboardCard(
                  context,
                  'Reports',
                  Icons.bar_chart_outlined,
                  Colors.purple,
                  'View All',
                  () {
                    setState(() => _selectedIndex = 4);
                  },
                ),
                 _buildDashboardCard(
                  context,
                  'Notepad',
                  Icons.note_add_outlined,
                  Colors.purple,
                  'Take Notes',
                  () {
                    setState(() => _selectedIndex = 5);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeesScreen() {
    return const EmployeesScreen();
  }

  Widget _buildTasksScreen() {
    return TasksScreen(
      userId: widget.userId ?? 'admin-user-id',
      userRole: widget.userRole,
      initialViewMode: _tasksInitialViewMode,
      lockViewMode: _lockTasksViewMode,
    );
  }

  Widget _buildAttendanceScreen() {
    return const AttendanceScreen();
  }

  Widget _buildReportsScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart, size: 80, color: Colors.indigo.shade300),
          const SizedBox(height: 16),
          const Text(
            'Reports',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('View analytics and reports'),
        ],
      ),
    );
  }

  Widget _buildNotepadScreen() {
    return NotepadListScreen(
      userId: widget.userId ?? '',
      userRole: widget.userRole,
      userName: widget.userName,
    );
  }

  Widget _buildSettingsScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.settings, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'Settings',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('Configure application settings'),
        ],
      ),
    );
  }

  Widget _buildDashboardCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 3,
      shadowColor: color.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 36, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
