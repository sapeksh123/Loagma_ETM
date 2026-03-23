<?php

namespace Tests\Feature;

use App\Events\ChatThreadEvent;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Str;
use Tests\TestCase;

class ChatRealtimeTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        Config::set('broadcasting.connections.reverb.key', 'test-key');
        Config::set('broadcasting.connections.reverb.secret', 'test-secret');

        $this->createChatTestSchema();
        $this->seedUsers();
    }

    public function test_send_message_is_idempotent_by_client_message_id_and_broadcasts_created_event(): void
    {
        Event::fake([ChatThreadEvent::class]);

        $threadId = $this->seedDirectThread('admin-1', 'employee-1');

        $headers = $this->chatHeaders('admin-1', 'admin');
        $payload = [
            'body' => 'Hello from the realtime path',
            'client_message_id' => 'client-msg-1',
        ];

        $first = $this->postJson("/api/chat/threads/{$threadId}/messages", $payload, $headers);
        $first->assertCreated()
            ->assertJsonPath('data.client_message_id', 'client-msg-1')
            ->assertJsonPath('data.status', 'sent');

        $messageId = $first->json('data.id');
        $messageCountAfterFirstSend = DB::table('chat_messages')->count();

        $second = $this->postJson("/api/chat/threads/{$threadId}/messages", $payload, $headers);
        $second->assertCreated()
            ->assertJsonPath('data.id', $messageId);

        $this->assertSame($messageCountAfterFirstSend, DB::table('chat_messages')->count());

        Event::assertDispatched(ChatThreadEvent::class, function (ChatThreadEvent $event) use ($threadId, $messageId) {
            return $event->eventName === 'message.created'
                && $event->channels === ["chat.thread.{$threadId}"]
                && ($event->payload['message']['id'] ?? null) === $messageId;
        });
    }

    public function test_update_receipts_advances_direct_chat_cursor_and_marks_sender_message_seen(): void
    {
        Event::fake([ChatThreadEvent::class]);

        $threadId = $this->seedDirectThread('admin-1', 'employee-1');
        $firstMessageId = $this->seedMessage($threadId, 'admin-1', 'admin', 'First', 1000);
        $secondMessageId = $this->seedMessage($threadId, 'admin-1', 'admin', 'Second', 2000);

        DB::table('chat_participants')
            ->where('thread_id', $threadId)
            ->where('user_id', 'employee-1')
            ->update(['unread_count' => 2]);

        $response = $this->postJson(
            "/api/chat/threads/{$threadId}/receipts",
            [
                'delivered_message_id' => $firstMessageId,
                'seen_message_id' => $secondMessageId,
            ],
            $this->chatHeaders('employee-1', 'employee')
        );

        $response->assertOk()
            ->assertJsonPath('data.by_user_id', 'employee-1')
            ->assertJsonPath('data.delivered_message_id', $secondMessageId)
            ->assertJsonPath('data.seen_message_id', $secondMessageId)
            ->assertJsonPath('data.delivered_sort_key', 2000)
            ->assertJsonPath('data.seen_sort_key', 2000);

        $participant = DB::table('chat_participants')
            ->where('thread_id', $threadId)
            ->where('user_id', 'employee-1')
            ->first();

        $this->assertSame($secondMessageId, $participant->last_delivered_message_id);
        $this->assertSame($secondMessageId, $participant->last_read_message_id);
        $this->assertSame(0, (int) $participant->unread_count);

        $message = DB::table('chat_messages')->where('id', $secondMessageId)->first();
        $this->assertNotNull($message->delivered_at);
        $this->assertNotNull($message->seen_at);

        Event::assertDispatched(ChatThreadEvent::class, function (ChatThreadEvent $event) use ($threadId, $secondMessageId) {
            return $event->eventName === 'receipt.updated'
                && $event->channels === ["chat.thread.{$threadId}"]
                && ($event->payload['seen_message_id'] ?? null) === $secondMessageId;
        });
    }

    public function test_realtime_auth_rejects_user_who_is_not_a_thread_participant(): void
    {
        $threadId = $this->seedDirectThread('admin-1', 'employee-1');

        $response = $this->postJson(
            '/api/chat/realtime/auth',
            [
                'socket_id' => '1234.5678',
                'channel_name' => "private-chat.thread.{$threadId}",
            ],
            $this->chatHeaders('stranger-1', 'employee')
        );

        $response->assertForbidden()
            ->assertJsonPath('message', 'Not authorized for requested realtime channel');
    }

    public function test_list_messages_supports_before_and_after_sort_key_cursor_sync(): void
    {
        $threadId = $this->seedDirectThread('admin-1', 'employee-1');
        $firstMessageId = $this->seedMessage($threadId, 'admin-1', 'admin', 'One', 1000);
        $secondMessageId = $this->seedMessage($threadId, 'employee-1', 'employee', 'Two', 2000);
        $thirdMessageId = $this->seedMessage($threadId, 'admin-1', 'admin', 'Three', 3000);

        $afterResponse = $this->getJson(
            "/api/chat/threads/{$threadId}/messages?after_sort_key=1000&limit=10",
            $this->chatHeaders('admin-1', 'admin')
        );

        $afterResponse->assertOk()
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('data.0.id', $secondMessageId)
            ->assertJsonPath('data.1.id', $thirdMessageId)
            ->assertJsonPath('meta.cursor.first_sort_key', 2000)
            ->assertJsonPath('meta.cursor.last_sort_key', 3000);

        $beforeResponse = $this->getJson(
            "/api/chat/threads/{$threadId}/messages?before_sort_key=3000&limit=10",
            $this->chatHeaders('admin-1', 'admin')
        );

        $beforeResponse->assertOk()
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('data.0.id', $firstMessageId)
            ->assertJsonPath('data.1.id', $secondMessageId)
            ->assertJsonPath('meta.cursor.first_sort_key', 1000)
            ->assertJsonPath('meta.cursor.last_sort_key', 2000);
    }

    private function createChatTestSchema(): void
    {
        DB::statement('PRAGMA foreign_keys = OFF');
        DB::statement('DROP TABLE IF EXISTS user_presences');
        DB::statement('DROP TABLE IF EXISTS chat_message_reactions');
        DB::statement('DROP TABLE IF EXISTS chat_participants');
        DB::statement('DROP TABLE IF EXISTS chat_messages');
        DB::statement('DROP TABLE IF EXISTS chat_threads');
        DB::statement('DROP TABLE IF EXISTS users');

        DB::statement('
            CREATE TABLE users (
                id TEXT PRIMARY KEY,
                name TEXT,
                email TEXT NULL,
                contactNumber TEXT NULL,
                roles TEXT NULL
            )
        ');

        DB::statement('
            CREATE TABLE chat_threads (
                id TEXT PRIMARY KEY,
                type TEXT NOT NULL,
                created_by TEXT NOT NULL,
                target_user_id TEXT NULL,
                target_role TEXT NULL,
                title TEXT NOT NULL,
                last_message_at TEXT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ');

        DB::statement('
            CREATE TABLE chat_messages (
                id TEXT PRIMARY KEY,
                thread_id TEXT NOT NULL,
                sender_id TEXT NOT NULL,
                sender_role TEXT NOT NULL,
                body TEXT NOT NULL,
                task_id TEXT NULL,
                subtask_index INTEGER NULL,
                client_message_id TEXT NULL,
                sort_key INTEGER NOT NULL,
                sent_at TEXT NULL,
                delivered_at TEXT NULL,
                seen_at TEXT NULL,
                edited_at TEXT NULL,
                is_deleted INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ');

        DB::statement('
            CREATE TABLE chat_participants (
                id TEXT PRIMARY KEY,
                thread_id TEXT NOT NULL,
                user_id TEXT NOT NULL,
                last_delivered_message_id TEXT NULL,
                last_read_message_id TEXT NULL,
                unread_count INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ');

        DB::statement('
            CREATE TABLE chat_message_reactions (
                id TEXT PRIMARY KEY,
                message_id TEXT NOT NULL,
                user_id TEXT NOT NULL,
                emoji TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
        ');

        DB::statement('
            CREATE TABLE user_presences (
                user_id TEXT PRIMARY KEY,
                is_online INTEGER NOT NULL DEFAULT 0,
                last_seen_at TEXT NULL,
                updated_at TEXT NULL
            )
        ');
    }

    private function seedUsers(): void
    {
        DB::table('users')->insert([
            [
                'id' => 'admin-1',
                'name' => 'Admin One',
                'email' => 'admin@example.test',
                'contactNumber' => '1111111111',
                'roles' => json_encode(['admin']),
            ],
            [
                'id' => 'employee-1',
                'name' => 'Employee One',
                'email' => 'employee@example.test',
                'contactNumber' => '2222222222',
                'roles' => json_encode(['employee']),
            ],
            [
                'id' => 'stranger-1',
                'name' => 'Stranger One',
                'email' => 'stranger@example.test',
                'contactNumber' => '3333333333',
                'roles' => json_encode(['employee']),
            ],
        ]);
    }

    private function seedDirectThread(string $userAId, string $userBId): string
    {
        $threadId = (string) Str::uuid();
        $now = now()->toDateTimeString();

        DB::table('chat_threads')->insert([
            'id' => $threadId,
            'type' => 'direct',
            'created_by' => $userAId,
            'target_user_id' => $userBId,
            'target_role' => null,
            'title' => 'Direct chat',
            'last_message_at' => null,
            'created_at' => $now,
        ]);

        DB::table('chat_participants')->insert([
            [
                'id' => (string) Str::uuid(),
                'thread_id' => $threadId,
                'user_id' => $userAId,
                'last_delivered_message_id' => null,
                'last_read_message_id' => null,
                'unread_count' => 0,
                'created_at' => $now,
            ],
            [
                'id' => (string) Str::uuid(),
                'thread_id' => $threadId,
                'user_id' => $userBId,
                'last_delivered_message_id' => null,
                'last_read_message_id' => null,
                'unread_count' => 0,
                'created_at' => $now,
            ],
        ]);

        return $threadId;
    }

    private function seedMessage(
        string $threadId,
        string $senderId,
        string $senderRole,
        string $body,
        int $sortKey
    ): string {
        $messageId = (string) Str::uuid();
        $timestamp = now()->toDateTimeString();

        DB::table('chat_messages')->insert([
            'id' => $messageId,
            'thread_id' => $threadId,
            'sender_id' => $senderId,
            'sender_role' => $senderRole,
            'body' => $body,
            'task_id' => null,
            'subtask_index' => null,
            'client_message_id' => null,
            'sort_key' => $sortKey,
            'sent_at' => $timestamp,
            'delivered_at' => null,
            'seen_at' => null,
            'edited_at' => null,
            'is_deleted' => 0,
            'created_at' => $timestamp,
        ]);

        DB::table('chat_threads')
            ->where('id', $threadId)
            ->update(['last_message_at' => $timestamp]);

        return $messageId;
    }

    private function chatHeaders(string $userId, string $role): array
    {
        return [
            'X-User-Id' => $userId,
            'X-User-Role' => $role,
            'X-Skip-Broadcast' => '0',
            'Accept' => 'application/json',
        ];
    }
}
