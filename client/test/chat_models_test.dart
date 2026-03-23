import 'package:flutter_test/flutter_test.dart';

import 'package:client/models/chat_message_model.dart';
import 'package:client/models/chat_thread_model.dart';

void main() {
  group('ChatMessage', () {
    test('optimistic constructor creates sending state', () {
      final message = ChatMessage.optimistic(
        localId: 'local-1',
        threadId: 'thread-1',
        senderId: 'user-1',
        senderRole: 'employee',
        body: 'hello',
        senderName: 'You',
      );

      expect(message.id, 'local-1');
      expect(message.clientMessageId, 'local-1');
      expect(message.status, 'sending');
      expect(message.isPending, isTrue);
      expect(message.isFailed, isFalse);
      expect(message.sortKey, isNotNull);
    });

    test('fromJson derives failed state from status', () {
      final message = ChatMessage.fromJson({
        'id': 'msg-1',
        'thread_id': 'thread-1',
        'sender_id': 'user-1',
        'sender_role': 'employee',
        'body': 'failed body',
        'created_at': DateTime.now().toIso8601String(),
        'status': 'failed',
      });

      expect(message.isFailed, isTrue);
      expect(message.isPending, isFalse);
    });

    test('fromJson treats naive API timestamps as UTC then localizes', () {
      final message = ChatMessage.fromJson({
        'id': 'msg-utc',
        'thread_id': 'thread-1',
        'sender_id': 'user-1',
        'sender_role': 'employee',
        'body': 'utc parse',
        'created_at': '2026-03-22 10:30:00',
      });

      final expected = DateTime.utc(2026, 3, 22, 10, 30).toLocal();
      expect(message.createdAt, expected);
    });

    test('fromStorageJson keeps local timestamps without UTC shifting', () {
      final localCreatedAt = DateTime(2026, 3, 22, 10, 30);
      final source = ChatMessage(
        id: 'msg-local',
        threadId: 'thread-1',
        senderId: 'user-1',
        senderRole: 'employee',
        body: 'local parse',
        createdAt: localCreatedAt,
      );

      final restored = ChatMessage.fromStorageJson(source.toStorageJson());
      expect(restored.createdAt, localCreatedAt);
    });
  });

  group('ChatThread', () {
    test('previewText prefixes own last message', () {
      const thread = ChatThread(
        id: 'thread-1',
        type: 'direct',
        title: 'Alex',
        createdBy: 'user-1',
        unreadCount: 0,
        lastMessageBody: 'Ping',
        lastMessageSenderId: 'user-1',
      );

      expect(thread.previewText('user-1'), 'You: Ping');
    });

    test('previewText falls back when no messages exist', () {
      const directThread = ChatThread(
        id: 'thread-2',
        type: 'direct',
        title: 'Sam',
        createdBy: 'user-1',
        unreadCount: 0,
      );
      const broadcastThread = ChatThread(
        id: 'thread-3',
        type: 'broadcast_all',
        title: 'Announcements',
        createdBy: 'user-1',
        unreadCount: 0,
      );

      expect(directThread.previewText('user-1'), 'Start chatting');
      expect(broadcastThread.previewText('user-1'), 'No messages yet');
    });
  });
}
