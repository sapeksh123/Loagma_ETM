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

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _selectedCategory = 'project';
  String _selectedPriority = 'medium';
  String _assignTo = 'self';
  String? _selectedEmployeeId;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isLoading = false;

  final List<Map<String, String>> _categories = [
    {'value': 'daily', 'label': 'Daily Task'},
    {'value': 'project', 'label': 'Project Task'},
    {'value': 'personal', 'label': 'Personal Task'},
    {'value': 'family', 'label': 'Family Task'},
    {'value': 'other', 'label': 'Other Task'},
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
    super.dispose();
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

  Future<void> _createTask() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final taskData = {
        'title': _titleController.text,
        'description': _descriptionController.text,
        'category': _selectedCategory,
        'priority': _selectedPriority,
        'deadline_date': _selectedDate?.toIso8601String().split('T')[0],
        'deadline_time': _selectedTime != null
            ? '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}:00'
            : null,
        'created_by': widget.userId,
        'assigned_to': _assignTo == 'self'
            ? widget.userId
            : _selectedEmployeeId,
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
                        Text(
                          'New Task',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Fill in the details to create a task.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 20),
                        _buildSectionTitle('Task Category'),
                        _buildCategoryDropdown(),
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
                        _buildSectionTitle('Description / Subtask'),
                        _buildDescriptionField(),
                        const SizedBox(height: 20),
                        _buildSectionTitle('Priority'),
                        _buildPrioritySelector(),
                        const SizedBox(height: 20),
                        _buildSectionTitle('Deadline'),
                        _buildDeadlineSelector(),
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

  Widget _buildCategoryDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCategory,
          isExpanded: true,
          items: _categories.map((category) {
            return DropdownMenuItem(
              value: category['value'],
              child: Text(category['label']!),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedCategory = value!;
            });
          },
        ),
      ),
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
        hintText: 'Enter task description or subtasks',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _buildPrioritySelector() {
    return Wrap(
      spacing: 8,
      children: _priorities.map((priority) {
        final isSelected = _selectedPriority == priority['value'];
        return ChoiceChip(
          label: Text(priority['label']!),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              _selectedPriority = priority['value']!;
            });
          },
          selectedColor: const Color(0xFFceb56e).withValues(alpha: 0.3),
          backgroundColor: Colors.white,
          labelStyle: TextStyle(
            color: isSelected ? const Color(0xFFceb56e) : Colors.grey.shade700,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
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
              padding: const EdgeInsets.all(16),
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
