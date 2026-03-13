<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
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
            $userId = $request->query('user_id');
            $role = $request->query('role');

            if (!$userId || !$role) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'user_id and role are required',
                ], 400);
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
                'user_a_id' => 'required|string',
                'user_b_id' => 'required|string|different:user_a_id',
                'title' => 'nullable|string|max:255',
            ]);

            $userA = $validated['user_a_id'];
            $userB = $validated['user_b_id'];

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
                'created_by' => 'required|string',
                'scope' => 'required|in:all,role',
                'target_role' => 'nullable|string',
                'title' => 'nullable|string|max:255',
            ]);

            $createdBy = $validated['created_by'];
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
                'sender_id' => 'required|string',
                'sender_role' => 'required|string',
                'body' => 'required|string',
                'task_id' => 'nullable|string',
                'subtask_index' => 'nullable|integer|min:0',
            ]);

            $thread = DB::table('chat_threads')->where('id', $threadId)->first();
            if (!$thread) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Thread not found',
                ], 404);
            }

            $messageId = Str::uuid()->toString();

            DB::table('chat_messages')->insert([
                'id' => $messageId,
                'thread_id' => $threadId,
                'sender_id' => $validated['sender_id'],
                'sender_role' => $validated['sender_role'],
                'body' => $validated['body'],
                'task_id' => $validated['task_id'] ?? null,
                'subtask_index' => $validated['subtask_index'] ?? null,
            ]);

            // Ensure sender is a participant
            $existingSender = DB::table('chat_participants')
                ->where('thread_id', $threadId)
                ->where('user_id', $validated['sender_id'])
                ->first();
            if (!$existingSender) {
                DB::table('chat_participants')->insert([
                    'id' => Str::uuid()->toString(),
                    'thread_id' => $threadId,
                    'user_id' => $validated['sender_id'],
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
                ->where('user_id', '!=', $validated['sender_id'])
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
                'user_id' => 'required|string',
                'last_read_message_id' => 'required|string',
            ]);

            $participant = DB::table('chat_participants')
                ->where('thread_id', $threadId)
                ->where('user_id', $validated['user_id'])
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
}

