import 'package:flutter/material.dart';

import '../../models/task_model.dart';
import '../../services/task_service.dart';

class HiddenTasksScreen extends StatefulWidget {
  final String userId;
  final String userRole;
  final String title;

  const HiddenTasksScreen({
    super.key,
    required this.userId,
    required this.userRole,
    this.title = 'Hidden Tasks',
  });

  @override
  State<HiddenTasksScreen> createState() => _HiddenTasksScreenState();
}

class _HiddenTasksScreenState extends State<HiddenTasksScreen> {
  List<Task> _tasks = [];
  bool _isLoading = true;
  String? _error;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _fetchHiddenTasks();
  }

  Future<void> _fetchHiddenTasks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await TaskService.getHiddenTasks(widget.userId, widget.userRole);
      if (response['status'] == 'success') {
        final data = (response['data'] as List<dynamic>? ?? const []);
        setState(() {
          _tasks = data
              .whereType<Map>()
              .map((e) => Task.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = (response['message'] ?? 'Failed to load hidden tasks').toString();
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '').trim();
        _isLoading = false;
      });
    }
  }

  Future<void> _restoreTask(Task task) async {
    try {
      final response = await TaskService.unhideTask(task.id, widget.userId, widget.userRole);
      if (response['status'] != 'success') {
        throw Exception((response['message'] ?? 'Failed to restore task').toString());
      }

      if (!mounted) return;
      setState(() {
        _tasks.removeWhere((t) => t.id == task.id);
        _hasChanges = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Task restored'),
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

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'low':
        return const Color(0xFF4CAF50);
      case 'medium':
        return const Color(0xFFFF9800);
      case 'high':
        return const Color(0xFFF44336);
      case 'critical':
        return const Color(0xFF8E24AA);
      default:
        return const Color(0xFF9E9E9E);
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

  Widget _buildHistoryStrip(List<DailyStatusEntry> entries) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: entries.map((e) {
          final dt = DateTime.tryParse(e.date);
          final dayLabel = dt != null
              ? '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}'
              : e.date;
          final color = _getStatusColor(e.status);
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.6)),
                color: color.withValues(alpha: 0.08),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dayLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Icon(Icons.circle, size: 7, color: color),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSubtaskBlock(Task task) {
    if (task.subtasksWithStatus.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          final color = _getStatusColor(st.status);
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
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: color, width: 1.5),
                      ),
                      child: Icon(Icons.flag, size: 16, color: color),
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
                if (task.category == 'daily' &&
                    task.subtaskHistory != null &&
                    task.subtaskHistory![idx] != null &&
                    task.subtaskHistory![idx]!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _buildHistoryStrip(task.subtaskHistory![idx]!),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }
Future<void> _openTaskDetails(Task task) async {
  final statusColor = _getStatusColor(task.status);

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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              /// HEADER
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Task Details',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),

              /// TITLE
              Text(
                task.title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),

              const SizedBox(height: 8),

              /// STATUS + PRIORITY + DATE
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  /// STATUS
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      task.status.replaceAll('_', ' ').toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),

                  /// PRIORITY
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      task.priority.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _getPriorityColor(task.priority),
                      ),
                    ),
                  ),

                  /// DEADLINE
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
                ],
              ),

              /// DESCRIPTION
              if (task.descriptionOnly != null &&
                  task.descriptionOnly!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Description',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  task.descriptionOnly!,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                ),
              ],

              /// SUBTASKS
              if (task.subtasksWithStatus.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Subtasks',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                ...task.subtasksWithStatus.map(
                  (st) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 10,
                          color: _getStatusColor(st.status),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            st.text,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade800,
                              decoration: st.status == 'completed'
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              /// NEED HELP NOTE
              if (task.needHelpNote != null &&
                  task.needHelpNote!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status note',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade700,
                        ),
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

              const SizedBox(height: 14),

              /// RESTORE BUTTON
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _restoreTask(task);
                  },
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Restore Task'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
} Widget _buildTaskCard(Task task) {
    final statusColor = _getStatusColor(task.status);
    final priorityColor = _getPriorityColor(task.priority);
    final assignedToLabel =
        (task.assigneeName != null && task.assigneeName!.trim().isNotEmpty)
        ? task.assigneeName!.trim()
        : task.assignedTo;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shadowColor: Colors.black.withOpacity(0.06),
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
                        color: const Color(0xFFceb56e).withOpacity(0.12),
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
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: priorityColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flag_rounded, size: 12, color: priorityColor),
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
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Restore task',
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      onPressed: () => _restoreTask(task),
                    ),
                  ],
                ),
                if (task.needHelpNote != null && task.needHelpNote!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                if (task.category == 'daily' && task.taskHistory != null && task.taskHistory!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildHistoryStrip(task.taskHistory!),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.circle, size: 8, color: statusColor),
                    const SizedBox(width: 6),
                    Text(
                      task.status.replaceAll('_', ' '),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      task.category[0].toUpperCase() + task.category.substring(1),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    if (task.deadlineDate != null) ...[
                      const SizedBox(width: 10),
                      Icon(Icons.calendar_today, size: 13, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          task.deadlineDate!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ],
                ),
                if (task.descriptionOnly != null && task.descriptionOnly!.isNotEmpty) ...[
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
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                _buildSubtaskBlock(task),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        task.status.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (task.deadlineDate != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today, size: 14),
                          const SizedBox(width: 4),
                          Text(task.deadlineDate!, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Assigned to: $assignedToLabel',
                        style: const TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.person, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        task.assignmentByLabel(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) {
          Navigator.of(context).pop(_hasChanges);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_hasChanges),
          ),
          title: Text(widget.title),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _fetchHiddenTasks,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _tasks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.visibility_off_outlined,
                              size: 56,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'No hidden tasks',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchHiddenTasks,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                          itemCount: _tasks.length,
                          itemBuilder: (context, index) {
                            final task = _tasks[index];
                            return _buildTaskCard(task);
                          },
                        ),
                      ),
      ),
    );
  }
}
