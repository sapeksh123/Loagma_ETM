import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';

class DeveloperSwitchDialog extends StatefulWidget {
  const DeveloperSwitchDialog({super.key});

  static Future<User?> show(BuildContext context) {
    return showDialog<User>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const DeveloperSwitchDialog(),
    );
  }

  @override
  State<DeveloperSwitchDialog> createState() => _DeveloperSwitchDialogState();
}

class _DeveloperSwitchDialogState extends State<DeveloperSwitchDialog> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isSwitching = false;
  String? _error;

  List<User> _users = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final users = await AuthService.getSwitchableUsers();

      if (!mounted) return;
      setState(() {
        _users = users;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '').trim();
        _isLoading = false;
      });
    }
  }

  List<User> get _filteredUsers {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _users;
    return _users.where((u) {
      return u.name.toLowerCase().contains(query) ||
          u.id.toLowerCase().contains(query) ||
          u.phone.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _switchTo(User selectedUser) async {
    if (_isSwitching) return;
    setState(() {
      _isSwitching = true;
      _error = null;
    });

    try {
      final switchedUser = await AuthService.switchSessionContext(
        selectedUser: selectedUser,
        selectedRole: selectedUser.role,
      );

      if (!mounted) return;
      Navigator.of(context).pop(switchedUser);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '').trim();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSwitching = false;
        });
      }
    }
  }

  Future<void> _confirmAndSwitch(User selectedUser) async {
    if (_isSwitching) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: const Text('Switch account?'),
            content: Text(
              'Switch to ${selectedUser.name} (${selectedUser.id}) as ${_roleLabel(selectedUser.role)}?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Switch'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;
    await _switchTo(selectedUser);
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'Admin';
      case 'subadmin':
        return 'Sub Admin';
      case 'techincharge':
        return 'Tech Incharge';
      default:
        return 'Employee';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.developer_mode, color: Color(0xFFceb56e)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Developer Context Switch',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SizedBox(
          height: 430,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search by name, id, or phone',
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Select account to switch instantly',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _filteredUsers.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Text('No users found.'),
                              ),
                            )
                          : ListView.separated(
                              itemCount: _filteredUsers.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1, thickness: 0.6),
                              itemBuilder: (context, index) {
                                final user = _filteredUsers[index];
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: const Color(0xFFceb56e)
                                        .withValues(alpha: 0.2),
                                    child: Text(
                                      user.name.isNotEmpty
                                          ? user.name[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: Color(0xFF8E7A42),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    user.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${user.id} • ${_roleLabel(user.role)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: _isSwitching
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.chevron_right),
                                  onTap: _isSwitching
                                      ? null
                                      : () => _confirmAndSwitch(user),
                                );
                              },
                            ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSwitching
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
