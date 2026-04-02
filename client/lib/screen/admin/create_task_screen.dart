import 'package:flutter/material.dart';
import '../../services/task_service.dart';
import '../../widgets/calculator_app_bar_action.dart';
import '../../widgets/notepad_app_bar_action.dart';

/// When non-null, Assign To section is hidden and task is assigned accordingly.
/// 'self' = assign to current user; 'employee' = assign to [assignedToEmployeeId].
enum CreateTaskAssignMode { self, employee }

class CreateTaskScreen extends StatefulWidget {
  final String userId;
  final String userRole;
  /// Controls whether the "Assign To" selector (self/employee) is visible.
  /// This is typically true for admin flows and false for employee self-creation.
  final bool showAssignToSelector;
  /// When set, hide "Assign To" and use this: self = assign to self, employee = assign to [assignedToEmployeeId].
  final CreateTaskAssignMode? assignMode;
  /// Required when [assignMode] is [CreateTaskAssignMode.employee].
  final String? assignedToEmployeeId;
  final String? assignedToEmployeeName;

  const CreateTaskScreen({
    super.key,
    required this.userId,
    required this.userRole,
    this.showAssignToSelector = true,
    this.assignMode,
    this.assignedToEmployeeId,
    this.assignedToEmployeeName,
  });

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

/// Holds one subtask row: unique id for stable keys + text controller.
class _SubtaskEntry {
  final String id;
  final TextEditingController controller;
  _SubtaskEntry(this.id, this.controller);
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  final _descriptionController = TextEditingController();
  final List<_SubtaskEntry> _subtaskEntries = [];

  String _selectedCategory = 'project';
  String _selectedPriority = 'medium';
  String _deadlinePreset = 'today'; // 'today' | '2days' | '1week' | 'custom'
  String _assignTo = 'self';
  String? _selectedEmployeeId;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isLoading = false;

  bool get _isManagerRole =>
      widget.userRole == 'admin' ||
      widget.userRole == 'subadmin' ||
      widget.userRole == 'techincharge';

  bool get _isEmployeeTargetedFlow {
    if (widget.assignMode == CreateTaskAssignMode.employee) {
      return true;
    }
    if (widget.assignMode == null && widget.showAssignToSelector && _assignTo == 'employee') {
      return true;
    }
    return false;
  }

  List<Map<String, String>> get _visibleCategories {
    if (_isEmployeeTargetedFlow) {
      return _categories.where((c) => c['value'] != 'personal').toList();
    }
    return _categories;
  }

