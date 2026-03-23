import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/chat_message_model.dart';
import '../models/chat_thread_model.dart';

class ChatLocalStore {
  ChatLocalStore._();

  static final ChatLocalStore instance = ChatLocalStore._();

  Database? _db;
  bool _useMemoryStore = false;
  final Map<String, List<ChatThread>> _threadMemory = {};
  final Map<String, List<ChatMessage>> _messageMemory = {};
  final Map<String, List<ChatMessage>> _outboxMemory = {};

  List<ChatMessage> _mergeMessages(Iterable<ChatMessage> messages) {
    final byId = <String, ChatMessage>{};

    for (final message in messages) {
      final clientMessageId = message.clientMessageId?.trim();
      if (clientMessageId != null && clientMessageId.isNotEmpty) {
        byId.removeWhere((key, existing) {
          return existing.clientMessageId == clientMessageId || key == clientMessageId;
        });
      }
      byId[message.id] = message;
    }

    final merged = byId.values.toList();
    merged.sort((a, b) => (a.sortKey ?? 0).compareTo(b.sortKey ?? 0));
    return merged;
  }

  Future<void> init() async {
    if (_db != null || _useMemoryStore) return;

    if (kIsWeb || Platform.isWindows || Platform.isLinux) {
      _useMemoryStore = true;
      return;
    }

    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      path.join(dbPath, 'chat_cache.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE threads(
            owner_user_id TEXT NOT NULL,
            thread_id TEXT NOT NULL,
            payload TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY(owner_user_id, thread_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE messages(
            owner_user_id TEXT NOT NULL,
            thread_id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            client_message_id TEXT,
            sort_key INTEGER,
            payload TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY(owner_user_id, thread_id, message_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE outbox(
            owner_user_id TEXT NOT NULL,
            client_message_id TEXT NOT NULL,
            thread_id TEXT NOT NULL,
            payload TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY(owner_user_id, client_message_id)
          )
        ''');
      },
    );
  }

  Future<List<ChatThread>> loadThreads(String ownerUserId) async {
    await init();
    if (_useMemoryStore) {
      return List<ChatThread>.from(_threadMemory[ownerUserId] ?? const []);
    }

    final rows = await _db!.query(
      'threads',
      where: 'owner_user_id = ?',
      whereArgs: [ownerUserId],
      orderBy: 'updated_at DESC',
    );
    return rows
        .map((row) => ChatThread.fromStorageJson(row['payload']!.toString()))
        .toList();
  }

  Future<void> upsertThreads(String ownerUserId, List<ChatThread> threads) async {
    await init();
    if (_useMemoryStore) {
      _threadMemory[ownerUserId] = List<ChatThread>.from(threads);
      return;
    }

    final batch = _db!.batch();
    for (final thread in threads) {
      batch.insert('threads', {
        'owner_user_id': ownerUserId,
        'thread_id': thread.id,
        'payload': thread.toStorageJson(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<ChatMessage>> loadMessages(
    String ownerUserId,
    String threadId, {
    int limit = 80,
  }) async {
    await init();
    final key = '$ownerUserId|$threadId';
    if (_useMemoryStore) {
      final items = _mergeMessages(_messageMemory[key] ?? const <ChatMessage>[]);
      return items.length <= limit ? items : items.sublist(items.length - limit);
    }

    final rows = await _db!.query(
      'messages',
      where: 'owner_user_id = ? AND thread_id = ?',
      whereArgs: [ownerUserId, threadId],
      orderBy: 'sort_key ASC, updated_at ASC',
    );
    final items = rows
        .map((row) => ChatMessage.fromStorageJson(row['payload']!.toString()))
        .toList();
    return items.length <= limit ? items : items.sublist(items.length - limit);
  }

  Future<void> upsertMessages(
    String ownerUserId,
    String threadId,
    List<ChatMessage> messages,
  ) async {
    await init();
    final key = '$ownerUserId|$threadId';
    if (_useMemoryStore) {
      _messageMemory[key] = _mergeMessages([
        ...?_messageMemory[key],
        ...messages,
      ]);
      return;
    }

    final batch = _db!.batch();
    for (final message in messages) {
      final clientMessageId = message.clientMessageId?.trim();
      if (clientMessageId != null && clientMessageId.isNotEmpty) {
        batch.delete(
          'messages',
          where:
              'owner_user_id = ? AND thread_id = ? AND client_message_id = ? AND message_id != ?',
          whereArgs: [ownerUserId, threadId, clientMessageId, message.id],
        );
      }
      batch.insert('messages', {
        'owner_user_id': ownerUserId,
        'thread_id': threadId,
        'message_id': message.id,
        'client_message_id': message.clientMessageId,
        'sort_key': message.sortKey,
        'payload': message.toStorageJson(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> replaceMessage(
    String ownerUserId,
    String threadId,
    String localMessageId,
    ChatMessage message,
  ) async {
    await deleteMessage(ownerUserId, threadId, localMessageId);
    await upsertMessages(ownerUserId, threadId, [message]);
  }

  Future<void> deleteMessage(
    String ownerUserId,
    String threadId,
    String messageId,
  ) async {
    await init();
    final key = '$ownerUserId|$threadId';
    if (_useMemoryStore) {
      _messageMemory[key] = List<ChatMessage>.from(_messageMemory[key] ?? const [])
        ..removeWhere((item) => item.id == messageId);
      return;
    }

    await _db!.delete(
      'messages',
      where: 'owner_user_id = ? AND thread_id = ? AND message_id = ?',
      whereArgs: [ownerUserId, threadId, messageId],
    );
  }

  Future<void> upsertOutbox(String ownerUserId, ChatMessage message) async {
    await init();
    if (message.clientMessageId == null) return;
    if (_useMemoryStore) {
      final items = List<ChatMessage>.from(_outboxMemory[ownerUserId] ?? const []);
      items.removeWhere((item) => item.clientMessageId == message.clientMessageId);
      items.add(message);
      _outboxMemory[ownerUserId] = _mergeMessages(items);
      return;
    }

    await _db!.insert('outbox', {
      'owner_user_id': ownerUserId,
      'client_message_id': message.clientMessageId,
      'thread_id': message.threadId,
      'payload': message.toStorageJson(),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ChatMessage>> loadOutbox(String ownerUserId) async {
    await init();
    if (_useMemoryStore) {
      return List<ChatMessage>.from(_outboxMemory[ownerUserId] ?? const []);
    }

    final rows = await _db!.query(
      'outbox',
      where: 'owner_user_id = ?',
      whereArgs: [ownerUserId],
      orderBy: 'updated_at ASC',
    );
    return rows
        .map((row) => ChatMessage.fromStorageJson(row['payload']!.toString()))
        .toList();
  }

  Future<void> removeOutbox(String ownerUserId, String clientMessageId) async {
    await init();
    if (_useMemoryStore) {
      _outboxMemory[ownerUserId] =
          List<ChatMessage>.from(_outboxMemory[ownerUserId] ?? const [])
            ..removeWhere((item) => item.clientMessageId == clientMessageId);
      return;
    }

    await _db!.delete(
      'outbox',
      where: 'owner_user_id = ? AND client_message_id = ?',
      whereArgs: [ownerUserId, clientMessageId],
    );
  }
}
