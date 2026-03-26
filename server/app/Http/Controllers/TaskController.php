<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Carbon\Carbon;

class TaskController extends Controller
{
    private const VALID_STATUSES = [
        'assigned',
        'in_progress',
        'completed',
        'paused',
        'need_help',
        'ignore',
        'hold',
    ];

    private static function actorFromRequest(Request $request)
    {
        $userId = $request->input('user_id') ?: $request->query('user_id');
        $userRole = $request->input('user_role') ?: $request->query('user_role');
        return [
            'user_id' => is_string($userId) ? trim($userId) : null,
            'user_role' => is_string($userRole) ? trim($userRole) : null,
        ];
    }

    private static function canHideTaskForActor($task, string $actorUserId)
    {
        return (string) ($task->created_by ?? '') === $actorUserId
            && (string) ($task->assigned_to ?? '') === $actorUserId;
    }

    private static function mapRoleIdToAppRole($roleId)
    {
        switch ((string) $roleId) {
            case 'R001':
                return 'admin';
            case 'R006':
                return 'subadmin';
            case 'R007':
                return 'techincharge';
            default:
                return 'employee';
        }
    }

    private static function isManagerRole(?string $role): bool
    {
        return in_array($role, ['admin', 'subadmin', 'techincharge'], true);
    }

    private static function appRoleForUserId(?string $userId): string
    {
        if (!$userId) return 'employee';
        $row = DB::table('users')->select('roleId')->where('id', $userId)->first();
        if (!$row) return 'employee';
        return self::mapRoleIdToAppRole($row->roleId ?? null);
    }

    private static function canViewTaskForActor($task, string $actorUserId, string $actorRole): bool
    {
        if (self::isManagerRole($actorRole)) {
            // Managers can view employee tasks (except personal tasks not owned by actor).
            if (($task->category ?? '') === 'personal' && (string) ($task->created_by ?? '') !== $actorUserId) {
                return false;
            }
            return true;
        }

        return (string) ($task->created_by ?? '') === $actorUserId
            || (string) ($task->assigned_to ?? '') === $actorUserId;
    }

    private static function canEditOrDeleteTaskForActor($task, string $actorUserId, string $actorRole): bool
    {
        // Ownership-only for edit/delete across roles.
        return (string) ($task->created_by ?? '') === $actorUserId;
    }

    private static function canUpdateStatusForActor($task, string $actorUserId, string $actorRole): bool
    {
        $createdBy = (string) ($task->created_by ?? '');
        $assignedTo = (string) ($task->assigned_to ?? '');

        if (self::isManagerRole($actorRole)) {
            // Managers can change status only on tasks they created.
            return $createdBy === $actorUserId;
        }

        // Employees can change status on their own created tasks.
        if ($createdBy === $actorUserId) {
            return true;
        }

        // Exception: employee can change status on manager-created tasks assigned to them.
        if ($assignedTo === $actorUserId) {
            $creatorRole = self::appRoleForUserId($createdBy);
            return self::isManagerRole($creatorRole);
        }

        return false;
    }

    private static function canSetCurrentForActor($task, string $actorUserId, string $actorRole): bool
    {
        // Keep current-task permissions aligned with status-update permissions.
        return self::canUpdateStatusForActor($task, $actorUserId, $actorRole);
    }