  @override
  void initState() {
    super.initState();
    if (widget.assignMode == CreateTaskAssignMode.self) {
      _assignTo = 'self';
    } else if (widget.assignMode == CreateTaskAssignMode.employee &&
        widget.assignedToEmployeeId != null &&
        widget.assignedToEmployeeId!.trim().isNotEmpty) {
      _assignTo = 'employee';
      _selectedEmployeeId = widget.assignedToEmployeeId!.trim();
      if (_selectedCategory == 'personal') {
        _selectedCategory = 'project';
      }
    }
    _subtaskEntries.add(_SubtaskEntry(
      _nextSubtaskId(),
      TextEditingController(),
    ));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _titleFocusNode.requestFocus();
    });
  }

  String _nextSubtaskId() => 'subtask_${DateTime.now().millisecondsSinceEpoch}';

  final List<Map<String, String>> _categories = [
    {'value': 'daily', 'label': 'Daily'},
    {'value': 'project', 'label': 'Project'},
    {'value': 'monthly', 'label': 'Monthly'},
    {'value': 'quarterly', 'label': 'Quarterly'},
    {'value': 'yearly', 'label': 'Yearly'},
    {'value': 'personal', 'label': 'Personal'},
    {'value': 'other', 'label': 'Other'},
  ];

  final List<Map<String, String>> _priorities = [
    {'value': 'low', 'label': 'Low'},
    {'value': 'medium', 'label': 'Medium'},
    {'value': 'high', 'label': 'High'},
    {'value': 'critical', 'label': 'Critical'},
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _titleFocusNode.dispose();
    _descriptionController.dispose();
    for (final e in _subtaskEntries) {
      e.controller.dispose();
    }
    super.dispose();
  }

  void _addSubtask() {
    setState(() {
      _subtaskEntries.add(_SubtaskEntry(
        _nextSubtaskId(),
        TextEditingController(),
      ));
    });
  }

  void _removeSubtask(int index) {
    if (index < 0 || index >= _subtaskEntries.length) return;
    _subtaskEntries[index].controller.dispose();
    setState(() {
      _subtaskEntries.removeAt(index);
    });
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  /// Deadline date from preset or custom picker.
  DateTime? _getDeadlineDate() {
    final now = DateTime.now();
    switch (_deadlinePreset) {
      case 'today':
        return now;
      case '2days':
        return now.add(const Duration(days: 2));
      case '1week':
        return now.add(const Duration(days: 7));
      case 'custom':
        return _selectedDate;
      default:
        return _selectedDate;
    }
  }

  /// Deadline time: for presets use end of day (23:59); for custom use picked time or null.
  String? _getDeadlineTimeString() {
    if (_deadlinePreset == 'custom' && _selectedTime != null) {
      return '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}:00';
    }
    if (_deadlinePreset == 'today' || _deadlinePreset == '2days' || _deadlinePreset == '1week') {
      return '23:59:00'; // end of day for presets
    }
    return null;
  }

  Future<void> _createTask() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final DateTime? deadlineDate = _getDeadlineDate();
      final String? deadlineTimeStr = _getDeadlineTimeString();

      // Server requires assigned_to to be a non-empty string; fallback to self if employee ID missing
      final hasEmployeeId = _selectedEmployeeId != null &&
          _selectedEmployeeId!.trim().isNotEmpty;
      final assignedTo = (_assignTo == 'self' || !hasEmployeeId)
          ? widget.userId
          : _selectedEmployeeId!.trim();

      if (_selectedCategory == 'personal' && assignedTo != widget.userId) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Personal tasks can only be assigned to self.',
              ),
              backgroundColor: Colors.red.shade600,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        setState(() {
          _assignTo = 'self';
          _selectedEmployeeId = null;
        });
        return;
      }

      final subtaskList = _subtaskEntries
          .map((e) => e.controller.text.trim())
          .where((s) => s.isNotEmpty)
          .map((s) => {'text': s, 'status': 'assigned'})
          .toList();

      final taskData = {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'subtasks': subtaskList.isEmpty ? null : subtaskList,
        'category': _selectedCategory,
        'priority': _selectedPriority,
        'deadline_date': deadlineDate?.toIso8601String().split('T')[0],
        'deadline_time': deadlineTimeStr,
        'created_by': widget.userId,
        'user_role': widget.userRole,
        'assigned_to': assignedTo,
      };

      final response = await TaskService.createTask(taskData);

      if (response['status'] == 'success' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Task created successfully'),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context, true);
      } else if (mounted) {
        final message =
            (response['message'] ?? 'Failed to create task').toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage =
            e.toString().replaceFirst('Exception: ', '').trim();

        if (errorMessage.contains('Connection refused')) {
          errorMessage =
              'Cannot connect to server.\n'
              'Please start Laravel backend (php artisan serve).';
        } else if (errorMessage.contains('Validation failed')) {
          errorMessage =
              'Please check the task details.\nSome required fields are missing or invalid.';
        } else if (errorMessage.contains('SQLSTATE')) {
          errorMessage =
              'Server database error while creating task.\nPlease try again or contact support.';
        } else if (errorMessage.isEmpty) {
          errorMessage = 'Unexpected error while creating task.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Create Task'),
        centerTitle: true,
        actions: [
          buildNotepadAppBarAction(
            context,
            userId: widget.userId,
            userRole: widget.userRole,
          ),
          buildCalculatorAppBarAction(context),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    
                       
                        if (isWide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _buildSectionCard(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildSectionTitle('Task Category'),
                                      _buildCategoryButtons(),
                                      if (_isEmployeeTargetedFlow) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          'Personal category is available only for self-assigned tasks.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildSectionCard(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (widget.showAssignToSelector &&
                                          widget.assignMode == null) ...[
                                        _buildSectionTitle('Assign To'),
                                        _buildAssignToSelector(),
                                      ] else ...[
                                        _buildSectionTitle('Assignment'),
                                        Text(
                                          'Assigned automatically based on selected employee context.',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                      if (widget.assignMode ==
                                              CreateTaskAssignMode.employee &&
                                          widget.assignedToEmployeeName != null) ...[
                                        const SizedBox(height: 12),
                                        _buildAssigningToChip(),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        else ...[
                          _buildSectionCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSectionTitle('Task Category'),
                                _buildCategoryButtons(),
                                if (_isEmployeeTargetedFlow) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Personal category is available only for self-assigned tasks.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (widget.showAssignToSelector &&
                              widget.assignMode == null)
                            _buildSectionCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSectionTitle('Assign To'),
                                  _buildAssignToSelector(),
                                ],
                              ),
                            ),
                          if (widget.assignMode == CreateTaskAssignMode.employee &&
                              widget.assignedToEmployeeName != null) ...[
                            const SizedBox(height: 12),
                            _buildAssigningToChip(),
                          ],
                        ],
                        const SizedBox(height: 12),
                        _buildSectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionTitle('Task Title'),
                              _buildTitleField(),
                              const SizedBox(height: 16),
                              _buildSectionTitle('Subtasks'),
                              _buildSubtasksSection(),
                              const SizedBox(height: 16),
                              _buildSectionTitle('Description'),
                              _buildDescriptionField(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (isWide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _buildSectionCard(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildSectionTitle('Priority'),
                                      _buildPrioritySelector(),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildSectionCard(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildSectionTitle('Deadline'),
                                      _buildDeadlinePresetButtons(),
                                      if (_deadlinePreset == 'custom') ...[
                                        const SizedBox(height: 12),
                                        _buildDeadlineSelector(),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        else ...[
                          _buildSectionCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSectionTitle('Priority'),
                                _buildPrioritySelector(),
                                const SizedBox(height: 16),
                                _buildSectionTitle('Deadline'),
                                _buildDeadlinePresetButtons(),
                                if (_deadlinePreset == 'custom') ...[
                                  const SizedBox(height: 12),
                                  _buildDeadlineSelector(),
                                ],
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _buildCreateButton(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  static const Color _gold = Color(0xFFceb56e);

  /// Shared select button style for Category, Priority, and Deadline.
  Widget _buildSelectButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    bool flex = false,
  }) {
    final content = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? _gold.withValues(alpha: 0.25) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? _gold : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: flex ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isSelected)
                const Icon(Icons.check_circle, size: 18, color: _gold),
              if (isSelected) const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? _gold : Colors.grey.shade700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (flex) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: content,
        ),
      );
    }
    return content;
  }

  Widget _buildCategoryButtons() {
    final categories = _visibleCategories;

    if (_selectedCategory == 'personal' &&
        categories.every((c) => c['value'] != 'personal')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selectedCategory = 'project';
        });
      });
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: categories.map((category) {
        final value = category['value']!;
        final label = category['label']!;
        final isSelected = _selectedCategory == value;
        return _buildSelectButton(
          label: label,
          isSelected: isSelected,
          onTap: () {
            setState(() {
              _selectedCategory = value;
              if (_isManagerRole && value == 'personal' && _assignTo == 'employee') {
                _assignTo = 'self';
                _selectedEmployeeId = null;
              }
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildAssignToSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSelectButton(
              label: 'Assign to Self',
              isSelected: _assignTo == 'self',
              onTap: () {
                setState(() {
                  _assignTo = 'self';
                });
              },
              flex: true,
            ),
            _buildSelectButton(
              label: 'Assign to Employee',
              isSelected: _assignTo == 'employee',
              onTap: () {
                if (_selectedCategory == 'personal') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'Personal tasks can only be assigned to self.',
                      ),
                      backgroundColor: Colors.red.shade600,
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                  return;
                }
                setState(() {
                  _assignTo = 'employee';
                  if (_selectedCategory == 'personal') {
                    _selectedCategory = 'project';
                  }
                });
              },
              flex: true,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_assignTo == 'employee' && widget.assignMode == null)
          TextFormField(
            decoration: InputDecoration(
              labelText: 'Employee ID',
              hintText: 'Enter employee user ID',
              prefixIcon: const Icon(Icons.badge_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            validator: (value) {
              if (_assignTo == 'employee' &&
                  (value == null || value.trim().isEmpty)) {
                return 'Please enter employee ID';
              }
              return null;
            },
            onChanged: (value) {
              _selectedEmployeeId = value;
            },
          ),
      ],
    );
  }

  Widget _buildAssigningToChip() {
    final name = widget.assignedToEmployeeName ?? 'Employee';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.person_outline, size: 20, color: _gold),
          const SizedBox(width: 10),
          Text(
            'Assigning to: $name',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleField() {
    return TextFormField(
      controller: _titleController,
      focusNode: _titleFocusNode,
      autofocus: true,
      decoration: InputDecoration(
        hintText: 'Enter task title',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter task title';
        }
        return null;
      },
    );
  }

  Widget _buildDescriptionField() {
    return TextFormField(
      controller: _descriptionController,
      maxLines: 4,
      decoration: InputDecoration(
        hintText: 'Enter task description',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _buildSubtasksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(_subtaskEntries.length, (index) {
          final entry = _subtaskEntries[index];
          final canRemove = _subtaskEntries.length > 1;
          return Padding(
            key: ValueKey(entry.id),
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Checkbox(
                    value: false,
                    onChanged: null,
                    activeColor: _gold,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: entry.controller,
                    decoration: InputDecoration(
                      hintText: 'Subtask ${index + 1}',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: canRemove ? () => _removeSubtask(index) : null,
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.remove_circle_outline,
                        size: 24,
                        color: canRemove
                            ? Colors.grey.shade700
                            : Colors.grey.shade400,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _addSubtask,
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              decoration: BoxDecoration(
                border: Border.all(color: _gold),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.add, size: 20, color: _gold),
                    SizedBox(width: 8),
                    Text(
                      'Add subtask',
                      style: TextStyle(
                        color: _gold,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrioritySelector() {
    return Row(
      children: _priorities.map((priority) {
        final value = priority['value']!;
        final label = priority['label']!;
        final isSelected = _selectedPriority == value;
        return _buildSelectButton(
          label: label,
          isSelected: isSelected,
          onTap: () => setState(() => _selectedPriority = value),
          flex: true,
        );
      }).toList(),
    );
  }

  Widget _buildDeadlinePresetButtons() {
    const presets = [
      {'value': 'today', 'label': 'Today'},
      {'value': '2days', 'label': '2 Days'},
      {'value': '1week', 'label': '1 Week'},
      {'value': 'custom', 'label': 'Custom'},
    ];
    return Row(
      children: presets.map((preset) {
        final value = preset['value']!;
        final label = preset['label']!;
        final isSelected = _deadlinePreset == value;
        return _buildSelectButton(
          label: label,
          isSelected: isSelected,
          onTap: () => setState(() => _deadlinePreset = value),
          flex: true,
        );
      }).toList(),
    );
  }

  Widget _buildDeadlineSelector() {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: _selectDate,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    _selectedDate != null
                        ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
                        : 'Select Date',
                    style: TextStyle(
                      color: _selectedDate != null
                          ? Colors.black87
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: _selectTime,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    _selectedTime != null
                        ? '${_selectedTime!.hour}:${_selectedTime!.minute.toString().padLeft(2, '0')}'
                        : 'Select Time',
                    style: TextStyle(
                      color: _selectedTime != null
                          ? Colors.black87
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _createTask,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFceb56e),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Create Task',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}
