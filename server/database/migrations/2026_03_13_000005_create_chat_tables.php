<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration {
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        // Chat threads: high-level conversations (direct or broadcast)
        DB::statement("
            CREATE TABLE chat_threads (
                id VARCHAR(191) PRIMARY KEY,
                type ENUM('direct', 'broadcast_role', 'broadcast_all') NOT NULL,
                created_by VARCHAR(191) NOT NULL,
                target_user_id VARCHAR(191) NULL,
                target_role VARCHAR(191) NULL,
                title VARCHAR(255) NOT NULL,
                last_message_at DATETIME NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY (target_user_id) REFERENCES users(id) ON DELETE SET NULL,
                INDEX chat_threads_type_index (type),
                INDEX chat_threads_created_by_index (created_by),
                INDEX chat_threads_target_user_id_index (target_user_id),
                INDEX chat_threads_last_message_at_index (last_message_at)
            )
        ");

        // Chat messages: individual messages within a thread
        DB::statement("
            CREATE TABLE chat_messages (
                id VARCHAR(191) PRIMARY KEY,
                thread_id VARCHAR(191) NOT NULL,
                sender_id VARCHAR(191) NOT NULL,
                sender_role VARCHAR(50) NOT NULL,
                body TEXT NOT NULL,
                task_id VARCHAR(191) NULL,
                subtask_index INT NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (thread_id) REFERENCES chat_threads(id) ON DELETE CASCADE,
                FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE SET NULL,
                INDEX chat_messages_thread_id_index (thread_id),
                INDEX chat_messages_sender_id_index (sender_id),
                INDEX chat_messages_created_at_index (created_at)
            )
        ");

        // Chat participants: per-user state for a thread (unread counts, read markers)
        DB::statement("
            CREATE TABLE chat_participants (
                id VARCHAR(191) PRIMARY KEY,
                thread_id VARCHAR(191) NOT NULL,
                user_id VARCHAR(191) NOT NULL,
                last_read_message_id VARCHAR(191) NULL,
                unread_count INT NOT NULL DEFAULT 0,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (thread_id) REFERENCES chat_threads(id) ON DELETE CASCADE,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY (last_read_message_id) REFERENCES chat_messages(id) ON DELETE SET NULL,
                UNIQUE KEY chat_participants_thread_user_unique (thread_id, user_id),
                INDEX chat_participants_user_id_index (user_id)
            )
        ");
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        DB::statement("DROP TABLE IF EXISTS chat_participants");
        DB::statement("DROP TABLE IF EXISTS chat_messages");
        DB::statement("DROP TABLE IF EXISTS chat_threads");
    }
};

