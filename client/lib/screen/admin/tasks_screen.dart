import 'package:flutter/material.dart';
import '../../services/task_service.dart';
import '../../services/user_service.dart';
import '../../models/task_model.dart';
import 'create_task_screen.dart';

class TasksScreen extends StatefulWidget {
  final String userId;
  final String userRole;

  const TasksScreen({super.key, required this.userId, required this.userRole});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<Task> _tasks = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedFilter = 'all';

  // Admin-specific state
  String _viewMode = 'self'; // 'self' or 'employee'
  List<Map<String, dynamic>> _employees = [];
  bool _isEmployeesLoading = false;
  String? _selectedEmployeeId;
  String? _selectedEmployeeName;

  @override
  void initState() {
    super.initState();
    // Default to self-view; employees don't see extra options
    _viewMode = 'self';
    _fetchTasks();
    if (widget.userRole == 'admin') {
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
            _buildEmployeeSelector(),
          ],
        ],
      ),
    );
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

      if (widget.userRole == 'admin' && _viewMode == 'employee') {
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

        // For admin self view, show only tasks that belong to the admin
        if (widget.userRole == 'admin' && _viewMode == 'self') {
          tasks = tasks
              .where((task) =>
                  task.assignedTo == widget.userId ||
                  task.createdBy == widget.userId)
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
        setState(() {
          _employees = data
              .map<Map<String, dynamic>>((e) => {
                    'id': e['id']?.toString() ?? '',
                    'name': e['name']?.toString() ?? 'Unknown',
                    'employeeCode': e['employeeCode']?.toString() ?? '',
                  })
              .where((e) => e['id'].toString().isNotEmpty)
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
    if (_selectedFilter == 'all') return _tasks;
    return _tasks.where((task) => task.status == _selectedFilter).toList();
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

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'daily':
        return Icons.today;
      case 'project':
        return Icons.work;
      case 'personal':
        return Icons.person;
      case 'family':
        return Icons.family_restroom;
      case 'other':
        return Icons.more_horiz;
      default:
        return Icons.task;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.userRole == 'admin') _buildAdminModeSelector(),
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
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateTaskScreen(
                userId: widget.userId,
                userRole: widget.userRole,
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

  Widget _buildFilterChips() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              const Icon(Icons.filter_alt_outlined,
                  size: 18, color: Color(0xFF9E9E9E)),
              const SizedBox(width: 6),
              Text(
                'Filter by status',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.task_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No Tasks Found',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first task to get started',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () {
          // TODO: Navigate to task details
        },
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
                  ],
                ),
                if (task.description != null &&
                    task.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    task.description!,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
