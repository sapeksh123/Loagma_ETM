import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/note_model.dart';
import '../../services/note_service.dart';

class NotepadScreen extends StatefulWidget {
  final String userId;
  final String userRole;
  final String? userName;
  /// When set, this screen acts as note-detail (load/save by id).
  /// When null, legacy single notepad (getMyNote/saveMyNote).
  final String? noteId;
  /// Optional initial note when opening as detail (avoids extra load).
  final Note? initialNote;

  const NotepadScreen({
    super.key,
    required this.userId,
    required this.userRole,
    this.userName,
    this.noteId,
    this.initialNote,
  });

  @override
  State<NotepadScreen> createState() => _NotepadScreenState();
}

class _NotepadScreenState extends State<NotepadScreen> {
  static const _gold = Color(0xFFceb56e);
  static const _saveDebounce = Duration(milliseconds: 500);

  late final TextEditingController _controller;
  Timer? _debounce;
  bool _isLoading = true;
  bool _isSaved = true;
  DateTime? _lastSavedAt;
  String? _noteTitle; // for detail mode app bar

  String get _storageKey => 'notepad:${widget.userRole}:${widget.userId}';

  bool get _isDetailMode => widget.noteId != null && widget.noteId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(_onChanged);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    _isSaved = false;
    _debounce?.cancel();
    _debounce = Timer(_saveDebounce, () {
      _save();
    });
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (_isDetailMode) {
      await _loadDetailNote();
    } else {
      await _loadLegacyNote();
    }
  }

  Future<void> _loadDetailNote() async {
    setState(() => _isLoading = true);
    if (widget.initialNote != null) {
      _controller.text = widget.initialNote!.content;
      _noteTitle = widget.initialNote!.title;
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
      if (mounted) setState(() => _isLoading = false);
    }

    try {
      final note = await NoteService.getNote(widget.userId, widget.noteId!);
      if (!mounted) return;
      _controller.text = note.content;
      _noteTitle = note.title;
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
      setState(() {
        _isLoading = false;
        _isSaved = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadLegacyNote() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();

    final localText = prefs.getString(_storageKey) ?? '';
    _controller.text = localText;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _isSaved = true;
    });

    try {
      final remote = await NoteService.getMyNote(widget.userId);
      if (!mounted) return;
      if (remote.isNotEmpty && remote != _controller.text) {
        _controller.text = remote;
        _controller.selection =
            TextSelection.collapsed(offset: _controller.text.length);
        await prefs.setString(_storageKey, remote);
        setState(() => _isSaved = true);
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    if (_isDetailMode) {
      try {
        await NoteService.updateNote(
          widget.userId,
          widget.noteId!,
          content: _controller.text,
        );
        if (!mounted) return;
        setState(() {
          _isSaved = true;
          _lastSavedAt = DateTime.now();
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _isSaved = false);
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final text = _controller.text;
    await prefs.setString(_storageKey, text);

    try {
      await NoteService.saveMyNote(widget.userId, text);
      if (!mounted) return;
      setState(() {
        _isSaved = true;
        _lastSavedAt = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaved = false);
    }
  }

  Future<void> _deleteNote() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete note?'),
        content: const Text(
          'This note will be permanently deleted.',
        ),
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
    );
    if (ok != true || !mounted) return;
    try {
      await NoteService.deleteNote(widget.userId, widget.noteId!);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '').trim()),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _formatSavedText() {
    if (!_isSaved) return 'Saving...';
    if (_lastSavedAt == null) return 'Saved';
    final t = _lastSavedAt!;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return 'Saved $hh:$mm';
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final titleName = (widget.userName ?? '').trim();
    final subtitle = titleName.isNotEmpty ? titleName : widget.userRole;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isDetailMode)
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          if (!_isDetailMode) const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  _isSaved ? Icons.check_circle : Icons.sync,
                  size: 16,
                  color: _isSaved ? Colors.green : _gold,
                ),
                const SizedBox(width: 8),
                Text(
                  _formatSavedText(),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_controller.text.length} chars',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              expands: true,
              maxLines: null,
              minLines: null,
              keyboardType: TextInputType.multiline,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: 'Write anything here...\nIt auto-saves.',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _gold, width: 2),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
              style: const TextStyle(fontSize: 15, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDetailMode) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F7),
        appBar: AppBar(
          backgroundColor: _gold,
          foregroundColor: Colors.white,
          title: Text(
            _noteTitle ?? 'Note',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteNote,
              tooltip: 'Delete note',
            ),
          ],
        ),
        body: _buildContent(),
      );
    }

    return _buildContent();
  }
}
