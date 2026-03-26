<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        if (Schema::hasTable('tasks') && !Schema::hasColumn('tasks', 'is_current')) {
            DB::statement("ALTER TABLE tasks ADD COLUMN is_current TINYINT(1) NOT NULL DEFAULT 0 AFTER status");
            DB::statement("CREATE INDEX idx_tasks_assigned_current ON tasks (assigned_to, is_current)");
        }

        if (Schema::hasTable('tasks') && Schema::hasColumn('tasks', 'status')) {
            DB::statement("ALTER TABLE tasks MODIFY COLUMN status ENUM('assigned', 'in_progress', 'completed', 'paused', 'need_help', 'ignore', 'hold') NOT NULL DEFAULT 'assigned'");
        }

        if (Schema::hasTable('task_daily_statuses') && Schema::hasColumn('task_daily_statuses', 'status')) {
            DB::statement("ALTER TABLE task_daily_statuses MODIFY COLUMN status ENUM('assigned', 'in_progress', 'completed', 'paused', 'need_help', 'ignore', 'hold') NOT NULL DEFAULT 'assigned'");
        }

        if (Schema::hasTable('subtask_daily_statuses') && Schema::hasColumn('subtask_daily_statuses', 'status')) {
            DB::statement("ALTER TABLE subtask_daily_statuses MODIFY COLUMN status ENUM('assigned', 'in_progress', 'completed', 'paused', 'need_help', 'ignore', 'hold') NOT NULL DEFAULT 'assigned'");
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('subtask_daily_statuses') && Schema::hasColumn('subtask_daily_statuses', 'status')) {
            DB::statement("ALTER TABLE subtask_daily_statuses MODIFY COLUMN status ENUM('assigned', 'in_progress', 'completed', 'paused', 'need_help', 'ignore') NOT NULL DEFAULT 'assigned'");
        }

        if (Schema::hasTable('task_daily_statuses') && Schema::hasColumn('task_daily_statuses', 'status')) {
            DB::statement("ALTER TABLE task_daily_statuses MODIFY COLUMN status ENUM('assigned', 'in_progress', 'completed', 'paused', 'need_help', 'ignore') NOT NULL DEFAULT 'assigned'");
        }

        if (Schema::hasTable('tasks') && Schema::hasColumn('tasks', 'status')) {
            DB::statement("ALTER TABLE tasks MODIFY COLUMN status ENUM('assigned', 'in_progress', 'completed', 'paused', 'need_help', 'ignore') NOT NULL DEFAULT 'assigned'");
        }

        if (Schema::hasTable('tasks') && Schema::hasColumn('tasks', 'is_current')) {
            DB::statement("DROP INDEX idx_tasks_assigned_current ON tasks");
            DB::statement("ALTER TABLE tasks DROP COLUMN is_current");
        }
    }
};
