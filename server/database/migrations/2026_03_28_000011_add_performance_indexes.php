<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    private function hasIndex(string $table, string $indexName): bool
    {
        $row = DB::selectOne(
            "SELECT 1 AS found FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = ? AND index_name = ? LIMIT 1",
            [$table, $indexName]
        );

        return $row !== null;
    }

    private function addIndexIfMissing(string $table, string $indexName, string $columns): void
    {
        if (!Schema::hasTable($table) || $this->hasIndex($table, $indexName)) {
            return;
        }

        DB::statement("ALTER TABLE {$table} ADD INDEX {$indexName} ({$columns})");
    }

    private function dropIndexIfExists(string $table, string $indexName): void
    {
        if (!Schema::hasTable($table) || !$this->hasIndex($table, $indexName)) {
            return;
        }

        DB::statement("ALTER TABLE {$table} DROP INDEX {$indexName}");
    }

    public function up(): void
    {
        $this->addIndexIfMissing('tasks', 'idx_tasks_created_by', 'created_by');
        $this->addIndexIfMissing('tasks', 'idx_tasks_status_created_at', 'status, createdAt');
        $this->addIndexIfMissing('tasks', 'idx_tasks_category_created_at', 'category, createdAt');
        $this->addIndexIfMissing('tasks', 'idx_tasks_creator_assignee_created_at', 'created_by, assigned_to, createdAt');

        $this->addIndexIfMissing('attendances', 'idx_attendances_date_user', 'date, user_id');
        $this->addIndexIfMissing('attendance_breaks', 'idx_breaks_attendance_end_time', 'attendance_id, end_time');

        $this->addIndexIfMissing('notifications', 'idx_notifications_employee_created', 'employee_id, created_at');
        $this->addIndexIfMissing('notifications', 'idx_notifications_employee_read_created', 'employee_id, is_read, created_at');
    }

    public function down(): void
    {
        $this->dropIndexIfExists('notifications', 'idx_notifications_employee_read_created');
        $this->dropIndexIfExists('notifications', 'idx_notifications_employee_created');

        $this->dropIndexIfExists('attendance_breaks', 'idx_breaks_attendance_end_time');
        $this->dropIndexIfExists('attendances', 'idx_attendances_date_user');

        $this->dropIndexIfExists('tasks', 'idx_tasks_creator_assignee_created_at');
        $this->dropIndexIfExists('tasks', 'idx_tasks_category_created_at');
        $this->dropIndexIfExists('tasks', 'idx_tasks_status_created_at');
        $this->dropIndexIfExists('tasks', 'idx_tasks_created_by');
    }
};
