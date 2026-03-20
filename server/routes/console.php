<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schedule;
use Illuminate\Support\Facades\Schema;
use Carbon\Carbon;
use Symfony\Component\Process\Process;

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

Artisan::command('chat:serve {--host=127.0.0.1} {--port=8000}', function () {
    $php = PHP_BINARY;
    $host = (string) $this->option('host');
    $port = (string) $this->option('port');

    $this->info('Starting chat stack in one command...');
    $this->line("API: http://{$host}:{$port}");
    $this->line('Queue: queue:work');
    $this->line('Realtime: reverb:start');
    $this->newLine();

    $processes = [
        'api' => new Process([$php, 'artisan', 'serve', "--host={$host}", "--port={$port}"], base_path()),
        'queue' => new Process([$php, 'artisan', 'queue:work', '--sleep=1', '--tries=1'], base_path()),
        'reverb' => new Process([$php, 'artisan', 'reverb:start'], base_path()),
    ];

    foreach ($processes as $name => $process) {
        $process->setTimeout(null);
        $process->start(function (string $type, string $output) use ($name) {
            $tag = strtoupper($name);
            $text = trim($output);
            if ($text === '') {
                return;
            }

            foreach (preg_split('/\r\n|\r|\n/', $text) as $line) {
                if ($line === '') {
                    continue;
                }
                $this->line("[{$tag}] {$line}");
            }
        });
    }

    $this->newLine();
    $this->warn('Press Ctrl+C to stop all services.');

    try {
        while (true) {
            foreach ($processes as $name => $process) {
                if (!$process->isRunning()) {
                    $this->error("{$name} stopped unexpectedly (exit code: {$process->getExitCode()}). Stopping all services...");
                    return;
                }
            }
            usleep(250000);
        }
    } finally {
        foreach ($processes as $process) {
            if ($process->isRunning()) {
                $process->stop(2);
            }
        }
    }
})->purpose('Start API server, queue worker, and Reverb with one command');
