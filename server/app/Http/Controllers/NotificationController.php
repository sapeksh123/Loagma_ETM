<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class NotificationController extends Controller
{
    /**
     * List notifications for a given employee.
     */
    public function index(Request $request)
    {
        try {
            $employeeId = $request->query('employee_id');

            if (!$employeeId) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'employee_id is required',
                ], 400);
            }

            $notifications = DB::table('notifications')
                ->where('employee_id', $employeeId)
                ->orderBy('created_at', 'desc')
                ->get();

            return response()->json([
                'status' => 'success',
                'data' => $notifications,
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Create a new task-related notification for an employee.
     */
    public function store(Request $request)
    {
        try {
            $validated = $request->validate([
                'sender_role' => 'required|string',
                'employee_id' => 'required|string',
                'task_id' => 'required|string',
                'subtask_index' => 'nullable|integer|min:0',
                'type' => 'required|in:reminder,update',
                'message' => 'required|string|max:2000',
            ]);

            // Only manager roles can create notifications
            if (!in_array($validated['sender_role'], ['admin', 'subadmin', 'techincharge'], true)) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Only admin roles can send notifications',
                ], 403);
            }

            // Ensure employee and task exist
            $employee = DB::table('users')->where('id', $validated['employee_id'])->first();
            if (!$employee) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Employee not found',
                ], 404);
            }

            $task = DB::table('tasks')->where('id', $validated['task_id'])->first();
            if (!$task) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Task not found',
                ], 404);
            }

            $id = Str::uuid()->toString();

            $title = $task->title ?? 'Task update';

            // Ensure a chat thread exists between task creator (as admin) and employee.
            $adminId = $task->created_by ?? null;
            $threadId = null;
            $messageId = null;

            if ($adminId) {
                // Ensure the admin user exists to satisfy FK constraints on chat tables.
                $adminUser = DB::table('users')->where('id', $adminId)->first();
                if (!$adminUser) {
                    DB::table('users')->insert([
                        'id' => $adminId,
                        'contactNumber' => $adminId,
                        'name' => 'User ' . $adminId,
                    ]);
                }

                // Try to find existing direct thread.
                if ($adminId === $validated['employee_id']) {
                    // Self-thread: look for any direct thread where this user is a participant.
                    $existingThread = DB::table('chat_threads as t')
                        ->join('chat_participants as cp', 'cp.thread_id', '=', 't.id')
                        ->where('t.type', 'direct')
                        ->where('cp.user_id', $adminId)
                        ->select('t.*')
                        ->first();
                } else {
                    // Standard direct thread between two distinct users.
                    $existingThread = DB::table('chat_threads as t')
                        ->join('chat_participants as cp1', 'cp1.thread_id', '=', 't.id')
                        ->join('chat_participants as cp2', 'cp2.thread_id', '=', 't.id')
                        ->where('t.type', 'direct')
                        ->where('cp1.user_id', $adminId)
                        ->where('cp2.user_id', $validated['employee_id'])
                        ->select('t.*')
                        ->first();
                }

                if ($existingThread) {
                    $threadId = $existingThread->id;
                } else {
                    $threadId = Str::uuid()->toString();
                    DB::table('chat_threads')->insert([
                        'id' => $threadId,
                        'type' => 'direct',
                        'created_by' => $adminId,
                        'target_user_id' => $validated['employee_id'],
                        'target_role' => null,
                        'title' => $title,
                        'last_message_at' => null,
                    ]);

                    // Create participants. If admin and employee are the same user,
                    // only create one participant to satisfy the unique (thread_id, user_id) constraint.
                    if ($adminId === $validated['employee_id']) {
                        DB::table('chat_participants')->insert([
                            [
                                'id' => Str::uuid()->toString(),
                                'thread_id' => $threadId,
                                'user_id' => $adminId,
                                'last_read_message_id' => null,
                                'unread_count' => 0,
                            ],
                        ]);
                    } else {
                        DB::table('chat_participants')->insert([
                            [
                                'id' => Str::uuid()->toString(),
                                'thread_id' => $threadId,
                                'user_id' => $adminId,
                                'last_read_message_id' => null,
                                'unread_count' => 0,
                            ],
                            [
                                'id' => Str::uuid()->toString(),
                                'thread_id' => $threadId,
                                'user_id' => $validated['employee_id'],
                                'last_read_message_id' => null,
                                'unread_count' => 0,
                            ],
                        ]);
                    }
                }

                // Create a chat message representing this reminder.
                $messageId = Str::uuid()->toString();

                DB::table('chat_messages')->insert([
                    'id' => $messageId,
                    'thread_id' => $threadId,
                    'sender_id' => $adminId,
                    'sender_role' => $validated['sender_role'],
                    'body' => $validated['message'],
                    'task_id' => $validated['task_id'],
                    'subtask_index' => $validated['subtask_index'] ?? null,
                ]);

                // Mark admin as having read this message and increment unread for employee.
                $adminParticipant = DB::table('chat_participants')
                    ->where('thread_id', $threadId)
                    ->where('user_id', $adminId)
                    ->first();
                if ($adminParticipant) {
                    DB::table('chat_participants')
                        ->where('id', $adminParticipant->id)
                        ->update([
                            'last_read_message_id' => $messageId,
                        ]);
                }

                // For self-threads (admin == employee), there is only one participant
                // so we keep unread_count at 0. For normal threads, bump unread for employee.
                if ($adminId !== $validated['employee_id']) {
                    $employeeParticipant = DB::table('chat_participants')
                        ->where('thread_id', $threadId)
                        ->where('user_id', $validated['employee_id'])
                        ->first();
                    if ($employeeParticipant) {
                        DB::table('chat_participants')
                            ->where('id', $employeeParticipant->id)
                            ->update([
                                'unread_count' => $employeeParticipant->unread_count + 1,
                            ]);
                    }
                }

                DB::table('chat_threads')
                    ->where('id', $threadId)
                    ->update([
                        'last_message_at' => now(),
                    ]);
            }

            DB::table('notifications')->insert([
                'id' => $id,
                'employee_id' => $validated['employee_id'],
                'task_id' => $validated['task_id'],
                'chat_thread_id' => $threadId,
                'chat_message_id' => $messageId,
                'subtask_index' => $validated['subtask_index'] ?? null,
                'type' => $validated['type'],
                'title' => $title,
                'message' => $validated['message'],
                'is_read' => false,
            ]);

            $notification = DB::table('notifications')->where('id', $id)->first();

            // Fire-and-forget push notification to the employee if an FCM token is present.
            try {
                $this->sendPushNotificationToEmployee($employee->id, [
                    'title' => $title,
                    'body' => $validated['message'],
                    'data' => [
                        'notificationId' => $id,
                        'taskId' => $validated['task_id'],
                        'subtaskIndex' => $validated['subtask_index'] ?? null,
                        'type' => $validated['type'],
                    ],
                ]);
            } catch (\Throwable $pushError) {
                // Do not fail the main request if push sending fails.
            }

            return response()->json([
                'status' => 'success',
                'message' => 'Notification created successfully',
                'data' => $notification,
            ], 201);
        } catch (ValidationException $e) {
            return response()->json([
                'status' => 'error',
                'message' => 'Validation failed',
                'errors' => $e->errors(),
            ], 422);
        } catch (\Exception $e) {
            Log::error('NotificationController@store failed', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);

            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Mark a notification as read.
     */
    public function markRead(Request $request, string $id)
    {
        try {
            $employeeId = $request->input('employee_id');
            if (!$employeeId) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'employee_id is required',
                ], 400);
            }

            $notification = DB::table('notifications')->where('id', $id)->first();
            if (!$notification) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Notification not found',
                ], 404);
            }

            if ($notification->employee_id !== $employeeId) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Not authorized to update this notification',
                ], 403);
            }

            DB::table('notifications')->where('id', $id)->update([
                'is_read' => true,
            ]);

            $updated = DB::table('notifications')->where('id', $id)->first();

            return response()->json([
                'status' => 'success',
                'message' => 'Notification marked as read',
                'data' => $updated,
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Send a push notification to the given employee via FCM, if configured.
     *
     * Expects FCM_SERVER_KEY in the environment and uses the user's fcmToken field.
     */
    private function sendPushNotificationToEmployee(string $employeeId, array $payload): void
    {
        $serverKey = env('FCM_SERVER_KEY');
        if (!$serverKey) {
            return;
        }

        $user = DB::table('users')->where('id', $employeeId)->first();
        if (!$user || empty($user->fcmToken)) {
            return;
        }

        $body = [
            'to' => $user->fcmToken,
            'notification' => [
                'title' => $payload['title'] ?? 'Task update',
                'body' => $payload['body'] ?? '',
            ],
            'data' => $payload['data'] ?? [],
        ];

        Http::withHeaders([
            'Authorization' => 'key=' . $serverKey,
            'Content-Type' => 'application/json',
        ])->post('https://fcm.googleapis.com/fcm/send', $body);
    }
}

