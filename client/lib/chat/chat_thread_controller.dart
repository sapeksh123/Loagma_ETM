import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat_message_model.dart';
import '../models/chat_thread_model.dart';
import 'chat_repository.dart';
import 'chat_realtime_client.dart';

class ChatThreadController extends ChangeNotifier {
  ChatThreadController({
    required this.thread,
    required this.userId,
    required this.userRole,
    ChatRepository? repository,
  }) : _repository = repository ?? ChatRepository.instance;

  final ChatRepository _repository;
  final String userId;
  final String userRole;

  ChatThread thread;
  List<ChatMessage> messages = [];
  bool isLoading = true;
  bool isLoadingOlder = false;
  bool isSending = false;
  String? error;
  bool isCounterpartTyping = false;
  bool hasMoreBefore = true;

  StreamSubscription<ChatRealtimeEvent>? _threadEventsSubscription;
  StreamSubscription<ChatRealtimeEvent>? _userEventsSubscription;
  StreamSubscription<String>? _connectionSubscription;
  Timer? _typingDebounce;
  Timer? _typingResetTimer;
  Timer? _receiptDebounce;
  bool _typingSent = false;
  String? _pendingDeliveredMessageId;
  String? _pendingSeenMessageId;

  Future<void> init() async {
    await _repository.connect(userId: userId, userRole: userRole);
    await _repository.subscribeThread(thread.id);
    unawaited(
      _repository
          .setPresence(userId: userId, userRole: userRole, isOnline: true)
          .catchError((_) {}),
    );

    _threadEventsSubscription = _repository
        .eventsForChannel('private-chat.thread.${thread.id}')
        .listen(_handleRealtimeEvent);
    _userEventsSubscription = _repository
        .eventsForChannel('private-chat.user.$userId')
        .listen(_handleUserEvent);
    _connectionSubscription =
        _repository.realtime.connectionStates.listen(_handleConnectionState);

    final cached = await _repository.loadCachedMessages(
      userId: userId,
      threadId: thread.id,
    );
    if (cached.isNotEmpty) {
      messages = _sorted(cached);
      _applyLocalThreadSnapshot(messages.last, unreadCount: 0);
      isLoading = false;
      notifyListeners();
      _queueVisibleReceipts();
    }

    await refreshInitial();
    await _flushOutbox();
  }

