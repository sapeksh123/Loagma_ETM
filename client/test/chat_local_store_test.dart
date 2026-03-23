import 'package:flutter_test/flutter_test.dart';

import 'package:client/chat/chat_local_store.dart';
import 'package:client/models/chat_message_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatLocalStore', () {
    test('deduplicates optimistic and server messages by client message id', () async {
      final store = ChatLocalStore.instance;
      final ownerUserId = 'owner-local-store-dedupe';
      final threadId = 'thread-local-store-dedupe';
      final clientMessageId = 'local-owner-local-store-dedupe-1';

      await store.init();

      final optimistic = ChatMessage.optimistic(
        localId: clientMessageId,
        threadId: threadId,
        senderId: ownerUserId,
        senderRole: 'employee',
        body: 'hello',
        senderName: 'You',
      );

      final acknowledged = ChatMessage(
        id: 'server-message-1',
        threadId: threadId,
        senderId: ownerUserId,
        senderRole: 'employee',
        body: 'hello',
        clientMessageId: clientMessageId,
        sortKey: (optimistic.sortKey ?? 0) + 1,
        createdAt: optimistic.createdAt,
        sentAt: optimistic.sentAt,
        status: 'sent',
      );

      await store.upsertMessages(ownerUserId, threadId, [optimistic]);
      await store.upsertMessages(ownerUserId, threadId, [acknowledged]);

      final messages = await store.loadMessages(ownerUserId, threadId, limit: 20);

      expect(messages, hasLength(1));
      expect(messages.single.id, 'server-message-1');
      expect(messages.single.clientMessageId, clientMessageId);
      expect(messages.single.isPending, isFalse);
    });

    test('keeps outbox items removable after retry success', () async {
      final store = ChatLocalStore.instance;
      final ownerUserId = 'owner-local-store-outbox';
      final clientMessageId = 'local-owner-local-store-outbox-1';

      await store.init();

      final pending = ChatMessage.optimistic(
        localId: clientMessageId,
        threadId: 'thread-local-store-outbox',
        senderId: ownerUserId,
        senderRole: 'employee',
        body: 'retry me',
        senderName: 'You',
      );

      await store.upsertOutbox(ownerUserId, pending);
      expect(await store.loadOutbox(ownerUserId), hasLength(1));

      await store.removeOutbox(ownerUserId, clientMessageId);
      expect(await store.loadOutbox(ownerUserId), isEmpty);
    });
  });
}
