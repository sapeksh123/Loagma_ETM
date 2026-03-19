<?php

namespace App\Http\Controllers;

use App\Events\ChatThreadEvent;
use App\Events\UserPresenceEvent;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class ChatController extends Controller
{
    /**
     * List chat threads for a given user and role.
     */
    public function listThreads(Request $request)
    {
        try {
            $userId = $this->actorUserId($request);
            $role = $this->actorRole($request);

            $threads = DB::table('chat_participants as cp')
                ->join('chat_threads as t', 'cp.thread_id', '=', 't.id')
                ->select(
                    't.id',
                    't.type',
                    't.title',
                    't.created_by',
                    't.target_user_id',
                    't.target_role',
                    't.last_message_at',
                    'cp.unread_count'
                )
                ->where('cp.user_id', $userId)
                ->orderByDesc('t.last_message_at')
                ->orderByDesc('t.created_at')
                ->get();

            $directThreadIds = $threads
                ->where('type', 'direct')
                ->pluck('id')
                ->values()
                ->all();

            $counterpartsByThread = collect();
            if (!empty($directThreadIds)) {
                $counterpartsByThread = DB::table('chat_participants as cp')
                    ->join('users as u', 'u.id', '=', 'cp.user_id')
                    ->whereIn('cp.thread_id', $directThreadIds)
                    ->where('cp.user_id', '!=', $userId)
                    ->select('cp.thread_id', 'u.id as counterpart_user_id', 'u.name as counterpart_name')
                    ->get()
                    ->keyBy('thread_id');
            }

            $threads = $threads->map(function ($thread) use ($counterpartsByThread) {
                if ($thread->type === 'direct') {
                    $counterpart = $counterpartsByThread->get($thread->id);
                    $thread->counterpart_user_id = $counterpart->counterpart_user_id ?? null;
                    $thread->counterpart_name = $counterpart->counterpart_name ?? null;
                    if (!empty($thread->counterpart_name)) {
                        $thread->title = $thread->counterpart_name;
                    }
                }
                return $thread;
            });

            return response()->json([
                'status' => 'success',
                'data' => $threads,
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Create or get a direct chat thread between two users.
     */
    public function openDirectThread(Request $request)
    {
        try {
            $validated = $request->validate([
                'user_a_id' => 'nullable|string',
                'user_b_id' => 'required|string',
                'title' => 'nullable|string|max:255',
            ]);

            $userA = $this->actorUserId($request);
            if (!empty($validated['user_a_id']) && $validated['user_a_id'] !== $userA) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'sender identity mismatch',
                ], 403);
            }

            $userB = $validated['user_b_id'];

            if ($userA === $userB) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Cannot open a direct chat with yourself',
                ], 422);
            }

            // Try to find existing direct thread for these two participants.
            $existing = DB::table('chat_threads as t')
                ->join('chat_participants as cp1', 'cp1.thread_id', '=', 't.id')
                ->join('chat_participants as cp2', 'cp2.thread_id', '=', 't.id')
                ->where('t.type', 'direct')
                ->where('cp1.user_id', $userA)
                ->where('cp2.user_id', $userB)
                ->select('t.*')
                ->first();

            if ($existing) {
                $thread = $existing;
            } else {
                $threadId = Str::uuid()->toString();

                // Fallback generic title; UI can customize.
                $title = $validated['title'] ?? 'Direct chat';

                DB::table('chat_threads')->insert([
                    'id' => $threadId,
                    'type' => 'direct',
                    'created_by' => $userA,
                    'target_user_id' => $userB,
                    'target_role' => null,
                    'title' => $title,
                    'last_message_at' => null,
                ]);

                // Participants
                DB::table('chat_participants')->insert([
                    [
                        'id' => Str::uuid()->toString(),
                        'thread_id' => $threadId,
                        'user_id' => $userA,
                        'last_read_message_id' => null,
                        'unread_count' => 0,
                    ],
                    [
                        'id' => Str::uuid()->toString(),
                        'thread_id' => $threadId,
                        'user_id' => $userB,
                        'last_read_message_id' => null,
                        'unread_count' => 0,
                    ],
                ]);

                $thread = DB::table('chat_threads')->where('id', $threadId)->first();
            }

            return response()->json([
                'status' => 'success',
                'data' => $thread,
            ]);
        } catch (ValidationException $e) {
            return response()->json([
                'status' => 'error',
                'message' => 'Validation failed',
                'errors' => $e->errors(),
            ], 422);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Create or get a broadcast thread.
     */
    public function openBroadcastThread(Request $request)
    {
        try {
            $validated = $request->validate([
                'created_by' => 'nullable|string',
                'scope' => 'required|in:all,role',
                'target_role' => 'nullable|string',
                'title' => 'nullable|string|max:255',
            ]);

            $createdBy = $this->actorUserId($request);
            if (!empty($validated['created_by']) && $validated['created_by'] !== $createdBy) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'creator identity mismatch',
                ], 403);
            }

            $scope = $validated['scope'];
            $targetRole = $validated['target_role'] ?? null;

            $type = $scope === 'all' ? 'broadcast_all' : 'broadcast_role';

            $query = DB::table('chat_threads')
                ->where('type', $type)
                ->where('created_by', $createdBy);
            if ($type === 'broadcast_role') {
                $query->where('target_role', $targetRole);
            }

            $existing = $query->first();

            if ($existing) {
                $thread = $existing;
            } else {
                $threadId = Str::uuid()->toString();
                $title = $validated['title']
                    ?? ($type === 'broadcast_all'
                        ? 'Broadcast: All employees'
                        : 'Broadcast: ' . ($targetRole ?? 'role'));

                DB::table('chat_threads')->insert([
                    'id' => $threadId,
                    'type' => $type,
                    'created_by' => $createdBy,
                    'target_user_id' => null,
                    'target_role' => $type === 'broadcast_role' ? $targetRole : null,
                    'title' => $title,
                    'last_message_at' => null,
                ]);

                // Creator is always a participant
                DB::table('chat_participants')->insert([
                    'id' => Str::uuid()->toString(),
                    'thread_id' => $threadId,
                    'user_id' => $createdBy,
                    'last_read_message_id' => null,
                    'unread_count' => 0,
                ]);

                $thread = DB::table('chat_threads')->where('id', $threadId)->first();
            }

            return response()->json([
                'status' => 'success',
                'data' => $thread,
            ]);
        } catch (ValidationException $e) {
            return response()->json([
                'status' => 'error',
                'message' => 'Validation failed',
                'errors' => $e->errors(),
            ], 422);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * List messages for a thread, optionally only messages newer than a given ID.
     */
    public function listMessages(Request $request, string $threadId)
    {
        try {
            $sinceId = $request->query('since_id');
            $actorUserId = $this->actorUserId($request);

            if (!$this->isThreadParticipant($threadId, $actorUserId)) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Not authorized to read this thread',
                ], 403);
            }

            $query = DB::table('chat_messages')
                ->where('thread_id', $threadId)
                ->orderBy('created_at')
                ->orderBy('id');

            if ($sinceId) {
                $sinceMessage = DB::table('chat_messages')
                    ->where('id', $sinceId)
                    ->first();
                if ($sinceMessage) {
                    $query->where('created_at', '>=', $sinceMessage->created_at)
                        ->where('id', '>', $sinceId);
                }
            }

            $messages = $query->limit(200)->get();

            if ($messages->isNotEmpty()) {
                $messageIds = $messages->pluck('id')->values()->all();
                $allReactions = DB::table('chat_message_reactions')
                    ->whereIn('message_id', $messageIds)
                    ->select('id', 'message_id', 'user_id', 'emoji', 'created_at')
                    ->orderBy('created_at')
                    ->get()
                    ->groupBy('message_id');

                $messages = $messages->map(function ($message) use ($allReactions) {
                    $message->reactions = $allReactions->get($message->id, collect())->values();
                    return $message;
                });
            }

            $thread = DB::table('chat_threads')->where('id', $threadId)->first();
            $messages = $this->enrichMessages($messages, $thread, $actorUserId);

            if ($messages->isNotEmpty()) {
                $sample = $messages->first();
                Log::debug('chat.listMessages.identity', [
                    'thread_id' => $threadId,
                    'current_user_id' => $actorUserId,
                    'sample_sender_id' => $sample->sender_id,
                    'sample_receiver_id' => $sample->receiver_id ?? null,
                ]);
            }

            return response()->json([
                'status' => 'success',
                'data' => $messages,
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Send a message in a thread.
     */
    public function sendMessage(Request $request, string $threadId)
    {
        try {
            $validated = $request->validate([
                'sender_id' => 'nullable|string',
                'sender_role' => 'nullable|string',
                'body' => 'required|string',
                'task_id' => 'nullable|string',
                'subtask_index' => 'nullable|integer|min:0',
            ]);

            $actorUserId = $this->actorUserId($request);
            $actorRole = $this->actorRole($request);

            if (!empty($validated['sender_id']) && $validated['sender_id'] !== $actorUserId) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'sender identity mismatch',
                ], 403);
            }

            if (!empty($validated['sender_role']) && $validated['sender_role'] !== $actorRole) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'sender role mismatch',
                ], 403);
            }

            $thread = DB::table('chat_threads')->where('id', $threadId)->first();
            if (!$thread) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Thread not found',
                ], 404);
            }

            if (!$this->isThreadParticipant($threadId, $actorUserId)) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Only thread participants can send messages',
                ], 403);
            }

            $messageId = Str::uuid()->toString();

            DB::table('chat_messages')->insert([
                'id' => $messageId,
                'thread_id' => $threadId,
                'sender_id' => $actorUserId,
                'sender_role' => $actorRole,
                'body' => $validated['body'],
                'task_id' => $validated['task_id'] ?? null,
                'subtask_index' => $validated['subtask_index'] ?? null,
                'sent_at' => now(),
                'delivered_at' => null,
                'seen_at' => null,
                'edited_at' => null,
                'is_deleted' => false,
            ]);

            // Ensure sender is a participant
            $existingSender = DB::table('chat_participants')
                ->where('thread_id', $threadId)
                ->where('user_id', $actorUserId)
                ->first();
            if (!$existingSender) {
                DB::table('chat_participants')->insert([
                    'id' => Str::uuid()->toString(),
                    'thread_id' => $threadId,
                    'user_id' => $actorUserId,
                    'last_read_message_id' => $messageId,
                    'unread_count' => 0,
                ]);
            } else {
                DB::table('chat_participants')
                    ->where('id', $existingSender->id)
                    ->update([
                        'last_read_message_id' => $messageId,
                    ]);
            }

            // Increment unread count for all other participants
            $participants = DB::table('chat_participants')
                ->where('thread_id', $threadId)
                ->where('user_id', '!=', $actorUserId)
                ->get();
            foreach ($participants as $p) {
                DB::table('chat_participants')
                    ->where('id', $p->id)
                    ->update([
                        'unread_count' => $p->unread_count + 1,
                    ]);
            }

            // Update thread last_message_at
            DB::table('chat_threads')
                ->where('id', $threadId)
                ->update([
                    'last_message_at' => now(),
                ]);

            $message = DB::table('chat_messages')->where('id', $messageId)->first();
            $message->reactions = [];
            $message = $this->enrichMessage($message, $thread, $actorUserId);

            Log::debug('chat.sendMessage.identity', [
                'thread_id' => $threadId,
                'current_user_id' => $actorUserId,
                'sender_id' => $message->sender_id,
                'receiver_id' => $message->receiver_id ?? null,
            ]);

            event(new ChatThreadEvent($threadId, 'message_sent', [
                'message' => (array) $message,
            ]));

            return response()->json([
                'status' => 'success',
                'data' => $message,
            ], 201);
        } catch (ValidationException $e) {
            return response()->json([
                'status' => 'error',
                'message' => 'Validation failed',
                'errors' => $e->errors(),
            ], 422);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Mark messages in a thread as read for a user.
     */
    public function markThreadRead(Request $request, string $threadId)
    {
        try {
            $validated = $request->validate([
                'last_read_message_id' => 'required|string',
            ]);

            $actorUserId = $this->actorUserId($request);

            $participant = DB::table('chat_participants')
                ->where('thread_id', $threadId)
                ->where('user_id', $actorUserId)
                ->first();

            if (!$participant) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Participant not found for this thread',
                ], 404);
            }

            DB::table('chat_participants')
                ->where('id', $participant->id)
                ->update([
                    'last_read_message_id' => $validated['last_read_message_id'],
                    'unread_count' => 0,
                ]);

            DB::table('chat_messages')
                ->where('thread_id', $threadId)
                ->where('sender_id', '!=', $actorUserId)
                ->where(function ($query) {
                    $query->whereNull('seen_at')->orWhereNull('delivered_at');
                })
                ->update([
                    'delivered_at' => now(),
                    'seen_at' => now(),
                ]);

            return response()->json([
                'status' => 'success',
                'message' => 'Thread marked as read',
            ]);
        } catch (ValidationException $e) {
            return response()->json([
                'status' => 'error',
                'message' => 'Validation failed',
                'errors' => $e->errors(),
            ], 422);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Mark an individual message as delivered.
     */
    public function markMessageDelivered(Request $request, string $threadId, string $messageId)
    {
        try {
            $actorUserId = $this->actorUserId($request);

            if (!$this->isThreadParticipant($threadId, $actorUserId)) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Not authorized for this thread',
                ], 403);
            }

            $message = DB::table('chat_messages')
                ->where('id', $messageId)
                ->where('thread_id', $threadId)
                ->first();

            if (!$message) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Message not found',
                ], 404);
            }

            if ($message->sender_id !== $actorUserId) {
                DB::table('chat_messages')
                    ->where('id', $messageId)
                    ->whereNull('delivered_at')
                    ->update(['delivered_at' => now()]);

                event(new ChatThreadEvent($threadId, 'message_delivered', [
                    'message_id' => $messageId,
                    'by_user_id' => $actorUserId,
                ]));
            }

            return response()->json([
                'status' => 'success',
                'message' => 'Message marked as delivered',
            ]);
        } catch (ValidationException $e) {
            return response()->json([
                'status' => 'error',
                'message' => 'Validation failed',
                'errors' => $e->errors(),
            ], 422);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Mark an individual message as seen.
     */
    public function markMessageSeen(Request $request, string $threadId, string $messageId)
    {
        try {
            $actorUserId = $this->actorUserId($request);

            if (!$this->isThreadParticipant($threadId, $actorUserId)) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Not authorized for this thread',
                ], 403);
            }

            $message = DB::table('chat_messages')
                ->where('id', $messageId)
                ->where('thread_id', $threadId)
                ->first();

            if (!$message) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Message not found',
                ], 404);
            }

            if ($message->sender_id !== $actorUserId) {
                DB::table('chat_messages')
                    ->where('id', $messageId)
                    ->update([
                        'delivered_at' => DB::raw('COALESCE(delivered_at, NOW())'),
                        'seen_at' => DB::raw('COALESCE(seen_at, NOW())'),
                    ]);

                event(new ChatThreadEvent($threadId, 'message_seen', [
                    'message_id' => $messageId,
                    'by_user_id' => $actorUserId,
                ]));
            }

            return response()->json([
                'status' => 'success',
                'message' => 'Message marked as seen',
            ]);
        } catch (ValidationException $e) {
            return response()->json([
                'status' => 'error',
                'message' => 'Validation failed',
                'errors' => $e->errors(),
            ], 422);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * List reactions for a single message.
     */
    public function listMessageReactions(Request $request, string $threadId, string $messageId)
    {
        try {
            $userId = $this->actorUserId($request);

            if (!$this->isThreadParticipant($threadId, $userId)) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Not authorized for this thread',
                ], 403);
            }

            $exists = DB::table('chat_messages')
                ->where('id', $messageId)
                ->where('thread_id', $threadId)
                ->exists();

            if (!$exists) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Message not found',
                ], 404);
            }

            $reactions = DB::table('chat_message_reactions')
                ->where('message_id', $messageId)
                ->orderBy('created_at')
                ->get();

            return response()->json([
                'status' => 'success',
                'data' => $reactions,
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Add a reaction for the current user on a message.
     */
    public function addMessageReaction(Request $request, string $threadId, string $messageId)
    {
        try {
            $validated = $request->validate([
                'emoji' => 'required|string|max:32',
            ]);

            $actorUserId = $this->actorUserId($request);

            if (!$this->isThreadParticipant($threadId, $actorUserId)) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Not authorized for this thread',
                ], 403);
            }

            $exists = DB::table('chat_messages')
                ->where('id', $messageId)
                ->where('thread_id', $threadId)
                ->exists();

            if (!$exists) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Message not found',
                ], 404);
            }

            DB::table('chat_message_reactions')->insertOrIgnore([
                'id' => Str::uuid()->toString(),
                'message_id' => $messageId,
                'user_id' => $actorUserId,
                'emoji' => $validated['emoji'],
                'created_at' => now(),
            ]);

            $reactions = DB::table('chat_message_reactions')
                ->where('message_id', $messageId)
                ->orderBy('created_at')
                ->get();

            event(new ChatThreadEvent($threadId, 'reactions_updated', [
                'message_id' => $messageId,
                'reactions' => $reactions->map(fn ($r) => (array) $r)->values()->all(),
            ]));

            return response()->json([
                'status' => 'success',
                'message' => 'Reaction added',
                'data' => $reactions,
            ], 201);
        } catch (ValidationException $e) {
            return response()->json([
                'status' => 'error',
                'message' => 'Validation failed',
                'errors' => $e->errors(),
            ], 422);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Remove a reaction for the current user from a message.
     */
    public function removeMessageReaction(Request $request, string $threadId, string $messageId)
    {
        try {
            $validated = $request->validate([
                'emoji' => 'required|string|max:32',
            ]);

            $actorUserId = $this->actorUserId($request);

            if (!$this->isThreadParticipant($threadId, $actorUserId)) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Not authorized for this thread',
                ], 403);
            }

            $exists = DB::table('chat_messages')
                ->where('id', $messageId)
                ->where('thread_id', $threadId)
                ->exists();

            if (!$exists) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Message not found',
                ], 404);
            }

            DB::table('chat_message_reactions')
                ->where('message_id', $messageId)
                ->where('user_id', $actorUserId)
                ->where('emoji', $validated['emoji'])
                ->delete();

            $reactions = DB::table('chat_message_reactions')
                ->where('message_id', $messageId)
                ->orderBy('created_at')
                ->get();

            event(new ChatThreadEvent($threadId, 'reactions_updated', [
                'message_id' => $messageId,
                'reactions' => $reactions->map(fn ($r) => (array) $r)->values()->all(),
            ]));

            return response()->json([
                'status' => 'success',
                'message' => 'Reaction removed',
                'data' => $reactions,
            ]);
        } catch (ValidationException $e) {
            return response()->json([
                'status' => 'error',
                'message' => 'Validation failed',
                'errors' => $e->errors(),
            ], 422);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Update typing state for a user in a thread. Stored in cache with short TTL.
     */
    public function updateTypingStatus(Request $request, string $threadId)
    {
        try {
            $validated = $request->validate([
                'is_typing' => 'required|boolean',
            ]);

            $actorUserId = $this->actorUserId($request);

            if (!$this->isThreadParticipant($threadId, $actorUserId)) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Not authorized for this thread',
                ], 403);
            }

            $cacheKey = 'chat:typing:' . $threadId . ':' . $actorUserId;
            if ($validated['is_typing']) {
                Cache::put($cacheKey, true, now()->addSeconds(8));
            } else {
                Cache::forget($cacheKey);
            }

            event(new ChatThreadEvent($threadId, 'typing_updated', [
                'user_id' => $actorUserId,
                'is_typing' => $validated['is_typing'],
            ]));

            return response()->json([
                'status' => 'success',
                'data' => [
                    'thread_id' => $threadId,
                    'user_id' => $actorUserId,
                    'is_typing' => $validated['is_typing'],
                ],
            ]);
        } catch (ValidationException $e) {
            return response()->json([
                'status' => 'error',
                'message' => 'Validation failed',
                'errors' => $e->errors(),
            ], 422);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Update presence state and keep last-seen information.
     */
    public function upsertPresence(Request $request)
    {
        try {
            $validated = $request->validate([
                'is_online' => 'required|boolean',
            ]);

            $actorUserId = $this->actorUserId($request);

            DB::table('user_presences')->updateOrInsert(
                ['user_id' => $actorUserId],
                [
                    'is_online' => $validated['is_online'],
                    'last_seen_at' => $validated['is_online'] ? null : now(),
                    'updated_at' => now(),
                ]
            );

            event(new UserPresenceEvent(
                $actorUserId,
                $validated['is_online'],
                $validated['is_online'] ? null : now()->toDateTimeString()
            ));

            return response()->json([
                'status' => 'success',
                'data' => [
                    'user_id' => $actorUserId,
                    'is_online' => $validated['is_online'],
                ],
            ]);
        } catch (ValidationException $e) {
            return response()->json([
                'status' => 'error',
                'message' => 'Validation failed',
                'errors' => $e->errors(),
            ], 422);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Helper: verify user is participant of given thread.
     */
    private function isThreadParticipant(string $threadId, string $userId): bool
    {
        return DB::table('chat_participants')
            ->where('thread_id', $threadId)
            ->where('user_id', $userId)
            ->exists();
    }

    private function actorUserId(Request $request): string
    {
        return (string) $request->attributes->get('actor_user_id', '');
    }

    private function actorRole(Request $request): string
    {
        return (string) $request->attributes->get('actor_role', '');
    }

    /**
     * Enrich a collection of messages with sender/receiver display fields.
     */
    private function enrichMessages($messages, ?object $thread, string $viewerUserId)
    {
        if (!$thread || $messages->isEmpty()) {
            return $messages;
        }

        $senderIds = $messages->pluck('sender_id')->unique()->values()->all();
        $participants = DB::table('chat_participants')
            ->where('thread_id', $thread->id)
            ->pluck('user_id')
            ->values()
            ->all();

        $userIds = collect(array_merge($senderIds, $participants))->unique()->values()->all();
        $usersById = DB::table('users')
            ->whereIn('id', $userIds)
            ->select('id', 'name')
            ->get()
            ->keyBy('id');

        return $messages->map(function ($message) use ($thread, $usersById, $participants, $viewerUserId) {
            return $this->enrichMessageWithLookups($message, $thread, $viewerUserId, $usersById, $participants);
        });
    }

    /**
     * Enrich a single message with sender/receiver display fields.
     */
    private function enrichMessage(?object $message, ?object $thread, string $viewerUserId)
    {
        if (!$message || !$thread) {
            return $message;
        }

        $participants = DB::table('chat_participants')
            ->where('thread_id', $thread->id)
            ->pluck('user_id')
            ->values()
            ->all();

        $userIds = collect(array_merge([$message->sender_id], $participants))->unique()->values()->all();
        $usersById = DB::table('users')
            ->whereIn('id', $userIds)
            ->select('id', 'name')
            ->get()
            ->keyBy('id');

        return $this->enrichMessageWithLookups($message, $thread, $viewerUserId, $usersById, $participants);
    }

    private function enrichMessageWithLookups(
        object $message,
        object $thread,
        string $viewerUserId,
        $usersById,
        array $participants
    ): object {
        $message->sender_name = $usersById->get($message->sender_id)->name ?? null;

        $receiverId = null;
        if ($thread->type === 'direct') {
            foreach ($participants as $participantUserId) {
                if ($participantUserId !== $message->sender_id) {
                    $receiverId = $participantUserId;
                    break;
                }
            }
        }

        $message->receiver_id = $receiverId;
        $message->receiver_name = $receiverId
            ? ($usersById->get($receiverId)->name ?? null)
            : null;

        $message->viewer_user_id = $viewerUserId;

        return $message;
    }
}