    /** Decode subtasks JSON and normalize to [{text, status, need_help_note?}] for API response, plus attach daily history for daily tasks. */
    private static function decodeTask($task)
    {
        if (!$task) return $task;
        $arr = (array) $task;
        if (!isset($arr['creator_role']) && isset($arr['creator_role_id'])) {
            $arr['creator_role'] = self::mapRoleIdToAppRole($arr['creator_role_id']);
        }
        if (isset($arr['subtasks'])) {
            $raw = is_string($arr['subtasks']) ? json_decode($arr['subtasks'], true) : $arr['subtasks'];
            $arr['subtasks'] = self::normalizeSubtasksForResponse($raw ?? []);
        }

        // Attach 7-day history for daily tasks
        if (
            ($arr['category'] ?? null) === 'daily' &&
            isset($arr['id']) &&
            Schema::hasTable('task_daily_statuses') &&
            Schema::hasTable('subtask_daily_statuses')
        ) {
            $taskId = $arr['id'];
            $today = Carbon::today();
            $dates = [];
            for ($i = 6; $i >= 0; $i--) {
                $dates[] = $today->copy()->subDays($i)->toDateString();
            }

            // Task-level history (normalize date to Y-m-d so keys match $dates regardless of DB driver format)
            $rows = DB::table('task_daily_statuses')
                ->where('task_id', $taskId)
                ->whereBetween('date', [$dates[0], end($dates)])
                ->get();
            $byDate = [];
            foreach ($rows as $row) {
                $dateKey = Carbon::parse($row->date)->toDateString();
                $byDate[$dateKey] = [
                    'date' => $dateKey,
                    'status' => $row->status,
                    'note' => $row->note,
                ];
            }
            $taskHistory = [];
            foreach ($dates as $d) {
                if (isset($byDate[$d])) {
                    $taskHistory[] = $byDate[$d];
                } else {
                    $taskHistory[] = [
                        'date' => $d,
                        'status' => 'assigned',
                        'note' => null,
                    ];
                }
            }
            $arr['task_history'] = $taskHistory;

            // Subtask-level history
            $subtaskHistory = [];
            $subtaskRows = DB::table('subtask_daily_statuses')
                ->where('task_id', $taskId)
                ->whereBetween('date', [$dates[0], end($dates)])
                ->get();
            foreach ($subtaskRows as $row) {
                $idx = (int) $row->subtask_index;
                $dateKey = Carbon::parse($row->date)->toDateString();
                if (!isset($subtaskHistory[$idx])) {
                    $subtaskHistory[$idx] = [];
                }
                $subtaskHistory[$idx][$dateKey] = [
                    'date' => $dateKey,
                    'status' => $row->status,
                    'note' => $row->note,
                ];
            }

            // Always emit a 7-day history list for every subtask index
            $subtaskCount = isset($arr['subtasks']) && is_array($arr['subtasks'])
                ? count($arr['subtasks'])
                : 0;
            $finalSubtaskHistory = [];
            for ($idx = 0; $idx < $subtaskCount; $idx++) {
                $byDateMap = $subtaskHistory[$idx] ?? [];
                $entries = [];
                foreach ($dates as $d) {
                    if (isset($byDateMap[$d])) {
                        $entries[] = $byDateMap[$d];
                    } else {
                        $entries[] = [
                            'date' => $d,
                            'status' => 'assigned',
                            'note' => null,
                        ];
                    }
                }
                $finalSubtaskHistory[$idx] = $entries;
            }
            $arr['subtask_history'] = $finalSubtaskHistory;
        }
        return $arr;
    }

    /** Normalize subtasks to [{text, status, need_help_note?}] for API response */
    private static function normalizeSubtasksForResponse($raw)
    {
        if (!is_array($raw)) return [];
        $out = [];
        foreach ($raw as $item) {
            if (is_array($item) && isset($item['text'])) {
                $status = $item['status'] ?? 'assigned';
                $row = [
                    'text' => (string) $item['text'],
                    'status' => in_array($status, self::VALID_STATUSES, true) ? $status : 'assigned',
                ];
                if (!empty($item['need_help_note']) && is_string($item['need_help_note'])) {
                    $row['need_help_note'] = trim($item['need_help_note']);
                }
                $out[] = $row;
            } elseif (is_string($item)) {
                $out[] = ['text' => $item, 'status' => 'assigned'];
            }
        }
        return $out;
    }

    /** Normalize subtasks from request to [{text, status, need_help_note?}] for storage. Accepts array or JSON string. */
    private static function normalizeSubtasksForStorage($input)
    {
        if (is_string($input)) {
            $decoded = json_decode($input, true);
            $input = is_array($decoded) ? $decoded : [];
        }
        if (!is_array($input)) {
            return null;
        }
        $out = [];
        foreach ($input as $item) {
            if (is_array($item) && isset($item['text'])) {
                $status = $item['status'] ?? 'assigned';
                if (!in_array($status, self::VALID_STATUSES, true)) {
                    $status = 'assigned';
                }
                $text = trim((string) $item['text']);
                if ($text !== '') {
                    $row = ['text' => $text, 'status' => $status];
                    if (!empty($item['need_help_note']) && is_string($item['need_help_note'])) {
                        $row['need_help_note'] = trim($item['need_help_note']);
                    }
                    $out[] = $row;
                }
            } elseif (is_string($item) && trim($item) !== '') {
                $out[] = ['text' => trim($item), 'status' => 'assigned'];
            }
        }
        return $out;
    }

