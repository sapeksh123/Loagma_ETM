<?php

namespace App\Http\Controllers;

use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class DashboardController extends Controller
{
    /**
     * Simple summary stats for the admin dashboard.
     */
    public function summary(Request $request)
    {
        try {
            $now = Carbon::now('Asia/Kolkata');
            $today = $now->toDateString();

            // Employees
            $totalEmployees = DB::table('users')->count();
            $activeEmployees = DB::table('users')
                ->where('isActive', 1)
                ->count();

            // Tasks: treat everything not completed as pending.
            $pendingTasks = DB::table('tasks')
                ->where('status', '!=', 'completed')
                ->count();

            // Attendance today
            $presentToday = DB::table('attendances')
                ->where('date', $today)
                ->count();

            $absentToday = max(0, $totalEmployees - $presentToday);

            return response()->json([
                'status' => 'success',
                'data' => [
                    'employees_total' => $totalEmployees,
                    'employees_active' => $activeEmployees,
                    'tasks_pending' => $pendingTasks,
                    'present_today' => $presentToday,
                    'absent_today' => $absentToday,
                ],
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }
}

