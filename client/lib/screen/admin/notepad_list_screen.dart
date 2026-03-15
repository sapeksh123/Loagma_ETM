import 'package:flutter/material.dart';

import '../../models/note_model.dart';
import '../../services/note_service.dart';
import 'notepad_screen.dart';

class NotepadListScreen extends StatefulWidget {
  final String userId;
  final String userRole;
  final String? userName;

  const NotepadListScreen({
    super.key,
    required this.userId,
    required this.userRole,
    this.userName,
  });

  @override
  State<NotepadListScreen> createState() => _NotepadListScreenState();
}

class _NotepadListScreenState extends State<NotepadListScreen> {
  static const _gold = Color(0xFFceb56e);

  List<Note> _notes = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final list = await NoteService.listNotes(widget.userId);
      if (!mounted) return;
      setState(() {
        _notes = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '').trim();
        _isLoading = false;
      });
    }
  }

  /// Group notes by folder_name (empty string as "General").
  Map<String, List<Note>> get _notesByFolder {
    final map = <String, List<Note>>{};
    for (final note in _notes) {
      final folder = note.folderName.trim().isEmpty ? 'General' : note.folderName;
      map.putIfAbsent(folder, () => []).add(note);
    }
    // Sort folders; keep "General" first if present
    final keys = map.keys.toList()..sort((a, b) {
      if (a == 'General') return -1;
      if (b == 'General') return 1;
      return a.compareTo(b);
    });
    return Map.fromEntries(keys.map((k) => MapEntry(k, map[k]!)));
  }

  Future<void> _openAddNoteDialog() async {
    final folderController = TextEditingController();
    final titleController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Add new note'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: folderController,
                  decoration: const InputDecoration(
                    labelText: 'Folder / Category',
                    hintText: 'e.g. Work, Personal',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Note name',
                    hintText: 'Enter note title',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.white,
              ),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (result != true || !mounted) return;

    final folderName = folderController.text.trim().isEmpty
        ? 'General'
        : folderController.text.trim();
    final title = titleController.text.trim().isEmpty
        ? 'Untitled'
        : titleController.text.trim();

    setState(() => _isLoading = true);
    try {
      final note = await NoteService.createNote(
        widget.userId,
        folderName: folderName,
        title: title,
        content: '',
      );
      if (!mounted) return;
      await _loadNotes();
      if (!mounted) return;
      _openNoteDetail(note);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', '').trim(),
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openNoteDetail(Note note) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => NotepadScreen(
          userId: widget.userId,
          userRole: widget.userRole,
          userName: widget.userName,
          noteId: note.id,
          initialNote: note,
        ),
      ),
    ).then((_) => _loadNotes());
  }

  Future<void> _confirmDeleteNote(Note note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Delete note?'),
        content: Text(
          'This will permanently delete "${note.title}".',
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
      await NoteService.deleteNote(widget.userId, note.id);
      if (!mounted) return;
      await _loadNotes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note deleted'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', '').trim(),
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _notes.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: _gold,
          foregroundColor: Colors.white,
          title: const Text('Notepad'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null && _notes.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: _gold,
          foregroundColor: Colors.white,
          title: const Text('Notepad'),
        ),
        body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey.shade600),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadNotes,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      );
    }

    final byFolder = _notesByFolder;

    if (byFolder.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: _gold,
          foregroundColor: Colors.white,
          title: const Text('Notepad'),
        ),
        body: Column(
        children: [
          const SizedBox(height: 24),
          Icon(Icons.note_add_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No notes yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Add a note to get started.',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _openAddNoteDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add note'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ),
        ],
        ),
      );
    }

    return Scaffold(
     
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _openAddNoteDialog,
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add note'),
      ),
      body: RefreshIndicator(
      onRefresh: _loadNotes,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ...byFolder.entries.map((entry) {
            final folderName = entry.key;
            final notes = entry.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 12, bottom: 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 20,
                        color: _gold,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        folderName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFceb56e),
                        ),
                      ),
                    ],
                  ),
                ),
                ...notes.map((note) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () => _openNoteDetail(note),
                        onLongPress: () => _confirmDeleteNote(note),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _gold.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.note_outlined,
                                  size: 22,
                                  color: _gold,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      note.title,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (note.content.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        note.content.trim(),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade600,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: Colors.grey.shade400,
                                size: 22,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            );
          }),
        ],
      ),
    ),
    );
  }
}
