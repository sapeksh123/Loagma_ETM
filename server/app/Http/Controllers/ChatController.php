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
    private ?bool $hasClientMessageIdColumn = null;

    /**
     * List chat threads for a given user and role.
     */
    public function listThreads(Request $request)
    {
        try {
            $userId = $this->actorUserId($request);
            $role = $this->actorRole($request);

            $cacheKey = $this->threadListCacheKey($userId, $role);
            $cached = Cache::get($cacheKey);
            if ($cached !== null) {
                return response()->json([
                    'status' => 'success',
                    'data' => $cached,
                ]);
            }

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
                    ->whereIn('cp.thread_id', $directThreadIds)
                    ->where('cp.user_id', '!=', $userId)
                    ->select('cp.thread_id', 'cp.user_id as counterpart_user_id')
                    ->get()
                    ->keyBy('thread_id');

                $counterpartUserIds = $counterpartsByThread
                    ->pluck('counterpart_user_id')
                    ->filter()
                    ->values()
                    ->all();

                $names = $this->fetchUsersByIds($counterpartUserIds);

                $counterpartsByThread = $counterpartsByThread->map(function ($row) use ($names) {
                    $row->counterpart_name = $names[$row->counterpart_user_id]->name ?? null;
                    return $row;
                });
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

            Cache::put($cacheKey, $threads->values()->all(), now()->addSeconds(6));

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

            $this->invalidateThreadListCaches([$userA, $userB]);

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

            $this->invalidateThreadListCaches([$createdBy]);

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
            $includeReactions = $this->toBool($request->query('include_reactions', false));
            $limit = (int) $request->query('limit', 80);
            if ($limit <= 0) {
                $limit = 80;
            }
            $limit = min($limit, 200);
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
                    $query->where(function ($q) use ($sinceMessage, $sinceId) {
                        $q->where('created_at', '>', $sinceMessage->created_at)
                            ->orWhere(function ($sameTime) use ($sinceMessage, $sinceId) {
                                $sameTime->where('created_at', '=', $sinceMessage->created_at)
                                    ->where('id', '>', $sinceId);
                            });
                    });
                }
            }

            $messages = $query->limit($limit)->get();

            if ($includeReactions && $messages->isNotEmpty()) {
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
            } elseif ($messages->isNotEmpty()) {
                $messages = $messages->map(function ($message) {
                    $message->reactions = [];
                    return $message;
                });
            }

            $thread = DB::table('chat_threads')->where('id', $threadId)->first();
            $messages = $this->enrichMessages($messages, $thread, $actorUserId);

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
                'client_message_id' => 'nullable|string|max:191',
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

            $clientMessageId = isset($validated['client_message_id'])
                ? trim((string) $validated['client_message_id'])
                : '';

            $hasClientMessageIdColumn = $this->hasClientMessageIdColumn();

            $messageId = DB::transaction(function () use (
                $threadId,
                $actorUserId,
                $actorRole,
                $validated,
                $clientMessageId,
                $hasClientMessageIdColumn
            ) {
                if ($clientMessageId !== '' && $hasClientMessageIdColumn) {
                    $existing = DB::table('chat_messages')
                        ->where('thread_id', $threadId)
                        ->where('sender_id', $actorUserId)
                        ->where('client_message_id', $clientMessageId)
                        ->first();

                    if ($existing) {
                        return $existing->id;
                    }
                }

                $newMessageId = Str::uuid()->toString();

                $insertPayload = [
                    'id' => $newMessageId,
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
                ];

                if ($hasClientMessageIdColumn) {
                    $insertPayload['client_message_id'] = $clientMessageId !== '' ? $clientMessageId : null;
                }

                DB::table('chat_messages')->insert($insertPayload);

                DB::table('chat_participants')
                    ->where('thread_id', $threadId)
                    ->where('user_id', $actorUserId)
                    ->update([
                        'last_read_message_id' => $newMessageId,
                    ]);

                DB::table('chat_participants')
                    ->where('thread_id', $threadId)
                    ->where('user_id', '!=', $actorUserId)
                    ->increment('unread_count');

                DB::table('chat_threads')
                    ->where('id', $threadId)
                    ->update([
                        'last_message_at' => now(),
                    ]);

                return $newMessageId;
            });

            $message = DB::table('chat_messages')->where('id', $messageId)->first();
            $message->reactions = [];
            $message = $this->enrichMessage($message, $thread, $actorUserId);

            $participantUserIds = $this->getThreadParticipants($threadId);
            $this->invalidateThreadListCaches($participantUserIds);

            if ($this->shouldBroadcast($request)) {
                $this->dispatchChatThreadEvent($threadId, 'message_sent', [
                    'message' => (array) $message,
                ]);
            }

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

            $lastReadMessage = DB::table('chat_messages')
                ->where('id', $validated['last_read_message_id'])
                ->where('thread_id', $threadId)
                ->first();

            if (!$lastReadMessage) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'last_read_message_id is not part of this thread',
                ], 422);
            }

            DB::transaction(function () use ($participant, $validated, $threadId, $actorUserId, $lastReadMessage) {
                DB::table('chat_participants')
                    ->where('id', $participant->id)
                    ->update([
                        'last_read_message_id' => $validated['last_read_message_id'],
                        'unread_count' => 0,
                    ]);

                DB::table('chat_messages')
                    ->where('thread_id', $threadId)
                    ->where('sender_id', '!=', $actorUserId)
                    ->where(function ($q) use ($lastReadMessage) {
                        $q->where('created_at', '<', $lastReadMessage->created_at)
                            ->orWhere(function ($sameTime) use ($lastReadMessage) {
                                $sameTime->where('created_at', '=', $lastReadMessage->created_at)
                                    ->where('id', '<=', $lastReadMessage->id);
                            });
                    })
                    ->where(function ($query) {
                        $query->whereNull('seen_at')->orWhereNull('delivered_at');
                    })
                    ->update([
                        'delivered_at' => now(),
                        'seen_at' => now(),
                    ]);
            });

            $this->invalidateThreadListCaches([$actorUserId]);

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

                if ($this->shouldBroadcast($request)) {
                    $this->dispatchChatThreadEvent($threadId, 'message_delivered', [
                        'message_id' => $messageId,
                        'by_user_id' => $actorUserId,
                    ]);
                }
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

                if ($this->shouldBroadcast($request)) {
                    $this->dispatchChatThreadEvent($threadId, 'message_seen', [
                        'message_id' => $messageId,
                        'by_user_id' => $actorUserId,
                    ]);
                }
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

            if ($this->shouldBroadcast($request)) {
                $this->dispatchChatThreadEvent($threadId, 'reactions_updated', [
                    'message_id' => $messageId,
                    'reactions' => $reactions->map(fn ($r) => (array) $r)->values()->all(),
                ]);
            }

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

            if ($this->shouldBroadcast($request)) {
                $this->dispatchChatThreadEvent($threadId, 'reactions_updated', [
                    'message_id' => $messageId,
                    'reactions' => $reactions->map(fn ($r) => (array) $r)->values()->all(),
                ]);
            }

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

            if ($this->shouldBroadcast($request)) {
                $this->dispatchChatThreadEvent($threadId, 'typing_updated', [
                    'user_id' => $actorUserId,
                    'is_typing' => $validated['is_typing'],
                ]);
            }

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

            if ($this->shouldBroadcast($request)) {
                $this->dispatchUserPresenceEvent(
                    $actorUserId,
                    $validated['is_online'],
                    $validated['is_online'] ? null : now()->toDateTimeString()
                );
            }

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

    private function shouldBroadcast(Request $request): bool
    {
        $header = strtolower((string) $request->header('X-Skip-Broadcast', ''));
        if ($header === '1' || $header === 'true' || $header === 'yes') {
            return false;
        }

        return true;
    }

    private function hasClientMessageIdColumn(): bool
    {
        if ($this->hasClientMessageIdColumn !== null) {
            return $this->hasClientMessageIdColumn;
        }

        $cacheKey = 'chat:has_client_message_id_column';
        $cached = Cache::get($cacheKey);
        if (is_bool($cached)) {
            $this->hasClientMessageIdColumn = $cached;
            return $this->hasClientMessageIdColumn;
        }

        $this->hasClientMessageIdColumn = DB::getSchemaBuilder()->hasColumn('chat_messages', 'client_message_id');
        Cache::put($cacheKey, $this->hasClientMessageIdColumn, now()->addMinutes(30));

        return $this->hasClientMessageIdColumn;
    }

    private function fetchUsersByIds(array $userIds): array
    {
        $ids = array_values(array_filter(array_unique($userIds)));
        if (empty($ids)) {
            return [];
        }

        $cacheKey = 'chat:user-names:' . md5(json_encode($ids));
        return Cache::remember($cacheKey, now()->addMinutes(5), function () use ($ids) {
            return DB::table('users')
                ->whereIn('id', $ids)
                ->select('id', 'name')
                ->get()
                ->keyBy('id')
                ->toArray();
        });
    }

    private function getThreadParticipants(string $threadId): array
    {
        $cacheKey = 'chat:thread-participants:' . $threadId;
        return Cache::remember($cacheKey, now()->addMinutes(2), function () use ($threadId) {
            return DB::table('chat_participants')
                ->where('thread_id', $threadId)
                ->pluck('user_id')
                ->values()
                ->all();
        });
    }

    private function threadListCacheKey(string $userId, string $role): string
    {
        return 'chat:threads:list:' . $userId . ':' . strtolower($role);
    }

    private function invalidateThreadListCaches(array $userIds): void
    {
        $roles = ['admin', 'subadmin', 'techincharge', 'employee', 'manager'];
        $ids = array_values(array_filter(array_unique($userIds)));
        foreach ($ids as $userId) {
            foreach ($roles as $role) {
                Cache::forget($this->threadListCacheKey((string) $userId, $role));
            }
        }
    }

    private function toBool(mixed $value): bool
    {
        if (is_bool($value)) {
            return $value;
        }

        $raw = strtolower(trim((string) $value));
        return in_array($raw, ['1', 'true', 'yes', 'on'], true);
    }

    private function dispatchChatThreadEvent(string $threadId, string $eventType, array $payload = []): void
    {
        try {
            event(new ChatThreadEvent($threadId, $eventType, $payload));
        } catch (\Throwable $e) {
            Log::warning('Chat thread broadcast dispatch failed', [
                'thread_id' => $threadId,
                'event_type' => $eventType,
                'error' => $e->getMessage(),
            ]);
        }
    }

    private function dispatchUserPresenceEvent(string $userId, bool $isOnline, ?string $lastSeenAt): void
    {
        try {
            event(new UserPresenceEvent($userId, $isOnline, $lastSeenAt));
        } catch (\Throwable $e) {
            Log::warning('Presence broadcast dispatch failed', [
                'user_id' => $userId,
                'is_online' => $isOnline,
                'error' => $e->getMessage(),
            ]);
        }
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
        $participants = $this->getThreadParticipants($thread->id);

        $userIds = collect(array_merge($senderIds, $participants))->unique()->values()->all();
        $usersById = collect($this->fetchUsersByIds($userIds));

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

        $participants = $this->getThreadParticipants($thread->id);

        $userIds = collect(array_merge([$message->sender_id], $participants))->unique()->values()->all();
        $usersById = collect($this->fetchUsersByIds($userIds));

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
        $message->thread_type = $thread->type ?? null;

        return $message;
    }
}