    /** Get raw subtasks from request (array or JSON string). Reads from raw JSON body first so nested arrays are never lost. */
    private static function getSubtasksFromRequest(Request $request)
    {
        // Prefer raw JSON body so Laravel's input merge doesn't drop or flatten nested arrays
        if ($request->header('Content-Type') && str_contains($request->header('Content-Type'), 'application/json')) {
            $content = $request->getContent();
            if (is_string($content) && $content !== '') {
                $body = json_decode($content, true);
                if (is_array($body) && array_key_exists('subtasks', $body)) {
                    $raw = $body['subtasks'];
                    if (is_array($raw)) {
                        return $raw;
                    }
                    if (is_string($raw)) {
                        $decoded = json_decode($raw, true);
                        return is_array($decoded) ? $decoded : [];
                    }
                }
            }
        }
        $raw = $request->input('subtasks');
        if ($raw === null) {
            return [];
        }
        if (is_string($raw)) {
            $decoded = json_decode($raw, true);
            return is_array($decoded) ? $decoded : [];
        }
        return is_array($raw) ? $raw : [];
    }

    // Get all tasks (filtered by user role)
    public function index(Request $request)
    {
        try {
            $userId = $request->query('user_id');
            $userRole = $request->query('user_role'); // 'admin' or 'employee'
            $targetUserId = $request->query('target_user_id');
            $currentOnly = (string) $request->query('current_only', '0') === '1';

            if (!$userId || !$userRole) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'user_id and user_role are required'
                ], 400);
            }

            if (in_array($userRole, ['admin', 'subadmin', 'techincharge'], true)) {
                // Manager roles see all non-personal tasks.
                // Optional target_user_id narrows results to one employee scope.
                $query = DB::table('tasks')
                    ->leftJoin('users as creator', 'tasks.created_by', '=', 'creator.id')
                    ->leftJoin('users as assignee', 'tasks.assigned_to', '=', 'assignee.id')
                    ->select(
                        'tasks.*',
                        'creator.name as creator_name',
                        'creator.roleId as creator_role_id',
                        'assignee.name as assignee_name',
                        'assignee.employeeCode as assignee_code'
                    )
                    ->where('tasks.category', '!=', 'personal');

                if (Schema::hasTable('task_hidden_items')) {
                    $query->leftJoin('task_hidden_items as hidden', function ($join) use ($userId) {
                        $join->on('hidden.task_id', '=', 'tasks.id')
                            ->where('hidden.hidden_by_user_id', '=', $userId);
                    })->whereNull('hidden.id');
                }

                if ($targetUserId) {
                    $query->where(function ($q) use ($targetUserId) {
                        $q->where('tasks.created_by', $targetUserId)
                            ->orWhere('tasks.assigned_to', $targetUserId);
                    });
                }

                if ($currentOnly && Schema::hasColumn('tasks', 'is_current')) {
                    $query->where('tasks.is_current', 1);
                }

                $tasks = $query->orderBy('tasks.createdAt', 'desc')->get();
            } else {
                // Employee sees their own tasks (assigned to them OR created by them).
                $tasks = DB::table('tasks')
                    ->leftJoin('users as creator', 'tasks.created_by', '=', 'creator.id')
                    ->leftJoin('users as assignee', 'tasks.assigned_to', '=', 'assignee.id')
                    ->select(
                        'tasks.*',
                        'creator.name as creator_name',
                        'creator.roleId as creator_role_id',
                        'assignee.name as assignee_name'
                    )
                    ->where(function ($query) use ($userId) {
                        $query->where('tasks.assigned_to', $userId)
                            ->orWhere('tasks.created_by', $userId);
                    });

                if (Schema::hasTable('task_hidden_items')) {
                    $tasks->leftJoin('task_hidden_items as hidden', function ($join) use ($userId) {
                        $join->on('hidden.task_id', '=', 'tasks.id')
                            ->where('hidden.hidden_by_user_id', '=', $userId);
                    })->whereNull('hidden.id');
                }

                $tasks = $tasks
                    ->when($currentOnly && Schema::hasColumn('tasks', 'is_current'), function ($q) {
                        $q->where('tasks.is_current', 1);
                    })
                    ->orderBy('tasks.createdAt', 'desc')
                    ->get();
            }

            $data = $tasks->map(function ($task) {
                return self::decodeTask($task);
            })->values()->all();

            return response()->json([
                'status' => 'success',
                'data' => $data
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage()
            ], 500);
        }
    }

    // Get hidden tasks for current actor
    public function hiddenIndex(Request $request)
    {
        try {
            $actor = self::actorFromRequest($request);
            $userId = $actor['user_id'];
            $userRole = $actor['user_role'];

            if (!$userId || !$userRole) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'user_id and user_role are required'
                ], 400);
            }

            if (!Schema::hasTable('task_hidden_items')) {
                return response()->json([
                    'status' => 'success',
                    'data' => []
                ]);
            }

            $tasks = DB::table('task_hidden_items as hidden')
                ->join('tasks', 'hidden.task_id', '=', 'tasks.id')
                ->leftJoin('users as creator', 'tasks.created_by', '=', 'creator.id')
                ->leftJoin('users as assignee', 'tasks.assigned_to', '=', 'assignee.id')
                ->select(
                    'tasks.*',
                    'creator.name as creator_name',
                    'creator.roleId as creator_role_id',
                    'assignee.name as assignee_name',
                    'assignee.employeeCode as assignee_code',
                    'hidden.created_at as hidden_at'
                )
                ->where('hidden.hidden_by_user_id', $userId)
                ->orderBy('hidden.created_at', 'desc')
                ->get();

            $data = $tasks->map(function ($task) {
                return self::decodeTask($task);
            })->values()->all();

            return response()->json([
                'status' => 'success',
                'data' => $data
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage()
            ], 500);
        }
    }

    // Create a new task
    public function store(Request $request)
    {
        try {
            $validated = $request->validate([
                'title' => 'required|string|max:255',
                'description' => 'nullable|string',
                'subtasks' => 'nullable|array',
                'category' => 'required|in:daily,project,personal,monthly,quarterly,yearly,other',
                'priority' => 'required|in:low,medium,high,critical',
                'deadline_date' => 'nullable|date',
                'deadline_time' => 'nullable',
                'created_by' => 'required|string',
                'user_role' => 'nullable|string',
                'assigned_to' => 'required|string',
            ]);

            $actor = self::actorFromRequest($request);
            $actorUserId = $actor['user_id'] ?: ($validated['created_by'] ?? null);
            $actorRole = $actor['user_role'] ?: ($validated['user_role'] ?? null);
            $actorRole = $actorRole ? trim(strtolower($actorRole)) : self::appRoleForUserId($actorUserId);

            if (!$actorUserId || !$actorRole) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'user_id and user_role are required'
                ], 400);
            }

            // Ensure creator and assignee users exist to satisfy FK constraints
            $creatorId = $validated['created_by'];
            $assigneeId = $validated['assigned_to'];

            if ($creatorId !== $actorUserId) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Not authorized to create tasks for another creator'
                ], 403);
            }

            if (!self::isManagerRole($actorRole)) {
                // Employees can create only their own tasks.
                if ($creatorId !== $actorUserId || $assigneeId !== $actorUserId) {
                    return response()->json([
                        'status' => 'error',
                        'message' => 'Employees can create tasks only for themselves'
                    ], 403);
                }
            }

            // Personal tasks are strictly self-assigned only.
            if (($validated['category'] ?? '') === 'personal' && $creatorId !== $assigneeId) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Personal tasks can only be assigned to self',
                ], 422);
            }

            $existingCreator = DB::table('users')->where('id', $creatorId)->first();
            if (!$existingCreator) {
                DB::table('users')->insert([
                    'id' => $creatorId,
                    'contactNumber' => $creatorId,
                    'name' => 'User ' . $creatorId,
                ]);
            }

            if ($assigneeId !== $creatorId) {
                $existingAssignee = DB::table('users')->where('id', $assigneeId)->first();
                if (!$existingAssignee) {
                    DB::table('users')->insert([
                        'id' => $assigneeId,
                        'contactNumber' => $assigneeId,
                        'name' => 'User ' . $assigneeId,
                    ]);
                }
            }

            $taskId = Str::uuid()->toString();

            $subtasksRaw = self::getSubtasksFromRequest($request);
            $normalized = self::normalizeSubtasksForStorage($subtasksRaw);
            $subtasksJson = $normalized !== null && count($normalized) > 0 ? json_encode($normalized) : null;

            // Ensure subtasks column exists (in case migration was not run)
            if (!Schema::hasColumn('tasks', 'subtasks')) {
                DB::statement('ALTER TABLE tasks ADD COLUMN subtasks JSON NULL AFTER description');
            }

            DB::table('tasks')->insert([
                'id' => $taskId,
                'title' => $validated['title'],
                'description' => $validated['description'] ?? null,
                'subtasks' => $subtasksJson,
                'category' => $validated['category'],
                'priority' => $validated['priority'],
                'status' => 'assigned',
                'deadline_date' => $validated['deadline_date'] ?? null,
                'deadline_time' => $validated['deadline_time'] ?? null,
                'created_by' => $creatorId,
                'assigned_to' => $assigneeId,
            ]);

            $task = DB::table('tasks')->where('id', $taskId)->first();

            return response()->json([
                'status' => 'success',
                'message' => 'Task created successfully',
                'data' => self::decodeTask($task)
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
                'message' => $e->getMessage()
            ], 500);
        }
    }

    // Get a single task
    public function show(Request $request, $id)
    {
        try {
            $actor = self::actorFromRequest($request);
            $userId = $actor['user_id'];
            $userRole = $actor['user_role'];

            if (!$userId || !$userRole) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'user_id and user_role are required'
                ], 400);
            }

            $task = DB::table('tasks')
                ->leftJoin('users as creator', 'tasks.created_by', '=', 'creator.id')
                ->leftJoin('users as assignee', 'tasks.assigned_to', '=', 'assignee.id')
                ->select(
                    'tasks.*',
                    'creator.name as creator_name',
                    'creator.roleId as creator_role_id',
                    'assignee.name as assignee_name',
                    'assignee.employeeCode as assignee_code'
                )
                ->where('tasks.id', $id)
                ->first();

            if (!$task) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Task not found'
                ], 404);
            }

            if (!self::canViewTaskForActor($task, $userId, $userRole)) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Not authorized to view this task'
                ], 403);
            }

            return response()->json([
                'status' => 'success',
                'data' => self::decodeTask($task)
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage()
            ], 500);
        }
    }

    // Update a task
    public function update(Request $request, $id)
    {
        try {
            $actor = self::actorFromRequest($request);
            $userId = $actor['user_id'];
            $userRole = $actor['user_role'];

            if (!$userId || !$userRole) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'user_id and user_role are required'
                ], 400);
            }

            $task = DB::table('tasks')->where('id', $id)->first();

            if (!$task) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Task not found'
                ], 404);
            }

            if (!self::canEditOrDeleteTaskForActor($task, $userId, $userRole)) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Not authorized to edit this task'
                ], 403);
            }

            $validated = $request->validate([
                'title' => 'sometimes|string|max:255',
                'description' => 'nullable|string',
                'subtasks' => 'nullable|array',
                'category' => 'sometimes|in:daily,project,personal,monthly,quarterly,yearly,other',
                'priority' => 'sometimes|in:low,medium,high,critical',
                'status' => 'sometimes|in:assigned,in_progress,completed,paused,need_help,ignore,hold',
                'deadline_date' => 'nullable|date',
                'deadline_time' => 'nullable',
                'assigned_to' => 'sometimes|string',
            ]);

            $nextCategory = $validated['category'] ?? $task->category;
            $nextAssignedTo = $validated['assigned_to'] ?? $task->assigned_to;
            $creatorId = $task->created_by;
            if ($nextCategory === 'personal' && $nextAssignedTo !== $creatorId) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Personal tasks can only be assigned to self',
                ], 422);
            }

            $update = $validated;
            $isDaily = $task->category === 'daily';
            if (array_key_exists('subtasks', $update)) {
                if (!Schema::hasColumn('tasks', 'subtasks')) {
                    DB::statement('ALTER TABLE tasks ADD COLUMN subtasks JSON NULL AFTER description');
                }
                $subtasksRaw = self::getSubtasksFromRequest($request);
                $normalized = self::normalizeSubtasksForStorage($subtasksRaw);
                $update['subtasks'] = $normalized !== null && count($normalized) > 0 ? json_encode($normalized) : null;

                // For daily tasks, also upsert per-day subtask statuses for today
                if ($isDaily && $normalized !== null) {
                    $today = Carbon::today()->toDateString();
                    $now = Carbon::now();
                    foreach (array_values($normalized) as $index => $row) {
                        $status = $row['status'] ?? 'assigned';
                        $note = $row['need_help_note'] ?? null;
                        DB::table('subtask_daily_statuses')->updateOrInsert(
                            [
                                'task_id' => $task->id,
                                'subtask_index' => $index,
                                'date' => $today,
                            ],
                            [
                                'status' => $status,
                                'note' => $note,
                                'created_at' => $now,
                                'updated_at' => $now,
                            ]
                        );
                    }
                }
            }
            DB::table('tasks')->where('id', $id)->update($update);

            $updatedTask = DB::table('tasks')
                ->leftJoin('users as creator', 'tasks.created_by', '=', 'creator.id')
                ->leftJoin('users as assignee', 'tasks.assigned_to', '=', 'assignee.id')
                ->select(
                    'tasks.*',
                    'creator.name as creator_name',
                    'creator.roleId as creator_role_id',
                    'assignee.name as assignee_name',
                    'assignee.employeeCode as assignee_code'
                )
                ->where('tasks.id', $id)
                ->first();

            return response()->json([
                'status' => 'success',
                'message' => 'Task updated successfully',
                'data' => self::decodeTask($updatedTask)
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage()
            ], 500);
        }
    }

    // Delete a task
    public function destroy(Request $request, $id)
    {
        try {
            $actor = self::actorFromRequest($request);
            $userId = $actor['user_id'];
            $userRole = $actor['user_role'];

            if (!$userId || !$userRole) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'user_id and user_role are required'
                ], 400);
            }

            $task = DB::table('tasks')->where('id', $id)->first();

            if (!$task) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Task not found'
                ], 404);
            }

            if (!self::canEditOrDeleteTaskForActor($task, $userId, $userRole)) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Not authorized to delete this task'
                ], 403);
            }

            DB::table('tasks')->where('id', $id)->delete();

            return response()->json([
                'status' => 'success',
                'message' => 'Task deleted successfully'
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage()
            ], 500);
        }
    }

    // Update task status
    public function updateStatus(Request $request, $id)
    {
        try {
            $actor = self::actorFromRequest($request);
            $userId = $actor['user_id'];
            $userRole = $actor['user_role'];

            if (!$userId || !$userRole) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'user_id and user_role are required'
                ], 400);
            }

            $validated = $request->validate([
                'status' => 'required|in:assigned,in_progress,completed,paused,need_help,ignore,hold',
                'need_help_note' => 'nullable|string|max:2000',
            ]);

            $task = DB::table('tasks')->where('id', $id)->first();

            if (!$task) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Task not found'
                ], 404);
            }

            if (!self::canUpdateStatusForActor($task, $userId, $userRole)) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Not authorized to update status for this task'
                ], 403);
            }

            $update = ['status' => $validated['status']];
            $note = array_key_exists('need_help_note', $validated)
                ? ($validated['need_help_note'] ? trim($validated['need_help_note']) : null)
                : null;

            if (array_key_exists('need_help_note', $validated)) {
                $update['need_help_note'] = $note;
            }

            DB::table('tasks')->where('id', $id)->update($update);

            // For daily tasks, also write into task_daily_statuses for today
            if ($task->category === 'daily') {
                $today = Carbon::today()->toDateString();
                $now = Carbon::now();
                DB::table('task_daily_statuses')->updateOrInsert(
                    [
                        'task_id' => $task->id,
                        'date' => $today,
                    ],
                    [
                        'status' => $validated['status'],
                        'note' => $note,
                        'created_at' => $now,
                        'updated_at' => $now,
                    ]
                );
            }

            $updatedTask = DB::table('tasks')->where('id', $id)->first();

            return response()->json([
                'status' => 'success',
                'message' => 'Task status updated successfully',
                'data' => self::decodeTask($updatedTask)
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage()
            ], 500);
        }
    }

    // Move task to current work for its assignee
    public function moveToCurrent(Request $request, $id)
    {
        try {
            $actor = self::actorFromRequest($request);
            $userId = $actor['user_id'];
            $userRole = $actor['user_role'];

            if (!$userId || !$userRole) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'user_id and user_role are required'
                ], 400);
            }

            if (!Schema::hasColumn('tasks', 'is_current')) {
                DB::statement('ALTER TABLE tasks ADD COLUMN is_current TINYINT(1) NOT NULL DEFAULT 0 AFTER status');
            }

            $task = DB::table('tasks')->where('id', $id)->first();
            if (!$task) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Task not found'
                ], 404);
            }

            if (!self::canSetCurrentForActor($task, $userId, $userRole)) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Not authorized to mark current task'
                ], 403);
            }

            $assigneeId = (string) ($task->assigned_to ?? '');
            if ($assigneeId === '') {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Task has no assignee'
                ], 422);
            }

            DB::transaction(function () use ($id, $assigneeId, $task) {
                DB::table('tasks')
                    ->where('assigned_to', $assigneeId)
                    ->where('id', '!=', $id)
                    ->update(['is_current' => 0]);

                $update = ['is_current' => 1];
                if (in_array((string) $task->status, ['assigned', 'paused', 'hold'], true)) {
                    $update['status'] = 'in_progress';
                }
                DB::table('tasks')->where('id', $id)->update($update);
            });

            $updatedTask = DB::table('tasks')->where('id', $id)->first();

            return response()->json([
                'status' => 'success',
                'message' => 'Task moved to current successfully',
                'data' => self::decodeTask($updatedTask),
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage()
            ], 500);
        }
    }

    // Hide task for current actor (self-assigned tasks only)
    public function hide(Request $request, $id)
    {
        try {
            $actor = self::actorFromRequest($request);
            $userId = $actor['user_id'];
            $userRole = $actor['user_role'];

            if (!$userId || !$userRole) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'user_id and user_role are required'
                ], 400);
            }

            $task = DB::table('tasks')->where('id', $id)->first();
            if (!$task) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Task not found'
                ], 404);
            }

            if (!self::canHideTaskForActor($task, $userId)) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Only self-assigned tasks can be moved to hidden'
                ], 403);
            }

            if (!Schema::hasTable('task_hidden_items')) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Hidden tasks feature is not available yet'
                ], 500);
            }

            DB::table('task_hidden_items')->updateOrInsert(
                [
                    'task_id' => $id,
                    'hidden_by_user_id' => $userId,
                ],
                [
                    'updated_at' => Carbon::now(),
                    'created_at' => Carbon::now(),
                ]
            );

            return response()->json([
                'status' => 'success',
                'message' => 'Task moved to hidden'
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage()
            ], 500);
        }
    }

    // Unhide task for current actor
    public function unhide(Request $request, $id)
    {
        try {
            $actor = self::actorFromRequest($request);
            $userId = $actor['user_id'];
            $userRole = $actor['user_role'];

            if (!$userId || !$userRole) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'user_id and user_role are required'
                ], 400);
            }

            if (!Schema::hasTable('task_hidden_items')) {
                return response()->json([
                    'status' => 'success',
                    'message' => 'Task restored successfully'
                ]);
            }

            DB::table('task_hidden_items')
                ->where('task_id', $id)
                ->where('hidden_by_user_id', $userId)
                ->delete();

            return response()->json([
                'status' => 'success',
                'message' => 'Task restored successfully'
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage()
            ], 500);
        }
    }
}
