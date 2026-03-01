<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class TaskController extends Controller
{
    // Get all tasks (filtered by user role)
    public function index(Request $request)
    {
        try {
            $userId = $request->query('user_id');
            $userRole = $request->query('user_role'); // 'admin' or 'employee'

            if (!$userId || !$userRole) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'user_id and user_role are required'
                ], 400);
            }

            if ($userRole === 'admin') {
                // Admin sees: ALL project tasks + their own personal tasks
                $tasks = DB::table('tasks')
                    ->leftJoin('users as creator', 'tasks.created_by', '=', 'creator.id')
                    ->leftJoin('users as assignee', 'tasks.assigned_to', '=', 'assignee.id')
                    ->select(
                        'tasks.*',
                        'creator.name as creator_name',
                        'assignee.name as assignee_name',
                        'assignee.employeeCode as assignee_code'
                    )
                    ->where(function ($query) use ($userId) {
                        $query->where('tasks.category', 'project')
                            ->orWhere('tasks.created_by', $userId);
                    })
                    ->orderBy('tasks.createdAt', 'desc')
                    ->get();
            } else {
                // Employee sees: only their own tasks
                $tasks = DB::table('tasks')
                    ->leftJoin('users as creator', 'tasks.created_by', '=', 'creator.id')
                    ->leftJoin('users as assignee', 'tasks.assigned_to', '=', 'assignee.id')
                    ->select(
                        'tasks.*',
                        'creator.name as creator_name',
                        'assignee.name as assignee_name'
                    )
                    ->where('tasks.assigned_to', $userId)
                    ->orderBy('tasks.createdAt', 'desc')
                    ->get();
            }

            return response()->json([
                'status' => 'success',
                'data' => $tasks
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
                'category' => 'required|in:daily,project,personal,monthly,quarterly,yearly,other',
                'priority' => 'required|in:low,medium,high,critical',
                'deadline_date' => 'nullable|date',
                'deadline_time' => 'nullable',
                'created_by' => 'required|string',
                'assigned_to' => 'required|string',
            ]);

            // Ensure creator and assignee users exist to satisfy FK constraints
            $creatorId = $validated['created_by'];
            $assigneeId = $validated['assigned_to'];

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

            DB::table('tasks')->insert([
                'id' => $taskId,
                'title' => $validated['title'],
                'description' => $validated['description'] ?? null,
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
                'data' => $task
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
    public function show($id)
    {
        try {
            $task = DB::table('tasks')
                ->leftJoin('users as creator', 'tasks.created_by', '=', 'creator.id')
                ->leftJoin('users as assignee', 'tasks.assigned_to', '=', 'assignee.id')
                ->select(
                    'tasks.*',
                    'creator.name as creator_name',
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

            return response()->json([
                'status' => 'success',
                'data' => $task
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
            $task = DB::table('tasks')->where('id', $id)->first();

            if (!$task) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Task not found'
                ], 404);
            }

            $validated = $request->validate([
                'title' => 'sometimes|string|max:255',
                'description' => 'nullable|string',
                'category' => 'sometimes|in:daily,project,personal,monthly,quarterly,yearly,other',
                'priority' => 'sometimes|in:low,medium,high,critical',
                'status' => 'sometimes|in:assigned,in_progress,completed,paused,need_help',
                'deadline_date' => 'nullable|date',
                'deadline_time' => 'nullable',
                'assigned_to' => 'sometimes|string',
            ]);

            DB::table('tasks')->where('id', $id)->update($validated);

            $updatedTask = DB::table('tasks')->where('id', $id)->first();

            return response()->json([
                'status' => 'success',
                'message' => 'Task updated successfully',
                'data' => $updatedTask
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage()
            ], 500);
        }
    }

    // Delete a task
    public function destroy($id)
    {
        try {
            $task = DB::table('tasks')->where('id', $id)->first();

            if (!$task) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Task not found'
                ], 404);
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
            $validated = $request->validate([
                'status' => 'required|in:assigned,in_progress,completed,paused,need_help',
            ]);

            $task = DB::table('tasks')->where('id', $id)->first();

            if (!$task) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Task not found'
                ], 404);
            }

            DB::table('tasks')->where('id', $id)->update([
                'status' => $validated['status']
            ]);

            $updatedTask = DB::table('tasks')->where('id', $id)->first();

            return response()->json([
                'status' => 'success',
                'message' => 'Task status updated successfully',
                'data' => $updatedTask
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage()
            ], 500);
        }
    }
}
