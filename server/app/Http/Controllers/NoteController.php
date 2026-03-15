<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class NoteController extends Controller
{
    /**
     * List all notes for a user (query user_id).
     */
    public function index(Request $request)
    {
        try {
            $userId = $request->query('user_id');
            if (!$userId) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'user_id is required',
                ], 400);
            }

            $notes = DB::table('notes')
                ->where('user_id', $userId)
                ->orderBy('folder_name')
                ->orderBy('updatedAt', 'desc')
                ->get();

            $data = $notes->map(function ($note) {
                return [
                    'id' => $note->id,
                    'user_id' => $note->user_id,
                    'folder_name' => $note->folder_name ?? '',
                    'title' => $note->title ?? '',
                    'content' => $note->content ?? '',
                    'createdAt' => $note->createdAt,
                    'updatedAt' => $note->updatedAt,
                ];
            })->values()->all();

            return response()->json([
                'status' => 'success',
                'data' => $data,
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Get one note by id (ownership by user_id in query).
     */
    public function show(Request $request, string $id)
    {
        try {
            $userId = $request->query('user_id');
            if (!$userId) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'user_id is required',
                ], 400);
            }

            $note = DB::table('notes')
                ->where('id', $id)
                ->where('user_id', $userId)
                ->first();

            if (!$note) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Note not found',
                ], 404);
            }

            $data = [
                'id' => $note->id,
                'user_id' => $note->user_id,
                'folder_name' => $note->folder_name ?? '',
                'title' => $note->title ?? '',
                'content' => $note->content ?? '',
                'createdAt' => $note->createdAt,
                'updatedAt' => $note->updatedAt,
            ];

            return response()->json([
                'status' => 'success',
                'data' => $data,
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Create a new note.
     */
    public function store(Request $request)
    {
        try {
            $validated = $request->validate([
                'user_id' => 'required|string',
                'folder_name' => 'required|string|max:255',
                'title' => 'required|string|max:255',
                'content' => 'nullable|string',
            ]);

            $noteId = Str::uuid()->toString();
            DB::table('notes')->insert([
                'id' => $noteId,
                'user_id' => $validated['user_id'],
                'folder_name' => $validated['folder_name'],
                'title' => $validated['title'],
                'content' => $validated['content'] ?? null,
                'createdAt' => now(),
                'updatedAt' => now(),
            ]);

            $note = DB::table('notes')->where('id', $noteId)->first();
            $data = [
                'id' => $note->id,
                'user_id' => $note->user_id,
                'folder_name' => $note->folder_name ?? '',
                'title' => $note->title ?? '',
                'content' => $note->content ?? '',
                'createdAt' => $note->createdAt,
                'updatedAt' => $note->updatedAt,
            ];

            return response()->json([
                'status' => 'success',
                'message' => 'Note created',
                'data' => $data,
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
     * Update a note (partial: folder_name, title, content).
     */
    public function update(Request $request, string $id)
    {
        try {
            $userId = $request->query('user_id');
            if (!$userId) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'user_id is required',
                ], 400);
            }

            $validated = $request->validate([
                'folder_name' => 'sometimes|string|max:255',
                'title' => 'sometimes|string|max:255',
                'content' => 'nullable|string',
            ]);

            $updated = DB::table('notes')
                ->where('id', $id)
                ->where('user_id', $userId)
                ->update(array_merge($validated, ['updatedAt' => now()]));

            if ($updated === 0) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Note not found',
                ], 404);
            }

            $note = DB::table('notes')->where('id', $id)->first();
            $data = [
                'id' => $note->id,
                'user_id' => $note->user_id,
                'folder_name' => $note->folder_name ?? '',
                'title' => $note->title ?? '',
                'content' => $note->content ?? '',
                'createdAt' => $note->createdAt,
                'updatedAt' => $note->updatedAt,
            ];

            return response()->json([
                'status' => 'success',
                'message' => 'Note updated',
                'data' => $data,
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
     * Delete a note.
     */
    public function destroy(Request $request, string $id)
    {
        try {
            $userId = $request->query('user_id');
            if (!$userId) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'user_id is required',
                ], 400);
            }

            $deleted = DB::table('notes')
                ->where('id', $id)
                ->where('user_id', $userId)
                ->delete();

            if ($deleted === 0) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Note not found',
                ], 404);
            }

            return response()->json([
                'status' => 'success',
                'message' => 'Note deleted',
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Get the current user's note (by user_id query param).
     */
    public function showMe(Request $request)
    {
        try {
            $userId = $request->query('user_id');

            if (!$userId) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'user_id is required',
                ], 400);
            }

            $note = DB::table('notes')->where('user_id', $userId)->first();

            $data = [
                'user_id' => $userId,
                'content' => $note ? (string) ($note->content ?? '') : '',
                'updatedAt' => $note ? $note->updatedAt : null,
            ];

            return response()->json([
                'status' => 'success',
                'data' => $data,
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Create or update the current user's note.
     */
    public function upsertMe(Request $request)
    {
        try {
            $validated = $request->validate([
                'user_id' => 'required|string',
                'content' => 'nullable|string',
            ]);

            $userId = $validated['user_id'];
            $content = array_key_exists('content', $validated) ? $validated['content'] : null;

            $existing = DB::table('notes')->where('user_id', $userId)->first();

            if ($existing) {
                DB::table('notes')
                    ->where('user_id', $userId)
                    ->update([
                        'content' => $content,
                        'updatedAt' => now(),
                    ]);
                $noteId = $existing->id;
            } else {
                $noteId = Str::uuid()->toString();
                DB::table('notes')->insert([
                    'id' => $noteId,
                    'user_id' => $userId,
                    'content' => $content,
                    'createdAt' => now(),
                    'updatedAt' => now(),
                ]);
            }

            $note = DB::table('notes')->where('id', $noteId)->first();

            return response()->json([
                'status' => 'success',
                'message' => 'Note saved',
                'data' => [
                    'id' => $note->id,
                    'user_id' => $note->user_id,
                    'content' => $note->content,
                    'updatedAt' => $note->updatedAt,
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
}

