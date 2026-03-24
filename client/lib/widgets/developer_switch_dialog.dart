import 'dart:async';

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
  static List<User> _cachedFirstPage = [];

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isPageLoading = false;
  bool _isSwitching = false;
  bool _hasMore = true;
  String? _error;

  static const int _perPage = 25;
  int _nextPage = 1;
  String _activeQuery = '';
  Timer? _searchDebounce;

  List<User> _users = [];

  @override
  void initState() {
    super.initState();
    if (_cachedFirstPage.isNotEmpty) {
      _users = List<User>.from(_cachedFirstPage);
      _isLoading = false;
      _nextPage = 2;
      _hasMore = _cachedFirstPage.length >= _perPage;
    }
    _scrollController.addListener(_onScroll);
    _loadFirstPage(showSpinner: _users.isEmpty);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 160) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    } else {
      setState(() {
        _error = null;
      });
    }

    try {
      final users = await AuthService.getSwitchableUsers(
        page: 1,
        perPage: _perPage,
        search: _activeQuery,
      );

      if (!mounted) return;
      setState(() {
        _users = users;
        _nextPage = 2;
        _hasMore = users.length >= _perPage;
        _isLoading = false;
      });
      if (_activeQuery.isEmpty) {
        _cachedFirstPage = List<User>.from(users);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '').trim();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isPageLoading || !_hasMore) return;

    setState(() {
      _isPageLoading = true;
      _error = null;
    });

    try {
      final users = await AuthService.getSwitchableUsers(
        page: _nextPage,
        perPage: _perPage,
        search: _activeQuery,
      );
      if (!mounted) return;
      setState(() {
        final known = _users.map((u) => u.id).toSet();
        for (final u in users) {
          if (!known.contains(u.id)) {
            _users.add(u);
          }
        }
        _nextPage += 1;
        _hasMore = users.length >= _perPage;
        _isPageLoading = false;
      });
      if (_activeQuery.isEmpty && _cachedFirstPage.isEmpty && _users.isNotEmpty) {
        _cachedFirstPage = List<User>.from(_users.take(_perPage));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '').trim();
        _isPageLoading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      final next = value.trim();
      if (next == _activeQuery) return;
      _activeQuery = next;
      _loadFirstPage(showSpinner: _users.isEmpty);
    });
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
                      onChanged: (value) {
                        setState(() {});
                        _onSearchChanged(value);
                      },
                      decoration: InputDecoration(
                        hintText: 'Search by name, id, or phone',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearchChanged('');
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close),
                              )
                            : null,
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
                      child: _users.isEmpty && !_isLoading
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Text('No users found.'),
                              ),
                            )
                          : ListView.separated(
                              controller: _scrollController,
                              itemCount: _users.length + (_hasMore || _isPageLoading ? 1 : 0),
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1, thickness: 0.6),
                              itemBuilder: (context, index) {
                                if (index >= _users.length) {
                                  if (_isPageLoading) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 12),
                                      child: Center(
                                        child: SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      ),
                                    );
                                  }
                                  if (_hasMore) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 12),
                                      child: Center(
                                        child: Text(
                                          'Scroll to load more',
                                          style: TextStyle(fontSize: 12, color: Colors.black54),
                                        ),
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                }

                                final user = _users[index];
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
