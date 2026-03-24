import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat_thread_model.dart';
import '../models/chat_user_model.dart';
import '../services/chat_service.dart';
import 'chat_repository.dart';
import 'chat_realtime_client.dart';

class ChatListController extends ChangeNotifier {
  ChatListController({
    required this.userId,
    required this.userRole,
    ChatRepository? repository,
  }) : _repository = repository ?? ChatRepository.instance;

  final String userId;
  final String userRole;
  final ChatRepository _repository;

  static const int _usersPerPage = 30;
  static final Map<String, List<ChatUser>> _cachedUsersByOwner = {};

  List<ChatThread> threads = [];
  List<ChatUser> users = [];
  bool isLoading = true;
  bool isRefreshing = false;
  bool isLoadingMoreUsers = false;
  bool hasMoreUsers = true;
  int _nextUsersPage = 1;
  String? error;

  StreamSubscription<ChatRealtimeEvent>? _eventsSubscription;

  Future<void> init() async {
    final cachedUsers = _cachedUsersByOwner[userId];
    if (cachedUsers != null && cachedUsers.isNotEmpty) {
      users = List<ChatUser>.from(cachedUsers);
      hasMoreUsers = cachedUsers.length >= _usersPerPage;
      _nextUsersPage = 2;
      isLoading = threads.isEmpty && users.isEmpty;
      notifyListeners();
    }

    final cachedThreads = await _repository.loadCachedThreads(userId);
    if (cachedThreads.isNotEmpty) {
      threads = cachedThreads;
      isLoading = false;
      notifyListeners();
    }

    _eventsSubscription = _repository
        .eventsForChannel('private-chat.user.$userId')
        .listen(_handleRealtimeEvent);

    unawaited(_connectRealtime());

    await refresh(initial: true);
  }

  Future<void> _connectRealtime() async {
    try {
      await _repository.connect(userId: userId, userRole: userRole);
      await _repository.setPresence(userId: userId, userRole: userRole, isOnline: true);
    } catch (_) {
      // Realtime failures should not block core chat list loading.
    }
  }

  Future<void> refresh({bool initial = false}) async {
    if (initial) {
      isLoading = threads.isEmpty && users.isEmpty;
    } else {
      isRefreshing = true;
    }
    error = null;
    notifyListeners();

    final threadsFuture = _repository.refreshThreads(userId: userId, userRole: userRole);
    final usersFuture = _loadUsersPage(page: 1);

    try {
      threads = await threadsFuture;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '').trim();
    }

    try {
      final firstPage = await usersFuture;
      users = firstPage;
      _cachedUsersByOwner[userId] = List<ChatUser>.from(firstPage);
      hasMoreUsers = firstPage.length >= _usersPerPage;
      _nextUsersPage = 2;
    } catch (e) {
      error ??= e.toString().replaceFirst('Exception: ', '').trim();
    }

    isLoading = false;
    isRefreshing = false;
    notifyListeners();
  }

  Future<void> loadMoreUsers() async {
    if (isLoading || isRefreshing || isLoadingMoreUsers || !hasMoreUsers) {
      return;
    }

    isLoadingMoreUsers = true;
    notifyListeners();

    try {
      final nextPage = await _loadUsersPage(page: _nextUsersPage);
      final known = users.map((u) => u.id).toSet();
      for (final user in nextPage) {
        if (!known.contains(user.id)) {
          users.add(user);
        }
      }
      hasMoreUsers = nextPage.length >= _usersPerPage;
      if (nextPage.isNotEmpty) {
        _nextUsersPage += 1;
      }
      _cachedUsersByOwner[userId] = List<ChatUser>.from(users.take(_usersPerPage));
    } catch (e) {
      error ??= e.toString().replaceFirst('Exception: ', '').trim();
    } finally {
      isLoadingMoreUsers = false;
      notifyListeners();
    }
  }

  Future<List<ChatUser>> _loadUsersPage({required int page}) async {
    return ChatService.getChatUsers(
      currentUserId: userId,
      perPage: _usersPerPage,
      page: page,
    );
  }

  void _handleRealtimeEvent(ChatRealtimeEvent event) {
    if (event.eventName != 'thread.updated') return;
    final threadJson = event.data['thread'];
    if (threadJson is! Map) return;

    final incoming = ChatThread.fromJson(Map<String, dynamic>.from(threadJson));
    final next = List<ChatThread>.from(threads);
    final index = next.indexWhere((item) => item.id == incoming.id);
    if (index >= 0) {
      next[index] = incoming;
    } else {
      next.add(incoming);
    }
    next.sort((a, b) {
      final aKey = a.lastMessageAt?.millisecondsSinceEpoch ?? 0;
      final bKey = b.lastMessageAt?.millisecondsSinceEpoch ?? 0;
      return bKey.compareTo(aKey);
    });
    threads = next;
    notifyListeners();
    unawaited(_repository.saveThreads(userId, next));
  }

  Future<ChatThread> openDirectThread(ChatUser user) async {
    final thread = await _repository.openDirectThread(
      userId: userId,
      userRole: userRole,
      targetUserId: user.id,
      title: user.name,
    );
    final next = List<ChatThread>.from(threads);
    final index = next.indexWhere((item) => item.id == thread.id);
    if (index >= 0) {
      next[index] = thread;
    } else {
      next.insert(0, thread);
    }
    next.sort((a, b) {
      final aKey = a.lastMessageAt?.millisecondsSinceEpoch ?? 0;
      final bKey = b.lastMessageAt?.millisecondsSinceEpoch ?? 0;
      return bKey.compareTo(aKey);
    });
    threads = next;
    notifyListeners();
    unawaited(_repository.saveThreads(userId, next));
    return thread;
  }

  @override
  void dispose() {
    _eventsSubscription?.cancel();
    super.dispose();
  }
}
