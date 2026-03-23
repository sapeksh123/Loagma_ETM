import '../models/chat_message_model.dart';
import '../models/chat_thread_model.dart';
import '../services/chat_service.dart';
import 'chat_local_store.dart';
import 'chat_realtime_client.dart';

class ChatRepository {
  ChatRepository._();

  static final ChatRepository instance = ChatRepository._();

  final ChatLocalStore _store = ChatLocalStore.instance;
  final ChatRealtimeClient realtime = ChatRealtimeClient.instance;

  Future<void> connect({
    required String userId,
    required String userRole,
  }) async {
    await _store.init();
    await realtime.connect(userId: userId, userRole: userRole);
    await realtime.subscribeUserChannel(userId);
  }

  Future<void> setPresence({
    required String userId,
    required String userRole,
    required bool isOnline,
  }) {
    return ChatService.setPresence(
      userId: userId,
      userRole: userRole,
      isOnline: isOnline,
    );
  }

  Future<List<ChatThread>> loadCachedThreads(String userId) {
    return _store.loadThreads(userId);
  }

  Future<List<ChatThread>> refreshThreads({
    required String userId,
    required String userRole,
  }) async {
    final threads = await ChatService.getThreads(userId: userId, role: userRole);
    await _store.upsertThreads(userId, threads);
    return threads;
  }

  Future<List<ChatMessage>> loadCachedMessages({
    required String userId,
    required String threadId,
    int limit = 80,
  }) {
    return _store.loadMessages(userId, threadId, limit: limit);
  }

  Future<ChatMessagesPage> refreshMessages({
    required String userId,
    required String userRole,
    required String threadId,
    int? afterSortKey,
    int? beforeSortKey,
    int limit = 80,
  }) async {
    final page = await ChatService.getMessages(
      threadId: threadId,
      userId: userId,
      userRole: userRole,
      afterSortKey: afterSortKey,
      beforeSortKey: beforeSortKey,
      limit: limit,
    );
    await _store.upsertMessages(userId, threadId, page.messages);
    return page;
  }

  Future<void> saveThreads(String userId, List<ChatThread> threads) {
    return _store.upsertThreads(userId, threads);
  }

  Future<void> saveThread(String userId, ChatThread thread) {
    return _store.upsertThreads(userId, [thread]);
  }

  Future<void> saveMessages({
    required String userId,
    required String threadId,
    required List<ChatMessage> messages,
  }) {
    return _store.upsertMessages(userId, threadId, messages);
  }

  Future<void> saveOptimisticMessage(String userId, ChatMessage message) async {
    await _store.upsertMessages(userId, message.threadId, [message]);
    await _store.upsertOutbox(userId, message);
  }

  Future<void> replaceOptimisticMessage({
    required String userId,
    required String threadId,
    required String localMessageId,
    required ChatMessage message,
  }) async {
    await _store.replaceMessage(userId, threadId, localMessageId, message);
    if (message.clientMessageId != null) {
      await _store.removeOutbox(userId, message.clientMessageId!);
    }
  }

  Future<void> markMessageFailed({
    required String userId,
    required String threadId,
    required ChatMessage message,
  }) async {
    final failed = message.copyWith(status: 'failed', isPending: false, isFailed: true);
    await _store.upsertMessages(userId, threadId, [failed]);
    await _store.upsertOutbox(userId, failed);
  }

  Future<List<ChatMessage>> loadOutbox(String userId) {
    return _store.loadOutbox(userId);
  }

  Future<void> removeOutbox(String userId, String clientMessageId) {
    return _store.removeOutbox(userId, clientMessageId);
  }

  Future<ChatMessage> sendMessage({
    required String threadId,
    required String senderId,
    required String senderRole,
    required String body,
    required String clientMessageId,
  }) {
    return ChatService.sendMessage(
      threadId: threadId,
      senderId: senderId,
      senderRole: senderRole,
      body: body,
      clientMessageId: clientMessageId,
    );
  }

  Future<void> updateReceipts({
    required String threadId,
    required String userId,
    required String userRole,
    String? deliveredMessageId,
    String? seenMessageId,
  }) {
    return ChatService.updateReceipts(
      threadId: threadId,
      userId: userId,
      userRole: userRole,
      deliveredMessageId: deliveredMessageId,
      seenMessageId: seenMessageId,
    );
  }

  Future<void> setTyping({
    required String threadId,
    required String userId,
    required String userRole,
    required bool isTyping,
  }) {
    return ChatService.setTyping(
      threadId: threadId,
      userId: userId,
      userRole: userRole,
      isTyping: isTyping,
    );
  }

  Future<ChatThread> openDirectThread({
    required String userId,
    required String userRole,
    required String targetUserId,
    required String title,
  }) async {
    final thread = await ChatService.openDirectThread(
      userAId: userId,
      userBId: targetUserId,
      userRole: userRole,
      title: title,
    );
    await saveThread(userId, thread);
    return thread;
  }

  Stream<ChatRealtimeEvent> eventsForChannel(String channelName) {
    return realtime.events.where((event) => event.channelName == channelName);
  }

  Future<void> subscribeThread(String threadId) {
    return realtime.subscribeThreadChannel(threadId);
  }

  Future<void> unsubscribeThread(String threadId) {
    return realtime.unsubscribeThreadChannel(threadId);
  }
}
