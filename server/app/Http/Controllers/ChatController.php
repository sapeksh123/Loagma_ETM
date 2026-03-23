<?php

namespace App\Http\Controllers;

use App\Events\ChatThreadEvent;
use App\Events\UserPresenceEvent;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;
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
                    'cp.unread_count',
                    'cp.last_delivered_message_id',
                    'cp.last_read_message_id'
                )
                ->where('cp.user_id', $userId)
                ->orderByDesc('t.last_message_at')
                ->orderByDesc('t.created_at')
                ->get();

            $enrichedThreads = $this->enrichThreads($threads, $userId);

            Cache::put($cacheKey, $enrichedThreads, now()->addSeconds(6));

            return response()->json([
                'status' => 'success',
                'data' => $enrichedThreads,
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Custom auth endpoint for Reverb / Pusher-compatible private channels.
     */
    public function authorizeRealtime(Request $request)
    {
        try {
            $validated = $request->validate([
                'socket_id' => 'required|string|max:191',
                'channel_name' => 'required|string|max:191',
            ]);

            $actorUserId = $this->actorUserId($request);
            $channelName = trim($validated['channel_name']);

            if (!$this->canAuthorizeChannel($channelName, $actorUserId)) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Not authorized for requested realtime channel',
                ], 403);
            }

            $authString = $validated['socket_id'] . ':' . $channelName;
            $signature = hash_hmac(
                'sha256',
                $authString,
                (string) config('broadcasting.connections.reverb.secret')
            );

            return response()->json([
                'auth' => config('broadcasting.connections.reverb.key') . ':' . $signature,
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
                $threadId = $existing->id;
            } else {
                $threadId = Str::uuid()->toString();

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

                DB::table('chat_participants')->insert([
                    [
                        'id' => Str::uuid()->toString(),
                        'thread_id' => $threadId,
                        'user_id' => $userA,
                        'last_delivered_message_id' => null,
                        'last_read_message_id' => null,
                        'unread_count' => 0,
                    ],
                    [
                        'id' => Str::uuid()->toString(),
                        'thread_id' => $threadId,
                        'user_id' => $userB,
                        'last_delivered_message_id' => null,
                        'last_read_message_id' => null,
                        'unread_count' => 0,
                    ],
                ]);
            }

            $this->invalidateThreadListCaches([$userA, $userB]);
            $this->broadcastThreadState($threadId);

            return response()->json([
                'status' => 'success',
                'data' => $this->buildThreadPayload($threadId, $userA),
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
                $threadId = $existing->id;
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
                    'last_delivered_message_id' => null,
                    'last_read_message_id' => null,
                    'unread_count' => 0,
                ]);
            }

            $this->invalidateThreadListCaches([$createdBy]);
            $this->broadcastThreadState($threadId);

            return response()->json([
                'status' => 'success',
                'data' => $this->buildThreadPayload($threadId, $createdBy),
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
     * List messages for a thread using cursor-based sync.
     */
    public function listMessages(Request $request, string $threadId)
    {
        try {
            $afterSortKey = $this->toNullableInt($request->query('after_sort_key'));
            $beforeSortKey = $this->toNullableInt($request->query('before_sort_key'));
            $sinceId = $request->query('since_id');
            $includeReactions = $this->toBool($request->query('include_reactions', false));
            $limit = (int) $request->query('limit', 80);
            $limit = max(1, min($limit, 200));
            $actorUserId = $this->actorUserId($request);

            if (!$this->isThreadParticipant($threadId, $actorUserId)) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Not authorized to read this thread',
                ], 403);
            }

            if ($afterSortKey === null && $beforeSortKey === null && !empty($sinceId)) {
                $afterSortKey = $this->sortKeyForMessageId((string) $sinceId);
            }

            $baseQuery = DB::table('chat_messages')
                ->where('thread_id', $threadId);

            $hasMoreBefore = false;

            if ($beforeSortKey !== null) {
                $messages = (clone $baseQuery)
                    ->where('sort_key', '<', $beforeSortKey)
                    ->orderByDesc('sort_key')
                    ->orderByDesc('id')
                    ->limit($limit + 1)
                    ->get();

                $hasMoreBefore = $messages->count() > $limit;
                if ($hasMoreBefore) {
                    $messages = $messages->slice(0, $limit);
                }

                $messages = $messages->reverse()->values();
            } elseif ($afterSortKey !== null) {
                $messages = (clone $baseQuery)
                    ->where('sort_key', '>', $afterSortKey)
                    ->orderBy('sort_key')
                    ->orderBy('id')
                    ->limit($limit)
                    ->get();

                $hasMoreBefore = $this->hasEarlierMessages($threadId, $messages);
            } else {
                $messages = (clone $baseQuery)
                    ->orderByDesc('sort_key')
                    ->orderByDesc('id')
                    ->limit($limit + 1)
                    ->get();

                $hasMoreBefore = $messages->count() > $limit;
                if ($hasMoreBefore) {
                    $messages = $messages->slice(0, $limit);
                }

                $messages = $messages->reverse()->values();
            }

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
                'meta' => [
                    'has_more_before' => $hasMoreBefore,
                    'cursor' => [
                        'first_sort_key' => $messages->first()->sort_key ?? null,
                        'last_sort_key' => $messages->last()->sort_key ?? null,
                    ],
                ],
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

            $body = trim((string) $validated['body']);
            if ($body === '') {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Message body cannot be empty',
                ], 422);
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
                $body,
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
                $sortKey = $this->nextSortKey();

                $insertPayload = [
                    'id' => $newMessageId,
                    'thread_id' => $threadId,
                    'sender_id' => $actorUserId,
                    'sender_role' => $actorRole,
                    'body' => $body,
                    'task_id' => $validated['task_id'] ?? null,
                    'subtask_index' => $validated['subtask_index'] ?? null,
                    'sort_key' => $sortKey,
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
                        'last_delivered_message_id' => $newMessageId,
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
                $this->dispatchChatThreadEvent(
                    [$this->threadChannelName($threadId)],
                    'message.created',
                    [
                        'thread_id' => $threadId,
                        'message' => (array) $message,
                    ]
                );
                $this->broadcastThreadState($threadId);
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

            $payload = $this->applyReceiptUpdate(
                $threadId,
                $this->actorUserId($request),
                $validated['last_read_message_id'],
                $validated['last_read_message_id'],
                $this->shouldBroadcast($request)
            );

            return response()->json([
                'status' => 'success',
                'message' => 'Thread marked as read',
                'data' => $payload,
            ]);
        } catch (ValidationException $e) {
            return response()->json([
                'status' => 'error',
                'message' => 'Validation failed',
                'errors' => $e->errors(),
            ], 422);
        } catch (\InvalidArgumentException $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 422);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Batch update delivered / seen receipt cursors.
     */
    public function updateReceipts(Request $request, string $threadId)
    {
        try {
            $validated = $request->validate([
                'delivered_message_id' => 'nullable|string',
                'seen_message_id' => 'nullable|string',
            ]);

            if (empty($validated['delivered_message_id']) && empty($validated['seen_message_id'])) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'At least one receipt cursor is required',
                ], 422);
            }

            $payload = $this->applyReceiptUpdate(
                $threadId,
                $this->actorUserId($request),
                $validated['delivered_message_id'] ?? null,
                $validated['seen_message_id'] ?? null,
                $this->shouldBroadcast($request)
            );

            return response()->json([
                'status' => 'success',
                'data' => $payload,
            ]);
        } catch (ValidationException $e) {
            return response()->json([
                'status' => 'error',
                'message' => 'Validation failed',
                'errors' => $e->errors(),
            ], 422);
        } catch (\InvalidArgumentException $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
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
            $payload = $this->applyReceiptUpdate(
                $threadId,
                $this->actorUserId($request),
                $messageId,
                null,
                $this->shouldBroadcast($request)
            );

            return response()->json([
                'status' => 'success',
                'message' => 'Message marked as delivered',
                'data' => $payload,
            ]);
        } catch (\InvalidArgumentException $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
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
            $payload = $this->applyReceiptUpdate(
                $threadId,
                $this->actorUserId($request),
                $messageId,
                $messageId,
                $this->shouldBroadcast($request)
            );

            return response()->json([
                'status' => 'success',
                'message' => 'Message marked as seen',
                'data' => $payload,
            ]);
        } catch (\InvalidArgumentException $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
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
            $thread = DB::table('chat_threads')->where('id', $threadId)->first();

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

            $updatedMessage = $this->loadEnrichedMessage($messageId, $thread, $actorUserId);

            if ($this->shouldBroadcast($request)) {
                $this->dispatchChatThreadEvent(
                    [$this->threadChannelName($threadId)],
                    'message.updated',
                    [
                        'thread_id' => $threadId,
                        'message' => (array) $updatedMessage,
                    ]
                );
            }

            return response()->json([
                'status' => 'success',
                'message' => 'Reaction added',
                'data' => $updatedMessage->reactions ?? [],
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
            $thread = DB::table('chat_threads')->where('id', $threadId)->first();

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

            $updatedMessage = $this->loadEnrichedMessage($messageId, $thread, $actorUserId);

            if ($this->shouldBroadcast($request)) {
                $this->dispatchChatThreadEvent(
                    [$this->threadChannelName($threadId)],
                    'message.updated',
                    [
                        'thread_id' => $threadId,
                        'message' => (array) $updatedMessage,
                    ]
                );
            }

            return response()->json([
                'status' => 'success',
                'message' => 'Reaction removed',
                'data' => $updatedMessage->reactions ?? [],
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
                $this->dispatchChatThreadEvent(
                    [$this->threadChannelName($threadId)],
                    'typing.updated',
                    [
                        'thread_id' => $threadId,
                        'user_id' => $actorUserId,
                        'is_typing' => $validated['is_typing'],
                    ]
                );
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
                $threadIds = $this->getUserThreadIds($actorUserId);
                if (!empty($threadIds)) {
                    $channels = array_map(
                        fn (string $id) => $this->threadChannelName($id),
                        $threadIds
                    );
                    $this->dispatchUserPresenceEvent($channels, [
                        'user_id' => $actorUserId,
                        'is_online' => $validated['is_online'],
                        'last_seen_at' => $validated['is_online'] ? null : now()->toDateTimeString(),
                    ]);
                }
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

    private function canAuthorizeChannel(string $channelName, string $actorUserId): bool
    {
        $trimmed = trim($channelName);

        if (preg_match('/^private-chat\.thread\.(.+)$/', $trimmed, $matches) === 1) {
            return $this->isThreadParticipant($matches[1], $actorUserId);
        }

        if (preg_match('/^private-chat\.user\.(.+)$/', $trimmed, $matches) === 1) {
            return $matches[1] === $actorUserId;
        }

        return false;
    }

    private function applyReceiptUpdate(
        string $threadId,
        string $actorUserId,
        ?string $deliveredMessageId,
        ?string $seenMessageId,
        bool $broadcast = true
    ): array {
        if (!$this->isThreadParticipant($threadId, $actorUserId)) {
            throw new \InvalidArgumentException('Not authorized for this thread');
        }

        $thread = DB::table('chat_threads')->where('id', $threadId)->first();
        if (!$thread) {
            throw new \InvalidArgumentException('Thread not found');
        }

        $participant = DB::table('chat_participants')
            ->where('thread_id', $threadId)
            ->where('user_id', $actorUserId)
            ->first();

        if (!$participant) {
            throw new \InvalidArgumentException('Participant not found for this thread');
        }

        $currentDeliveredSortKey = $this->sortKeyForMessageId($participant->last_delivered_message_id);
        $currentSeenSortKey = $this->sortKeyForMessageId($participant->last_read_message_id);

        $nextDelivered = $this->resolveReceiptCursor($threadId, $deliveredMessageId, $currentDeliveredSortKey);
        $nextSeen = $this->resolveReceiptCursor($threadId, $seenMessageId, $currentSeenSortKey);

        if ($nextSeen !== null && ($nextDelivered === null || $nextSeen->sort_key > $nextDelivered->sort_key)) {
            $nextDelivered = $nextSeen;
        }

        DB::transaction(function () use (
            $thread,
            $threadId,
            $actorUserId,
            $participant,
            $currentSeenSortKey,
            $nextDelivered,
            $nextSeen
        ) {
            $updatePayload = [];
            if ($nextDelivered !== null) {
                $updatePayload['last_delivered_message_id'] = $nextDelivered->id;
            }
            if ($nextSeen !== null) {
                $updatePayload['last_read_message_id'] = $nextSeen->id;
            }
            if (!empty($updatePayload)) {
                $effectiveSeenSortKey = $nextSeen?->sort_key ?? $currentSeenSortKey;
                $updatePayload['unread_count'] = $this->countUnreadMessages(
                    $threadId,
                    $actorUserId,
                    $effectiveSeenSortKey
                );

                DB::table('chat_participants')
                    ->where('id', $participant->id)
                    ->update($updatePayload);
            }

            if ($thread->type === 'direct') {
                if ($nextDelivered !== null) {
                    DB::table('chat_messages')
                        ->where('thread_id', $threadId)
                        ->where('sender_id', '!=', $actorUserId)
                        ->where('sort_key', '<=', $nextDelivered->sort_key)
                        ->whereNull('delivered_at')
                        ->update([
                            'delivered_at' => now(),
                        ]);
                }

                if ($nextSeen !== null) {
                    $seenQuery = DB::table('chat_messages')
                        ->where('thread_id', $threadId)
                        ->where('sender_id', '!=', $actorUserId)
                        ->where('sort_key', '<=', $nextSeen->sort_key);

                    (clone $seenQuery)
                        ->whereNull('delivered_at')
                        ->update([
                            'delivered_at' => now(),
                        ]);

                    (clone $seenQuery)
                        ->whereNull('seen_at')
                        ->update([
                            'seen_at' => now(),
                        ]);
                }
            }
        });

        $participantUserIds = $this->getThreadParticipants($threadId);
        $this->invalidateThreadListCaches($participantUserIds);

        $payload = [
            'thread_id' => $threadId,
            'by_user_id' => $actorUserId,
            'delivered_message_id' => $nextDelivered->id ?? $participant->last_delivered_message_id,
            'delivered_sort_key' => $nextDelivered->sort_key ?? $currentDeliveredSortKey,
            'seen_message_id' => $nextSeen->id ?? $participant->last_read_message_id,
            'seen_sort_key' => $nextSeen->sort_key ?? $currentSeenSortKey,
        ];

        if ($broadcast) {
            $this->dispatchChatThreadEvent(
                [$this->threadChannelName($threadId)],
                'receipt.updated',
                $payload
            );
            $this->broadcastThreadState($threadId);
        }

        return $payload;
    }

    private function resolveReceiptCursor(string $threadId, ?string $messageId, ?int $currentSortKey): ?object
    {
        if ($messageId === null || trim($messageId) === '') {
            return null;
        }

        $message = DB::table('chat_messages')
            ->where('id', trim($messageId))
            ->where('thread_id', $threadId)
            ->select('id', 'thread_id', 'sort_key')
            ->first();

        if (!$message) {
            throw new \InvalidArgumentException('Receipt cursor does not belong to this thread');
        }

        if ($currentSortKey !== null && $message->sort_key <= $currentSortKey) {
            return null;
        }

        return $message;
    }

    private function countUnreadMessages(string $threadId, string $actorUserId, ?int $seenSortKey): int
    {
        $query = DB::table('chat_messages')
            ->where('thread_id', $threadId)
            ->where('sender_id', '!=', $actorUserId);

        if ($seenSortKey !== null) {
            $query->where('sort_key', '>', $seenSortKey);
        }

        return (int) $query->count();
    }

    private function hasEarlierMessages(string $threadId, Collection $messages): bool
    {
        $firstSortKey = $messages->first()->sort_key ?? null;
        if ($firstSortKey === null) {
            return false;
        }

        return DB::table('chat_messages')
            ->where('thread_id', $threadId)
            ->where('sort_key', '<', $firstSortKey)
            ->exists();
    }

    private function nextSortKey(): int
    {
        return (int) floor(microtime(true) * 1000000);
    }

    private function sortKeyForMessageId(?string $messageId): ?int
    {
        if ($messageId === null || trim($messageId) === '') {
            return null;
        }

        $sortKey = DB::table('chat_messages')
            ->where('id', trim($messageId))
            ->value('sort_key');

        return $sortKey !== null ? (int) $sortKey : null;
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

        sort($ids);
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

    private function fetchPresencesByUserIds(array $userIds): array
    {
        $ids = array_values(array_filter(array_unique($userIds)));
        if (empty($ids)) {
            return [];
        }

        return DB::table('user_presences')
            ->whereIn('user_id', $ids)
            ->select('user_id', 'is_online', 'last_seen_at')
            ->get()
            ->keyBy('user_id')
            ->toArray();
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

    private function getThreadParticipantRows(string $threadId): Collection
    {
        return DB::table('chat_participants')
            ->where('thread_id', $threadId)
            ->get([
                'thread_id',
                'user_id',
                'last_delivered_message_id',
                'last_read_message_id',
                'unread_count',
            ]);
    }

    private function getUserThreadIds(string $userId): array
    {
        return DB::table('chat_participants')
            ->where('user_id', $userId)
            ->pluck('thread_id')
            ->values()
            ->all();
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

    private function toNullableInt(mixed $value): ?int
    {
        if ($value === null || $value === '') {
            return null;
        }

        return is_numeric($value) ? (int) $value : null;
    }

    /**
     * @param  string[]  $channels
     * @param  array<string, mixed>  $payload
     */
    private function dispatchChatThreadEvent(array $channels, string $eventName, array $payload = []): void
    {
        try {
            event(new ChatThreadEvent($channels, $eventName, $payload));
        } catch (\Throwable $e) {
            Log::warning('Chat realtime broadcast dispatch failed', [
                'channels' => $channels,
                'event_name' => $eventName,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * @param  string[]  $channels
     * @param  array<string, mixed>  $payload
     */
    private function dispatchUserPresenceEvent(array $channels, array $payload = []): void
    {
        try {
            event(new UserPresenceEvent($channels, $payload));
        } catch (\Throwable $e) {
            Log::warning('Presence broadcast dispatch failed', [
                'channels' => $channels,
                'error' => $e->getMessage(),
            ]);
        }
    }

    private function threadChannelName(string $threadId): string
    {
        return 'chat.thread.' . $threadId;
    }

    private function userChannelName(string $userId): string
    {
        return 'chat.user.' . $userId;
    }

    private function broadcastThreadState(string $threadId): void
    {
        $participantUserIds = $this->getThreadParticipants($threadId);
        foreach ($participantUserIds as $participantUserId) {
            $payload = $this->buildThreadPayload($threadId, (string) $participantUserId);
            if ($payload === null) {
                continue;
            }

            $this->dispatchChatThreadEvent(
                [$this->userChannelName((string) $participantUserId)],
                'thread.updated',
                [
                    'thread' => $payload,
                ]
            );
        }
    }

    private function enrichThreads(Collection $threads, string $viewerUserId): array
    {
        if ($threads->isEmpty()) {
            return [];
        }

        $threadIds = $threads->pluck('id')->values()->all();
        $directThreadIds = $threads->where('type', 'direct')->pluck('id')->values()->all();

        $counterpartsByThread = collect();
        if (!empty($directThreadIds)) {
            $counterpartsByThread = DB::table('chat_participants as cp')
                ->whereIn('cp.thread_id', $directThreadIds)
                ->where('cp.user_id', '!=', $viewerUserId)
                ->select('cp.thread_id', 'cp.user_id as counterpart_user_id')
                ->get()
                ->keyBy('thread_id');
        }

        $latestMessagesByThread = [];
        $latestMessages = DB::table('chat_messages')
            ->whereIn('thread_id', $threadIds)
            ->orderByDesc('sort_key')
            ->orderByDesc('id')
            ->get([
                'id',
                'thread_id',
                'sender_id',
                'body',
                'sort_key',
                'created_at',
            ]);

        foreach ($latestMessages as $latestMessage) {
            if (!isset($latestMessagesByThread[$latestMessage->thread_id])) {
                $latestMessagesByThread[$latestMessage->thread_id] = $latestMessage;
            }
        }

        $counterpartUserIds = $counterpartsByThread
            ->pluck('counterpart_user_id')
            ->filter()
            ->values()
            ->all();
        $names = $this->fetchUsersByIds($counterpartUserIds);
        $presences = $this->fetchPresencesByUserIds($counterpartUserIds);

        return $threads->map(function ($thread) use ($counterpartsByThread, $latestMessagesByThread, $names, $presences) {
            $latestMessage = $latestMessagesByThread[$thread->id] ?? null;

            $thread->last_message_body = $latestMessage->body ?? null;
            $thread->last_message_id = $latestMessage->id ?? null;
            $thread->last_message_sender_id = $latestMessage->sender_id ?? null;
            $thread->last_message_sort_key = $latestMessage ? (int) $latestMessage->sort_key : null;

            if ($thread->type === 'direct') {
                $counterpart = $counterpartsByThread->get($thread->id);
                $counterpartUserId = $counterpart->counterpart_user_id ?? null;
                $counterpartName = $counterpartUserId ? ($names[$counterpartUserId]->name ?? null) : null;
                $presence = $counterpartUserId ? ($presences[$counterpartUserId] ?? null) : null;

                $thread->counterpart_user_id = $counterpartUserId;
                $thread->counterpart_name = $counterpartName;
                $thread->counterpart_is_online = $presence ? (bool) $presence->is_online : false;
                $thread->counterpart_last_seen_at = $presence->last_seen_at ?? null;

                if (!empty($counterpartName)) {
                    $thread->title = $counterpartName;
                }
            }

            return (array) $thread;
        })->values()->all();
    }

    private function buildThreadPayload(string $threadId, string $viewerUserId): ?array
    {
        $thread = DB::table('chat_threads')->where('id', $threadId)->first();
        if (!$thread) {
            return null;
        }

        $participant = DB::table('chat_participants')
            ->where('thread_id', $threadId)
            ->where('user_id', $viewerUserId)
            ->first();
        if (!$participant) {
            return null;
        }

        $collection = collect([
            (object) [
                'id' => $thread->id,
                'type' => $thread->type,
                'title' => $thread->title,
                'created_by' => $thread->created_by,
                'target_user_id' => $thread->target_user_id,
                'target_role' => $thread->target_role,
                'last_message_at' => $thread->last_message_at,
                'unread_count' => $participant->unread_count,
                'last_delivered_message_id' => $participant->last_delivered_message_id,
                'last_read_message_id' => $participant->last_read_message_id,
            ],
        ]);

        return $this->enrichThreads($collection, $viewerUserId)[0] ?? null;
    }

    /**
     * Enrich a collection of messages with sender/receiver display fields.
     */
    private function enrichMessages(Collection $messages, ?object $thread, string $viewerUserId): Collection
    {
        if (!$thread || $messages->isEmpty()) {
            return $messages;
        }

        $participants = $this->getThreadParticipants($thread->id);
        $participantRows = $this->getThreadParticipantRows($thread->id)->keyBy('user_id');
        $senderIds = $messages->pluck('sender_id')->unique()->values()->all();
        $userIds = collect(array_merge($senderIds, $participants))->unique()->values()->all();
        $usersById = collect($this->fetchUsersByIds($userIds));
        $counterpartReceiptState = $this->directReceiptStateForViewer($thread, $viewerUserId, $participantRows);

        return $messages->map(function ($message) use ($thread, $usersById, $participants, $viewerUserId, $counterpartReceiptState) {
            return $this->enrichMessageWithLookups(
                $message,
                $thread,
                $viewerUserId,
                $usersById,
                $participants,
                $counterpartReceiptState
            );
        });
    }

    /**
     * Enrich a single message with sender/receiver display fields.
     */
    private function enrichMessage(?object $message, ?object $thread, string $viewerUserId): ?object
    {
        if (!$message || !$thread) {
            return $message;
        }

        $participants = $this->getThreadParticipants($thread->id);
        $participantRows = $this->getThreadParticipantRows($thread->id)->keyBy('user_id');
        $userIds = collect(array_merge([$message->sender_id], $participants))->unique()->values()->all();
        $usersById = collect($this->fetchUsersByIds($userIds));
        $counterpartReceiptState = $this->directReceiptStateForViewer($thread, $viewerUserId, $participantRows);

        return $this->enrichMessageWithLookups(
            $message,
            $thread,
            $viewerUserId,
            $usersById,
            $participants,
            $counterpartReceiptState
        );
    }

    private function loadEnrichedMessage(string $messageId, ?object $thread, string $viewerUserId): ?object
    {
        $message = DB::table('chat_messages')->where('id', $messageId)->first();
        if (!$message) {
            return null;
        }

        $message->reactions = DB::table('chat_message_reactions')
            ->where('message_id', $messageId)
            ->orderBy('created_at')
            ->get();

        return $this->enrichMessage($message, $thread, $viewerUserId);
    }

    private function directReceiptStateForViewer(?object $thread, string $viewerUserId, Collection $participantRows): array
    {
        if (!$thread || $thread->type !== 'direct') {
            return [
                'delivered_sort_key' => null,
                'seen_sort_key' => null,
            ];
        }

        $counterpart = $participantRows->first(function ($participant) use ($viewerUserId) {
            return $participant->user_id !== $viewerUserId;
        });

        return [
            'delivered_sort_key' => $this->sortKeyForMessageId($counterpart->last_delivered_message_id ?? null),
            'seen_sort_key' => $this->sortKeyForMessageId($counterpart->last_read_message_id ?? null),
        ];
    }

    private function enrichMessageWithLookups(
        object $message,
        object $thread,
        string $viewerUserId,
        Collection $usersById,
        array $participants,
        array $counterpartReceiptState
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
        $message->thread_type = $thread->type ?? null;
        $message->status = 'sent';

        if ($thread->type === 'direct' && $message->sender_id === $viewerUserId) {
            $messageSortKey = isset($message->sort_key) ? (int) $message->sort_key : null;
            $seenSortKey = $counterpartReceiptState['seen_sort_key'];
            $deliveredSortKey = $counterpartReceiptState['delivered_sort_key'];

            if ($messageSortKey !== null && $seenSortKey !== null && $messageSortKey <= $seenSortKey) {
                $message->status = 'seen';
            } elseif ($messageSortKey !== null && $deliveredSortKey !== null && $messageSortKey <= $deliveredSortKey) {
                $message->status = 'delivered';
            }
        }

        return $message;
    }
}

