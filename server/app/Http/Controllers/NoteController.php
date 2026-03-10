<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class NoteController extends Controller
{
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

