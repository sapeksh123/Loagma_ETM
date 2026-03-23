<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('chat_messages', function (Blueprint $table) {
            if (!Schema::hasColumn('chat_messages', 'sort_key')) {
                $table->unsignedBigInteger('sort_key')->nullable()->after('subtask_index');
            }
        });

        $messages = DB::table('chat_messages')
            ->orderBy('created_at')
            ->orderBy('id')
            ->get(['id', 'created_at']);

        $sortKey = 0;
        foreach ($messages as $message) {
            $createdAtMicros = $message->created_at
                ? ((int) strtotime((string) $message->created_at) * 1000000)
                : 0;
            $sortKey = max($sortKey + 1, $createdAtMicros);

            DB::table('chat_messages')
                ->where('id', $message->id)
                ->update(['sort_key' => $sortKey]);
        }

        DB::statement('ALTER TABLE chat_messages MODIFY sort_key BIGINT UNSIGNED NOT NULL');

        $sortIndexExists = DB::table('information_schema.statistics')
            ->where('table_schema', DB::getDatabaseName())
            ->where('table_name', 'chat_messages')
            ->where('index_name', 'chat_messages_thread_sort_idx')
            ->exists();

        if (!$sortIndexExists) {
            DB::statement('ALTER TABLE chat_messages ADD INDEX chat_messages_thread_sort_idx (thread_id, sort_key, id)');
        }

        Schema::table('chat_participants', function (Blueprint $table) {
            if (!Schema::hasColumn('chat_participants', 'last_delivered_message_id')) {
                $table->string('last_delivered_message_id')->nullable()->after('user_id');
            }
        });

        $deliveryCursorIndexExists = DB::table('information_schema.statistics')
            ->where('table_schema', DB::getDatabaseName())
            ->where('table_name', 'chat_participants')
            ->where('index_name', 'chat_participants_delivered_idx')
            ->exists();

        if (!$deliveryCursorIndexExists) {
            DB::statement('ALTER TABLE chat_participants ADD INDEX chat_participants_delivered_idx (thread_id, user_id, last_delivered_message_id)');
        }
    }

    public function down(): void
    {
        $deliveryCursorIndexExists = DB::table('information_schema.statistics')
            ->where('table_schema', DB::getDatabaseName())
            ->where('table_name', 'chat_participants')
            ->where('index_name', 'chat_participants_delivered_idx')
            ->exists();

        if ($deliveryCursorIndexExists) {
            DB::statement('ALTER TABLE chat_participants DROP INDEX chat_participants_delivered_idx');
        }

        Schema::table('chat_participants', function (Blueprint $table) {
            if (Schema::hasColumn('chat_participants', 'last_delivered_message_id')) {
                $table->dropColumn('last_delivered_message_id');
            }
        });

        $sortIndexExists = DB::table('information_schema.statistics')
            ->where('table_schema', DB::getDatabaseName())
            ->where('table_name', 'chat_messages')
            ->where('index_name', 'chat_messages_thread_sort_idx')
            ->exists();

        if ($sortIndexExists) {
            DB::statement('ALTER TABLE chat_messages DROP INDEX chat_messages_thread_sort_idx');
        }

        Schema::table('chat_messages', function (Blueprint $table) {
            if (Schema::hasColumn('chat_messages', 'sort_key')) {
                $table->dropColumn('sort_key');
            }
        });
    }
};
