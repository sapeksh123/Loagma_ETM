<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration {
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        // TiDB/MySQL variant: add columns in two separate statements so that
        // the second ALTER does not reference a column that does not yet exist.
        DB::statement("
            ALTER TABLE notifications
            ADD COLUMN chat_thread_id VARCHAR(191) NULL AFTER task_id
        ");

        DB::statement("
            ALTER TABLE notifications
            ADD COLUMN chat_message_id VARCHAR(191) NULL AFTER chat_thread_id
        ");
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        DB::statement("
            ALTER TABLE notifications
            DROP COLUMN chat_message_id,
            DROP COLUMN chat_thread_id
        ");
    }
};

