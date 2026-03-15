<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    /**
     * Run the migrations.
     * Allow multiple notes per user; add folder_name and title.
     * Idempotent: safe to run if columns or index were already changed.
     */
    public function up(): void
    {
        // Add new columns only if they don't exist
        if (!Schema::hasColumn('notes', 'folder_name')) {
            DB::statement('ALTER TABLE notes ADD COLUMN folder_name VARCHAR(255) NULL AFTER user_id');
        }
        if (!Schema::hasColumn('notes', 'title')) {
            DB::statement('ALTER TABLE notes ADD COLUMN title VARCHAR(255) NULL AFTER folder_name');
        }

        // Migrate existing single-note rows to default folder/title
        DB::table('notes')->whereNull('folder_name')->update([
            'folder_name' => 'General',
            'title' => 'My note',
        ]);

        // Drop unique constraint so user can have multiple notes.
        // The unique index is used by the FK on user_id; we must drop FK first, then replace with non-unique index, then re-add FK.
        $indexes = DB::select("SHOW INDEX FROM notes WHERE Key_name = 'notes_user_id_unique'");
        if (!empty($indexes)) {
            $fkName = DB::selectOne("
                SELECT CONSTRAINT_NAME AS name
                FROM information_schema.KEY_COLUMN_USAGE
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = 'notes'
                  AND REFERENCED_TABLE_NAME = 'users'
                  AND COLUMN_NAME = 'user_id'
            ");
            if ($fkName && !empty($fkName->name)) {
                DB::statement("ALTER TABLE notes DROP FOREIGN KEY " . $fkName->name);
            }
            DB::statement('ALTER TABLE notes DROP INDEX notes_user_id_unique');
            DB::statement('ALTER TABLE notes ADD INDEX notes_user_id_index (user_id)');
            if ($fkName && !empty($fkName->name)) {
                DB::statement('ALTER TABLE notes ADD CONSTRAINT notes_user_id_foreign FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE');
            }
        }
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        DB::statement('ALTER TABLE notes DROP COLUMN folder_name');
        DB::statement('ALTER TABLE notes DROP COLUMN title');
        DB::statement('ALTER TABLE notes ADD UNIQUE KEY notes_user_id_unique (user_id)');
    }
};
