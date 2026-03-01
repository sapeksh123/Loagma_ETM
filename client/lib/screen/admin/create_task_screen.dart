import 'package:flutter/material.dart';
import '../../services/task_service.dart';

class CreateTaskScreen extends StatefulWidget {
  final String userId;
  final String userRole;

  const CreateTaskScreen({
    super.key,
    required this.userId,
    required this.userRole,
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

  @override
  void initState() {
    super.initState();
    _subtaskEntries.add(_SubtaskEntry(
      _nextSubtaskId(),
      TextEditingController(),
    ));
  }

  String _nextSubtaskId() => 'subtask_${DateTime.now().millisecondsSinceEpoch}';

  final List<Map<String, String>> _categories = [
    {'value': 'daily', 'label': 'Daily'},
    {'value': 'project', 'label': 'Project'},
    {'value': 'personal', 'label': 'Personal'},
    {'value': 'monthly', 'label': 'Monthly'},
    {'value': 'quarterly', 'label': 'Quarterly'},
    {'value': 'yearly', 'label': 'Yearly'},
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

  /// Builds the combined description string: main description + optional subtasks list.
  String _buildDescriptionForSubmit() {
    final desc = _descriptionController.text.trim();
    final subtaskTexts = _subtaskEntries
        .map((e) => e.controller.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (subtaskTexts.isEmpty) return desc;
    final subtaskBlock = subtaskTexts.map((s) => '• $s').join('\n');
    return desc.isEmpty ? 'Subtasks:\n$subtaskBlock' : '$desc\n\nSubtasks:\n$subtaskBlock';
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

      final taskData = {
        'title': _titleController.text.trim(),
        'description': _buildDescriptionForSubmit(),
        'category': _selectedCategory,
        'priority': _selectedPriority,
        'deadline_date': deadlineDate?.toIso8601String().split('T')[0],
        'deadline_time': deadlineTimeStr,
        'created_by': widget.userId,
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text('Create Task'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 20,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionTitle('Task Category'),
                        _buildCategoryButtons(),
                        const SizedBox(height: 20),
                        if (widget.userRole == 'admin' &&
                            _selectedCategory == 'project') ...[
                          _buildSectionTitle('Assign To'),
                          _buildAssignToSelector(),
                          const SizedBox(height: 20),
                        ],
                        _buildSectionTitle('Task Title'),
                        _buildTitleField(),
                        const SizedBox(height: 20),
                        _buildSectionTitle('Subtasks'),
                        _buildSubtasksSection(),
                        const SizedBox(height: 20),
                        _buildSectionTitle('Description'),
                        _buildDescriptionField(),
                        const SizedBox(height: 20),
                        _buildSectionTitle('Priority'),
                        _buildPrioritySelector(),
                        const SizedBox(height: 20),
                        _buildSectionTitle('Deadline'),
                        _buildDeadlinePresetButtons(),
                        if (_deadlinePreset == 'custom') ...[
                          const SizedBox(height: 12),
                          _buildDeadlineSelector(),
                        ],
                        const SizedBox(height: 24),
                        _buildCreateButton(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _categories.map((category) {
        final value = category['value']!;
        final label = category['label']!;
        final isSelected = _selectedCategory == value;
        return _buildSelectButton(
          label: label,
          isSelected: isSelected,
          onTap: () => setState(() => _selectedCategory = value),
        );
      }).toList(),
    );
  }

  Widget _buildAssignToSelector() {
    return Column(
      children: [
        RadioListTile<String>(
          title: const Text('Assign to Self'),
          value: 'self',
          groupValue: _assignTo,
          onChanged: (value) {
            setState(() {
              _assignTo = value!;
            });
          },
          activeColor: const Color(0xFFceb56e),
        ),
        RadioListTile<String>(
          title: const Text('Assign to Employee'),
          value: 'employee',
          groupValue: _assignTo,
          onChanged: (value) {
            setState(() {
              _assignTo = value!;
            });
          },
          activeColor: const Color(0xFFceb56e),
        ),
        if (_assignTo == 'employee')
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8),
            child: TextFormField(
              decoration: InputDecoration(
                labelText: 'Employee ID',
                hintText: 'Enter employee user ID',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              validator: (value) {
                if (_assignTo == 'employee' &&
                    (value == null || value.isEmpty)) {
                  return 'Please enter employee ID';
                }
                return null;
              },
              onChanged: (value) {
                _selectedEmployeeId = value;
              },
            ),
          ),
      ],
    );
  }

  Widget _buildTitleField() {
    return TextFormField(
      controller: _titleController,
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
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _createTask,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFceb56e),
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
