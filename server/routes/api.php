<?php

use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\DB;
use App\Http\Controllers\UserController;
use App\Http\Controllers\RoleController;
use App\Http\Controllers\DepartmentController;
use App\Http\Controllers\TaskController;
use App\Http\Controllers\NoteController;
use App\Http\Controllers\AttendanceController;
use App\Http\Controllers\DashboardController;
use App\Http\Controllers\NotificationController;
use App\Http\Controllers\ChatController;

Route::get('/health', function () {
    return response()->json([
        'status' => 'OK',
        'message' => 'API Working'
    ]);
});

Route::get('/db-test', function () {
    try {
        // Try simple query
        $result = DB::select('SELECT 1 as test');

        return response()->json([
            'status' => 'success',
            'database' => 'Connected',
            'result' => $result
        ]);
    } catch (\Exception $e) {
        return response()->json([
            'status' => 'error',
            'database' => 'Not Connected',
            'message' => $e->getMessage()
        ], 500);
    }
});

// User Routes
Route::get('/users', [UserController::class, 'index']);
Route::get('/users/by-contact/{contactNumber}', [UserController::class, 'showByContact']);
Route::get('/roles', [RoleController::class, 'index']);
Route::get('/departments', [DepartmentController::class, 'index']);

// Task Routes
Route::get('/tasks', [TaskController::class, 'index']);
Route::post('/tasks', [TaskController::class, 'store']);
Route::get('/tasks/{id}', [TaskController::class, 'show']);
Route::put('/tasks/{id}', [TaskController::class, 'update']);
Route::delete('/tasks/{id}', [TaskController::class, 'destroy']);
Route::patch('/tasks/{id}/status', [TaskController::class, 'updateStatus']);

// Notes Routes (list + CRUD; /me routes kept for backward compatibility)
Route::middleware('chat.actor')->group(function () {
    Route::get('/notes', [NoteController::class, 'index']);
    Route::post('/notes', [NoteController::class, 'store']);
    Route::get('/notes/me', [NoteController::class, 'showMe']);
    Route::put('/notes/me', [NoteController::class, 'upsertMe']);
    Route::get('/notes/{id}', [NoteController::class, 'show']);
    Route::put('/notes/{id}', [NoteController::class, 'update']);
    Route::delete('/notes/{id}', [NoteController::class, 'destroy']);
});

// Attendance Routes
Route::get('/attendance/today', [AttendanceController::class, 'today']);
Route::get('/attendance/overview', [AttendanceController::class, 'overview']);
Route::post('/attendance/punch-in', [AttendanceController::class, 'punchIn']);
Route::post('/attendance/punch-out', [AttendanceController::class, 'punchOut']);
Route::post('/attendance/break/start', [AttendanceController::class, 'startBreak']);
Route::post('/attendance/break/end', [AttendanceController::class, 'endBreak']);

// Dashboard summary
Route::get('/dashboard/summary', [DashboardController::class, 'summary']);

// Notification Routes
Route::get('/notifications', [NotificationController::class, 'index']);
Route::post('/notifications', [NotificationController::class, 'store']);
Route::patch('/notifications/{id}/read', [NotificationController::class, 'markRead']);

// Chat Routes
Route::middleware('chat.actor')->group(function () {
    Route::post('/chat/realtime/auth', [ChatController::class, 'authorizeRealtime']);
    Route::get('/chat/threads', [ChatController::class, 'listThreads']);
    Route::post('/chat/threads/direct', [ChatController::class, 'openDirectThread']);
    Route::post('/chat/threads/broadcast', [ChatController::class, 'openBroadcastThread']);
    Route::get('/chat/threads/{id}/messages', [ChatController::class, 'listMessages']);
    Route::post('/chat/threads/{id}/messages', [ChatController::class, 'sendMessage']);
    Route::post('/chat/threads/{id}/receipts', [ChatController::class, 'updateReceipts']);
    Route::post('/chat/threads/{id}/read', [ChatController::class, 'markThreadRead']);
    Route::post('/chat/threads/{id}/messages/{messageId}/delivered', [ChatController::class, 'markMessageDelivered']);
    Route::post('/chat/threads/{id}/messages/{messageId}/seen', [ChatController::class, 'markMessageSeen']);
    Route::get('/chat/threads/{id}/messages/{messageId}/reactions', [ChatController::class, 'listMessageReactions']);
    Route::post('/chat/threads/{id}/messages/{messageId}/reactions', [ChatController::class, 'addMessageReaction']);
    Route::delete('/chat/threads/{id}/messages/{messageId}/reactions', [ChatController::class, 'removeMessageReaction']);
    Route::post('/chat/threads/{id}/typing', [ChatController::class, 'updateTypingStatus']);
    Route::post('/chat/presence', [ChatController::class, 'upsertPresence']);
});