  Future<void> refreshInitial() async {
    try {
      final page = await _repository.refreshMessages(
        userId: userId,
        userRole: userRole,
        threadId: thread.id,
        limit: 80,
      );
      hasMoreBefore = page.hasMoreBefore;
      messages = _merge(messages, page.messages);
      if (messages.isNotEmpty) {
        _applyLocalThreadSnapshot(messages.last, unreadCount: 0);
      }
      await _repository.saveMessages(
        userId: userId,
        threadId: thread.id,
        messages: messages,
      );
      error = null;
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '').trim();
      // Keep conversation usable when cache is available and background refresh
      // times out on slower networks.
      if (messages.isEmpty || !message.toLowerCase().contains('timed out')) {
        error = message;
      }
    }
    isLoading = false;
    notifyListeners();
    _queueVisibleReceipts();
  }

  String get headerSubtitle {
    if (isCounterpartTyping) return 'typing...';
    if (thread.counterpartIsOnline) return 'online';
    final lastSeen = thread.counterpartLastSeenAt;
    if (lastSeen == null) return 'secure realtime chat';
    return 'last seen ${_timeLabel(lastSeen)}';
  }

  Future<void> sendMessage(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty) return;

    final localId = 'local-$userId-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = ChatMessage.optimistic(
      localId: localId,
      threadId: thread.id,
      senderId: userId,
      senderRole: userRole,
      body: text,
      senderName: 'You',
    );
    messages = _merge(messages, [optimistic]);
    unawaited(_repository.saveOptimisticMessage(userId, optimistic));
    _applyLocalThreadSnapshot(optimistic);
    notifyListeners();
    _setTypingState(false);

    // Do network delivery in the background so sending always feels instant.
    unawaited(
      _deliverOptimisticMessage(
        localMessageId: localId,
        body: text,
        fallbackMessage: optimistic,
      ),
    );
  }

  Future<void> _deliverOptimisticMessage({
    required String localMessageId,
    required String body,
    required ChatMessage fallbackMessage,
  }) async {
    try {
      final serverMessage = await _sendMessageWithQuickRetry(
        body: body,
        clientMessageId: localMessageId,
      );
      final normalized = serverMessage.copyWith(isPending: false, isFailed: false);
      messages = _replaceByClientMessageId(messages, localMessageId, normalized);
      await _repository.replaceOptimisticMessage(
        userId: userId,
        threadId: thread.id,
        localMessageId: localMessageId,
        message: normalized,
      );
      _applyLocalThreadSnapshot(normalized);
      error = null;
    } catch (e) {
      final failed = fallbackMessage.copyWith(
        status: 'failed',
        isPending: false,
        isFailed: true,
      );
      messages = _replaceByClientMessageId(messages, localMessageId, failed);
      await _repository.markMessageFailed(
        userId: userId,
        threadId: thread.id,
        message: failed,
      );
      error = e.toString().replaceFirst('Exception: ', '').trim();
    }
    notifyListeners();
  }

  Future<void> retryMessage(ChatMessage message) async {
    final body = message.body.trim();
    final clientMessageId = message.clientMessageId ?? message.id;
    final pending = message.copyWith(
      status: 'sending',
      isPending: true,
      isFailed: false,
    );
    messages = _replaceByClientMessageId(messages, clientMessageId, pending);
    await _repository.saveOptimisticMessage(userId, pending);
    notifyListeners();

    try {
      final serverMessage = await _sendMessageWithQuickRetry(
        body: body,
        clientMessageId: clientMessageId,
      );
      final normalized = serverMessage.copyWith(isPending: false, isFailed: false);
      messages = _replaceByClientMessageId(messages, clientMessageId, normalized);
      await _repository.replaceOptimisticMessage(
        userId: userId,
        threadId: thread.id,
        localMessageId: message.id,
        message: normalized,
      );
      _applyLocalThreadSnapshot(normalized);
    } catch (e) {
      final failed = pending.copyWith(
        status: 'failed',
        isPending: false,
        isFailed: true,
      );
      messages = _replaceByClientMessageId(messages, clientMessageId, failed);
      await _repository.markMessageFailed(
        userId: userId,
        threadId: thread.id,
        message: failed,
      );
      error = e.toString().replaceFirst('Exception: ', '').trim();
    }

    notifyListeners();
  }

  Future<ChatMessage> _sendMessageWithQuickRetry({
    required String body,
    required String clientMessageId,
  }) async {
    try {
      return await _repository.sendMessage(
        threadId: thread.id,
        senderId: userId,
        senderRole: userRole,
        body: body,
        clientMessageId: clientMessageId,
      );
    } catch (_) {
      // A short fallback retry keeps the UI responsive while smoothing over
      // transient network hiccups.
      await Future.delayed(const Duration(milliseconds: 350));
      return _repository.sendMessage(
        threadId: thread.id,
        senderId: userId,
        senderRole: userRole,
        body: body,
        clientMessageId: clientMessageId,
      );
    }
  }

  void onComposerChanged(String value) {
    final hasText = value.trim().isNotEmpty;
    _typingDebounce?.cancel();

    if (!hasText) {
      _setTypingState(false);
      return;
    }

    _setTypingState(true);
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      _setTypingState(false);
    });
  }

  Future<void> loadOlderMessages() async {
    if (isLoadingOlder || !hasMoreBefore) return;
    final firstSortKey = messages.isNotEmpty ? messages.first.sortKey : null;
    if (firstSortKey == null) return;

    isLoadingOlder = true;
    notifyListeners();

    try {
      final page = await _repository.refreshMessages(
        userId: userId,
        userRole: userRole,
        threadId: thread.id,
        beforeSortKey: firstSortKey,
        limit: 40,
      );
      hasMoreBefore = page.hasMoreBefore;
      messages = _merge(messages, page.messages);
    } catch (_) {
      // Keep existing UI stable; manual refresh can recover.
    } finally {
      isLoadingOlder = false;
      notifyListeners();
    }
  }

  Future<void> disposeController() async {
    _typingDebounce?.cancel();
    _typingResetTimer?.cancel();
    _receiptDebounce?.cancel();
    _threadEventsSubscription?.cancel();
    _userEventsSubscription?.cancel();
    _connectionSubscription?.cancel();
    await _repository.unsubscribeThread(thread.id);
    unawaited(
      _repository
          .setTyping(
            threadId: thread.id,
            userId: userId,
            userRole: userRole,
            isTyping: false,
          )
          .catchError((_) {}),
    );
  }

  void _handleRealtimeEvent(ChatRealtimeEvent event) {
    switch (event.eventName) {
      case 'message.created':
      case 'message.updated':
        final raw = event.data['message'];
        if (raw is! Map) return;
        final incoming = ChatMessage.fromJson(Map<String, dynamic>.from(raw));
        messages = _merge(messages, [incoming.copyWith(isPending: false, isFailed: false)]);
        unawaited(
          _repository.saveMessages(
            userId: userId,
            threadId: thread.id,
            messages: [incoming],
          ),
        );
        _applyLocalThreadSnapshot(
          incoming,
          unreadCount: incoming.senderId == userId ? thread.unreadCount : 0,
        );
        if (incoming.senderId != userId) {
          _queueVisibleReceipts();
        }
        notifyListeners();
        break;
      case 'receipt.updated':
        _applyReceiptUpdate(event.data);
        unawaited(
          _repository.saveMessages(
            userId: userId,
            threadId: thread.id,
            messages: messages.where((message) => message.senderId == userId).toList(),
          ),
        );
        notifyListeners();
        break;
      case 'typing.updated':
        final actor = event.data['user_id']?.toString();
        if (actor == null || actor == userId) return;
        final isTyping = event.data['is_typing'] == true;
        isCounterpartTyping = isTyping;
        _typingResetTimer?.cancel();
        if (isTyping) {
          _typingResetTimer = Timer(const Duration(seconds: 3), () {
            isCounterpartTyping = false;
            notifyListeners();
          });
        }
        notifyListeners();
        break;
      case 'presence.updated':
        final actor = event.data['user_id']?.toString();
        if (actor != null && actor == thread.counterpartUserId) {
          thread = thread.copyWith(
            counterpartIsOnline: event.data['is_online'] == true,
            counterpartLastSeenAt: ChatMessage.parseApiTime(
              event.data['last_seen_at']?.toString(),
            ),
          );
          notifyListeners();
        }
        break;
    }
  }

  void _handleUserEvent(ChatRealtimeEvent event) {
    if (event.eventName != 'thread.updated') return;
    final raw = event.data['thread'];
    if (raw is! Map) return;

    final incomingThread = ChatThread.fromJson(Map<String, dynamic>.from(raw));
    if (incomingThread.id != thread.id) return;

    thread = incomingThread;
    unawaited(_repository.saveThread(userId, incomingThread));
    notifyListeners();
  }

  void _handleConnectionState(String state) {
    if (!state.toLowerCase().contains('connected')) return;
    unawaited(_syncDeltaSafely());
    unawaited(_flushOutboxSafely());
  }

  Future<void> _syncDeltaSafely() async {
    try {
      await _syncDelta();
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '').trim();
      // Avoid noisy banners for transient background timeout retries.
      if (!message.toLowerCase().contains('timed out')) {
        error = message;
        notifyListeners();
      }
    }
  }

  Future<void> _flushOutboxSafely() async {
    try {
      await _flushOutbox();
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '').trim();
      if (!message.toLowerCase().contains('timed out')) {
        error = message;
        notifyListeners();
      }
    }
  }

  Future<void> _syncDelta() async {
    final afterSortKey = messages.isNotEmpty ? messages.last.sortKey : null;
    final page = await _repository.refreshMessages(
      userId: userId,
      userRole: userRole,
      threadId: thread.id,
      afterSortKey: afterSortKey,
      limit: 80,
    );
    if (page.messages.isEmpty) return;
    messages = _merge(messages, page.messages);
    if (messages.isNotEmpty) {
      _applyLocalThreadSnapshot(messages.last, unreadCount: 0);
    }
    notifyListeners();
    _queueVisibleReceipts();
  }

  Future<void> _flushOutbox() async {
    final items = await _repository.loadOutbox(userId);
    var processed = 0;
    for (final pending in items.where((item) => item.threadId == thread.id)) {
      if (processed >= 3) break;
      if (!pending.isPending && !pending.isFailed) continue;
      await retryMessage(pending);
      processed++;
    }
  }

  void _queueVisibleReceipts() {
    final latestIncoming = messages.where((m) => m.senderId != userId).lastOrNull;
    if (latestIncoming == null) return;

    _pendingDeliveredMessageId = latestIncoming.id;
    _pendingSeenMessageId = latestIncoming.id;
    _receiptDebounce?.cancel();
    _receiptDebounce = Timer(const Duration(milliseconds: 250), () async {
      final delivered = _pendingDeliveredMessageId;
      final seen = _pendingSeenMessageId;
      _pendingDeliveredMessageId = null;
      _pendingSeenMessageId = null;
      if (delivered == null && seen == null) return;
      try {
        await _repository.updateReceipts(
          threadId: thread.id,
          userId: userId,
          userRole: userRole,
          deliveredMessageId: delivered,
          seenMessageId: seen,
        );
        if (thread.unreadCount != 0) {
          thread = thread.copyWith(unreadCount: 0);
          unawaited(_repository.saveThread(userId, thread));
          notifyListeners();
        }
      } catch (_) {
        _pendingDeliveredMessageId = delivered;
        _pendingSeenMessageId = seen;
      }
    });
  }

  void _setTypingState(bool isTyping) {
    if (_typingSent == isTyping) return;
    _typingSent = isTyping;
    unawaited(
      _repository
          .setTyping(
            threadId: thread.id,
            userId: userId,
            userRole: userRole,
            isTyping: isTyping,
          )
          .catchError((_) {}),
    );
  }

  void _applyReceiptUpdate(Map<String, dynamic> data) {
    final deliveredSortKey = data['delivered_sort_key'] != null
        ? int.tryParse(data['delivered_sort_key'].toString())
        : null;
    final seenSortKey = data['seen_sort_key'] != null
        ? int.tryParse(data['seen_sort_key'].toString())
        : null;

    messages = messages.map((message) {
      if (message.senderId != userId) return message;
      final sortKey = message.sortKey ?? 0;
      if (seenSortKey != null && sortKey <= seenSortKey) {
        return message.copyWith(status: 'seen');
      }
      if (deliveredSortKey != null && sortKey <= deliveredSortKey) {
        return message.copyWith(status: 'delivered');
      }
      return message;
    }).toList();
  }

  void _applyLocalThreadSnapshot(ChatMessage message, {int? unreadCount}) {
    final currentSortKey = thread.lastMessageSortKey ?? 0;
    final nextSortKey = message.sortKey ?? currentSortKey;
    if (currentSortKey != 0 && nextSortKey < currentSortKey) {
      return;
    }

    thread = thread.copyWith(
      lastMessageAt: message.createdAt,
      lastMessageBody: message.body,
      lastMessageSenderId: message.senderId,
      lastMessageSortKey: message.sortKey,
      unreadCount: unreadCount ?? thread.unreadCount,
    );
    unawaited(_repository.saveThread(userId, thread));
  }

  static List<ChatMessage> _sorted(List<ChatMessage> items) {
    final next = List<ChatMessage>.from(items);
    next.sort((a, b) => (a.sortKey ?? 0).compareTo(b.sortKey ?? 0));
    return next;
  }

  static List<ChatMessage> _merge(
    List<ChatMessage> current,
    List<ChatMessage> incoming,
  ) {
    final byId = <String, ChatMessage>{for (final item in current) item.id: item};

    for (final item in incoming) {
      final clientMessageId = item.clientMessageId;
      if (clientMessageId != null) {
        final existingLocal = byId.values.where((entry) {
          return entry.clientMessageId == clientMessageId || entry.id == clientMessageId;
        }).toList();
        for (final local in existingLocal) {
          byId.remove(local.id);
        }
      }
      byId[item.id] = item;
    }

    return _sorted(byId.values.toList());
  }

  static List<ChatMessage> _replaceByClientMessageId(
    List<ChatMessage> current,
    String clientMessageId,
    ChatMessage replacement,
  ) {
    final next = current.where((item) {
      return item.id != clientMessageId && item.clientMessageId != clientMessageId;
    }).toList();
    next.add(replacement);
    return _sorted(next);
  }

  String _timeLabel(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

extension _LastOrNull<T> on Iterable<T> {
  T? get lastOrNull {
    if (isEmpty) return null;
    return last;
  }
}
