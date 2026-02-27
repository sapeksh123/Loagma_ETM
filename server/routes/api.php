<?php

use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\DB;
use App\Http\Controllers\UserController;
use App\Http\Controllers\RoleController;
use App\Http\Controllers\DepartmentController;
use App\Http\Controllers\TaskController;
use App\Http\Controllers\AttendanceController;

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
Route::get('/roles', [RoleController::class, 'index']);
Route::get('/departments', [DepartmentController::class, 'index']);

// Task Routes
Route::get('/tasks', [TaskController::class, 'index']);
Route::post('/tasks', [TaskController::class, 'store']);
Route::get('/tasks/{id}', [TaskController::class, 'show']);
Route::put('/tasks/{id}', [TaskController::class, 'update']);
Route::delete('/tasks/{id}', [TaskController::class, 'destroy']);
Route::patch('/tasks/{id}/status', [TaskController::class, 'updateStatus']);

// Attendance Routes
Route::get('/attendance/today', [AttendanceController::class, 'today']);
Route::post('/attendance/punch-in', [AttendanceController::class, 'punchIn']);
Route::post('/attendance/punch-out', [AttendanceController::class, 'punchOut']);
Route::post('/attendance/break/start', [AttendanceController::class, 'startBreak']);
Route::post('/attendance/break/end', [AttendanceController::class, 'endBreak']);