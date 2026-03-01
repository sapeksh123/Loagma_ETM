<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration {
    /**
     * Run the migrations.
     * Change task categories: remove 'family', add 'monthly', 'quarterly', 'yearly'.
     */
    public function up(): void
    {
        // Migrate existing 'family' tasks to 'other' before changing ENUM
        DB::table('tasks')->where('category', 'family')->update(['category' => 'other']);

        DB::statement("
            ALTER TABLE tasks
            MODIFY COLUMN category ENUM('daily', 'project', 'personal', 'monthly', 'quarterly', 'yearly', 'other') NOT NULL
        ");
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        // Move monthly/quarterly/yearly back to 'other' before reverting ENUM
        DB::table('tasks')
            ->whereIn('category', ['monthly', 'quarterly', 'yearly'])
            ->update(['category' => 'other']);

        DB::statement("
            ALTER TABLE tasks
            MODIFY COLUMN category ENUM('daily', 'project', 'personal', 'family', 'other') NOT NULL
        ");
    }
};
