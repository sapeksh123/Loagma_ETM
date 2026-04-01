import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/note_model.dart';
import '../../services/note_service.dart';
import '../../widgets/calculator_app_bar_action.dart';
import '../../widgets/notepad_app_bar_action.dart';
import 'notepad_screen.dart';

class NotepadListScreen extends StatefulWidget {
  final String userId;
  final String userRole;
  final String? userName;
  final bool showAppBar;
  final bool showNotepadAction;
  final bool autoOpenLastOpenedNote;

  const NotepadListScreen({
    super.key,
    required this.userId,
    required this.userRole,
    this.userName,
    this.showAppBar = false,
    this.showNotepadAction = true,
    this.autoOpenLastOpenedNote = true,
  });

  @override
  State<NotepadListScreen> createState() => _NotepadListScreenState();
}

class _NotepadListScreenState extends State<NotepadListScreen> {
  static const _gold = Color(0xFFceb56e);
  static const _pageBg = Color(0xFFF4F1EA);

  List<Note> _notes = [];
  final Map<String, bool> _expandedFolders = {};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.autoOpenLastOpenedNote) {
      _checkAndOpenLastNote();
    } else {
      _loadNotes();
    }
  }

  Future<void> _checkAndOpenLastNote() async {
    final prefs = await SharedPreferences.getInstance();
    final lastNoteId = prefs.getString(_lastNoteKey());
    if (lastNoteId != null && lastNoteId.isNotEmpty) {
      // Try to find the note in the list after loading
      await _loadNotes();
      Note? note;
      try {
        note = _notes.firstWhere((n) => n.id == lastNoteId);
      } catch (_) {
        note = null;
      }
      if (note != null) {
        await _openNoteDetail(note);
      }
      // Clear the last note key so it doesn't auto-open again
      await prefs.remove(_lastNoteKey());
    } else {
      await _loadNotes();
    }
  }

  Future<void> _loadNotes({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final list = await NoteService.listNotes(
        widget.userId,
        widget.userRole,
        forceRefresh: forceRefresh,
      );
      final grouped = _groupNotesByFolder(list);
      if (!mounted) return;
      setState(() {
        _notes = list;
        _syncExpandedFolders(grouped);
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

  Map<String, List<Note>> _groupNotesByFolder(List<Note> notes) {
    final map = <String, List<Note>>{};
    for (final note in notes) {
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

  Map<String, List<Note>> get _notesByFolder => _groupNotesByFolder(_notes);

  List<String> get _existingFolders => _notesByFolder.keys.toList();

  void _syncExpandedFolders(Map<String, List<Note>> grouped) {
    final folders = grouped.keys.toSet();
    for (final folder in folders) {
      _expandedFolders.putIfAbsent(folder, () => true);
    }
    final stale = _expandedFolders.keys.where((k) => !folders.contains(k)).toList();
    for (final key in stale) {
      _expandedFolders.remove(key);
    }
  }

  Future<void> _openAddNoteDialog({
    String? initialFolder,
    bool lockFolder = false,
  }) async {
    final availableFolders = _existingFolders;
    final bootstrapMode = availableFolders.isEmpty;
    final canCreateFolder = !lockFolder;

    String selectedFolder;
    if (bootstrapMode) {
      selectedFolder = 'General';
    } else if (initialFolder != null && availableFolders.contains(initialFolder)) {
      selectedFolder = initialFolder;
    } else {
      selectedFolder = availableFolders.first;
    }

    final titleController = TextEditingController();
    final newFolderController = TextEditingController();
    String folderNameToCreate = selectedFolder;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        String? localError;
        bool createNewFolder = false;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('Create note'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (bootstrapMode)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _gold.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _gold.withValues(alpha: 0.35)),
                        ),
                        child: const Text(
                          'Creating your first note in General folder.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    if (canCreateFolder)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: createNewFolder,
                          title: const Text('Create new folder'),
                          dense: true,
                          onChanged: (value) {
                            setModalState(() {
                              createNewFolder = value;
                              localError = null;
                            });
                          },
                        ),
                      ),
                    if (!createNewFolder)
                      DropdownButtonFormField<String>(
                        value: selectedFolder,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Folder',
                          border: OutlineInputBorder(),
                        ),
                        items: (bootstrapMode ? ['General'] : availableFolders)
                            .map(
                              (folder) => DropdownMenuItem<String>(
                                value: folder,
                                child: Text(
                                  folder,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (lockFolder || bootstrapMode)
                            ? null
                            : (value) {
                                if (value == null) return;
                                setModalState(() {
                                  selectedFolder = value;
                                });
                              },
                      ),
                    if (createNewFolder)
                      TextField(
                        controller: newFolderController,
                        decoration: const InputDecoration(
                          labelText: 'New folder name',
                          hintText: 'Enter folder name',
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
                    if (localError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        localError!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final title = titleController.text.trim();
                    if (title.isEmpty) {
                      setModalState(() {
                        localError = 'Note name is required.';
                      });
                      return;
                    }

                    if (createNewFolder) {
                      final newFolder = newFolderController.text.trim();
                      if (newFolder.isEmpty) {
                        setModalState(() {
                          localError = 'Folder name is required.';
                        });
                        return;
                      }
                      final existingIndex = availableFolders.indexWhere(
                        (f) => f.toLowerCase() == newFolder.toLowerCase(),
                      );
                      folderNameToCreate = existingIndex >= 0
                          ? availableFolders[existingIndex]
                          : newFolder;
                    } else {
                      if (!bootstrapMode && !availableFolders.contains(selectedFolder)) {
                        setModalState(() {
                          localError = 'Please select an existing folder.';
                        });
                        return;
                      }
                      folderNameToCreate = selectedFolder;
                    }

                    Navigator.pop(ctx, true);
                  },
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
      },
    );

    if (result != true || !mounted) return;

    final title = titleController.text.trim();
    setState(() => _isLoading = true);
    try {
      final note = await NoteService.createNote(
        widget.userId,
        userRole: widget.userRole,
        folderName: folderNameToCreate,
        title: title,
        content: '',
      );
      if (!mounted) return;
      NoteService.invalidateNotesCache(widget.userId, widget.userRole);
      await _loadNotes(forceRefresh: true);
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

  Future<void> _openNoteDetail(Note note) async {
    // Save last opened note ID
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastNoteKey(), note.id);
    await Navigator.push(
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
    );
    _loadNotes(forceRefresh: true);
  }

  String _lastNoteKey() => 'notepad:last_opened:${widget.userId}:${widget.userRole}';

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
      await NoteService.deleteNote(widget.userId, widget.userRole, note.id);
      if (!mounted) return;
      NoteService.invalidateNotesCache(widget.userId, widget.userRole);
      await _loadNotes(forceRefresh: true);
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
    final appBar = widget.showAppBar
        ? AppBar(
            backgroundColor: _gold,
            foregroundColor: Colors.white,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            title: const Text('Notepad'),
            actions: [
              if (widget.showNotepadAction)
                buildNotepadAppBarAction(
                  context,
                  userId: widget.userId,
                  userRole: widget.userRole,
                  userName: widget.userName,
                ),
              buildCalculatorAppBarAction(context),
            ],
          )
        : null;

    if (_isLoading && _notes.isEmpty) {
      return Scaffold(
        appBar: appBar,
        backgroundColor: _pageBg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null && _notes.isEmpty) {
      return Scaffold(
        appBar: appBar,
        backgroundColor: _pageBg,
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
        appBar: appBar,
        backgroundColor: _pageBg,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _isLoading ? null : _openAddNoteDialog,
          backgroundColor: _gold,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('Add note'),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                Text(
                  'Add a note to get started.',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      backgroundColor: _pageBg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _openAddNoteDialog,
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add note'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: RefreshIndicator(
      color: _gold,
      onRefresh: () => _loadNotes(forceRefresh: true),
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
            final isExpanded = _expandedFolders[folderName] ?? true;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      _expandedFolders[folderName] = !isExpanded;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, top: 12, bottom: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder_outlined,
                          size: 20,
                          color: _gold,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            folderName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFceb56e),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _gold.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${notes.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF8E7A42),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Add note to $folderName',
                          onPressed: _isLoading
                              ? null
                              : () => _openAddNoteDialog(
                                    initialFolder: folderName,
                                    lockFolder: true,
                                  ),
                          icon: const Icon(Icons.add_circle_outline),
                          color: _gold,
                        ),
                        Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          color: Colors.grey.shade700,
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 180),
                  crossFadeState: isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox.shrink(),
                  secondChild: Column(
                    children: notes.map((note) {
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
                    }).toList(),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    ),
    );
  }
}
