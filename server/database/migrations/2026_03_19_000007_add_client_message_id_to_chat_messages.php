<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        if (!Schema::hasColumn('chat_messages', 'client_message_id')) {
            DB::statement('ALTER TABLE chat_messages ADD COLUMN client_message_id VARCHAR(191) NULL');
        }

        $indexExists = DB::table('information_schema.statistics')
            ->where('table_schema', DB::getDatabaseName())
            ->where('table_name', 'chat_messages')
            ->where('index_name', 'chat_messages_client_message_unique')
            ->exists();

        if (!$indexExists) {
            DB::statement('ALTER TABLE chat_messages ADD UNIQUE INDEX chat_messages_client_message_unique (thread_id, sender_id, client_message_id)');
        }
    }

    public function down(): void
    {
        $indexExists = DB::table('information_schema.statistics')
            ->where('table_schema', DB::getDatabaseName())
            ->where('table_name', 'chat_messages')
            ->where('index_name', 'chat_messages_client_message_unique')
            ->exists();

        if ($indexExists) {
            DB::statement('ALTER TABLE chat_messages DROP INDEX chat_messages_client_message_unique');
        }

        if (Schema::hasColumn('chat_messages', 'client_message_id')) {
            DB::statement('ALTER TABLE chat_messages DROP COLUMN client_message_id');
        }
    }
};
