<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schedule;
use Illuminate\Support\Facades\Schema;
use Carbon\Carbon;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

Artisan::command('tasks:seed-daily-statuses', function () {
    // Ensure supporting tables exist so the command is safe to run
    if (
        !Schema::hasTable('task_daily_statuses') ||
        !Schema::hasTable('subtask_daily_statuses')
    ) {
        $this->warn('Daily status tables are missing; run migrations first.');
        return;
    }

    $today = Carbon::today()->toDateString();
    $now = Carbon::now();

    $dailyTasks = DB::table('tasks')
        ->where('category', 'daily')
        ->get();

    foreach ($dailyTasks as $task) {
        // Seed task-level daily status (default assigned / no note) only when missing.
        // Use insertOrIgnore so existing rows (possibly updated during the day)
        // are never overwritten by the seeder.
        DB::table('task_daily_statuses')->insertOrIgnore([
            'task_id' => $task->id,
            'date' => $today,
            'status' => 'assigned',
            'note' => null,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        // Seed subtask-level daily status for each subtask index only when missing.
        if (!empty($task->subtasks)) {
            $subtasks = json_decode($task->subtasks, true) ?: [];
            foreach (array_values($subtasks) as $index => $subtask) {
                DB::table('subtask_daily_statuses')->insertOrIgnore([
                    'task_id' => $task->id,
                    'subtask_index' => $index,
                    'date' => $today,
                    'status' => 'assigned',
                    'note' => null,
                    'created_at' => $now,
                    'updated_at' => $now,
                ]);
            }
        }
    }

    $this->info('Daily statuses seeded for ' . $today);
})->purpose('Seed today\'s daily status rows for all daily tasks and their subtasks');

// Schedule the seeding command to run every day at midnight
Schedule::command('tasks:seed-daily-statuses')->dailyAt('00:05');
