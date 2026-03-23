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

  List<ChatThread> threads = [];
  List<ChatUser> users = [];
  bool isLoading = true;
  bool isRefreshing = false;
  String? error;

  StreamSubscription<ChatRealtimeEvent>? _eventsSubscription;

  Future<void> init() async {
    await _repository.connect(userId: userId, userRole: userRole);
    unawaited(_repository.setPresence(userId: userId, userRole: userRole, isOnline: true));

    final cachedThreads = await _repository.loadCachedThreads(userId);
    if (cachedThreads.isNotEmpty) {
      threads = cachedThreads;
      isLoading = false;
      notifyListeners();
    }

    _eventsSubscription = _repository
        .eventsForChannel('private-chat.user.$userId')
        .listen(_handleRealtimeEvent);

    await refresh(initial: true);
  }

  Future<void> refresh({bool initial = false}) async {
    if (initial) {
      isLoading = threads.isEmpty;
    } else {
      isRefreshing = true;
    }
    error = null;
    notifyListeners();

    try {
      threads = await _repository.refreshThreads(userId: userId, userRole: userRole);
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '').trim();
    }

    try {
      users = await _loadUsers();
    } catch (e) {
      error ??= e.toString().replaceFirst('Exception: ', '').trim();
    }

    isLoading = false;
    isRefreshing = false;
    notifyListeners();
  }

  Future<List<ChatUser>> _loadUsers() async {
    return ChatService.getChatUsers(currentUserId: userId);
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
