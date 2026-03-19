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
        if (!Schema::hasColumn('chat_messages', 'sent_at')) {
            DB::statement('ALTER TABLE chat_messages ADD COLUMN sent_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP');
        }

        if (!Schema::hasColumn('chat_messages', 'delivered_at')) {
            DB::statement('ALTER TABLE chat_messages ADD COLUMN delivered_at DATETIME NULL');
        }

        if (!Schema::hasColumn('chat_messages', 'seen_at')) {
            DB::statement('ALTER TABLE chat_messages ADD COLUMN seen_at DATETIME NULL');
        }

        if (!Schema::hasColumn('chat_messages', 'edited_at')) {
            DB::statement('ALTER TABLE chat_messages ADD COLUMN edited_at DATETIME NULL');
        }

        if (!Schema::hasColumn('chat_messages', 'is_deleted')) {
            DB::statement('ALTER TABLE chat_messages ADD COLUMN is_deleted BOOLEAN NOT NULL DEFAULT FALSE');
        }

        $indexExists = DB::table('information_schema.statistics')
            ->where('table_schema', DB::getDatabaseName())
            ->where('table_name', 'chat_messages')
            ->where('index_name', 'chat_messages_delivery_index')
            ->exists();

        if (!$indexExists) {
            DB::statement('ALTER TABLE chat_messages ADD INDEX chat_messages_delivery_index (thread_id, delivered_at, seen_at)');
        }

        if (!Schema::hasTable('chat_message_reactions')) {
            DB::statement("CREATE TABLE chat_message_reactions (
                id VARCHAR(191) PRIMARY KEY,
                message_id VARCHAR(191) NOT NULL,
                user_id VARCHAR(191) NOT NULL,
                emoji VARCHAR(32) NOT NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (message_id) REFERENCES chat_messages(id) ON DELETE CASCADE,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                UNIQUE KEY chat_message_reactions_unique (message_id, user_id, emoji),
                INDEX chat_message_reactions_message_index (message_id),
                INDEX chat_message_reactions_user_index (user_id)
            )");
        }

        // Presence is lightweight and optional; persistent fallback is useful when cache is not distributed.
        if (!Schema::hasTable('user_presences')) {
            DB::statement("CREATE TABLE user_presences (
                user_id VARCHAR(191) PRIMARY KEY,
                is_online BOOLEAN NOT NULL DEFAULT FALSE,
                last_seen_at DATETIME NULL,
                updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                INDEX user_presences_online_index (is_online),
                INDEX user_presences_last_seen_index (last_seen_at)
            )");
        }
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        if (Schema::hasTable('user_presences')) {
            DB::statement('DROP TABLE user_presences');
        }

        if (Schema::hasTable('chat_message_reactions')) {
            DB::statement('DROP TABLE chat_message_reactions');
        }

        $indexExists = DB::table('information_schema.statistics')
            ->where('table_schema', DB::getDatabaseName())
            ->where('table_name', 'chat_messages')
            ->where('index_name', 'chat_messages_delivery_index')
            ->exists();

        if ($indexExists) {
            DB::statement('ALTER TABLE chat_messages DROP INDEX chat_messages_delivery_index');
        }

        if (Schema::hasColumn('chat_messages', 'is_deleted')) {
            DB::statement('ALTER TABLE chat_messages DROP COLUMN is_deleted');
        }

        if (Schema::hasColumn('chat_messages', 'edited_at')) {
            DB::statement('ALTER TABLE chat_messages DROP COLUMN edited_at');
        }

        if (Schema::hasColumn('chat_messages', 'seen_at')) {
            DB::statement('ALTER TABLE chat_messages DROP COLUMN seen_at');
        }

        if (Schema::hasColumn('chat_messages', 'delivered_at')) {
            DB::statement('ALTER TABLE chat_messages DROP COLUMN delivered_at');
        }

        if (Schema::hasColumn('chat_messages', 'sent_at')) {
            DB::statement('ALTER TABLE chat_messages DROP COLUMN sent_at');
        }
    }
};
