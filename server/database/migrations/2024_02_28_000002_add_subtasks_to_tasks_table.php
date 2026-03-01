<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration {
    /**
     * Run the migrations.
     * Add subtasks column (JSON array of strings) so description and subtasks are separate.
     */
    public function up(): void
    {
        DB::statement('ALTER TABLE tasks ADD COLUMN subtasks JSON NULL AFTER description');
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        DB::statement('ALTER TABLE tasks DROP COLUMN subtasks');
    }
};
