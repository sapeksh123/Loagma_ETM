<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        if (!Schema::hasColumn('tasks', 'alarm_enabled')) {
            DB::statement("ALTER TABLE tasks ADD COLUMN alarm_enabled TINYINT(1) NOT NULL DEFAULT 0 AFTER deadline_time");
        }
        if (!Schema::hasColumn('tasks', 'alarm_time')) {
            DB::statement("ALTER TABLE tasks ADD COLUMN alarm_time TIME NULL AFTER alarm_enabled");
        }
        if (!Schema::hasColumn('tasks', 'alarm_pattern')) {
            DB::statement("ALTER TABLE tasks ADD COLUMN alarm_pattern VARCHAR(20) NULL AFTER alarm_time");
        }
        if (!Schema::hasColumn('tasks', 'alarm_start_date')) {
            DB::statement("ALTER TABLE tasks ADD COLUMN alarm_start_date DATE NULL AFTER alarm_pattern");
        }
        if (!Schema::hasColumn('tasks', 'alarm_end_date')) {
            DB::statement("ALTER TABLE tasks ADD COLUMN alarm_end_date DATE NULL AFTER alarm_start_date");
        }
        if (!Schema::hasColumn('tasks', 'alarm_timezone')) {
            DB::statement("ALTER TABLE tasks ADD COLUMN alarm_timezone VARCHAR(120) NULL AFTER alarm_end_date");
        }
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        if (Schema::hasColumn('tasks', 'alarm_timezone')) {
            DB::statement('ALTER TABLE tasks DROP COLUMN alarm_timezone');
        }
        if (Schema::hasColumn('tasks', 'alarm_end_date')) {
            DB::statement('ALTER TABLE tasks DROP COLUMN alarm_end_date');
        }
        if (Schema::hasColumn('tasks', 'alarm_start_date')) {
            DB::statement('ALTER TABLE tasks DROP COLUMN alarm_start_date');
        }
        if (Schema::hasColumn('tasks', 'alarm_pattern')) {
            DB::statement('ALTER TABLE tasks DROP COLUMN alarm_pattern');
        }
        if (Schema::hasColumn('tasks', 'alarm_time')) {
            DB::statement('ALTER TABLE tasks DROP COLUMN alarm_time');
        }
        if (Schema::hasColumn('tasks', 'alarm_enabled')) {
            DB::statement('ALTER TABLE tasks DROP COLUMN alarm_enabled');
        }
    }
};
