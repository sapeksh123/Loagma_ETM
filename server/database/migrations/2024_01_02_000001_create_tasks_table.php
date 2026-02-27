<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration {
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        DB::statement("
            CREATE TABLE tasks (
                id VARCHAR(191) PRIMARY KEY,
                title VARCHAR(255) NOT NULL,
                description TEXT,
                category ENUM('daily', 'project', 'personal', 'family', 'other') NOT NULL,
                priority ENUM('low', 'medium', 'high', 'critical') NOT NULL DEFAULT 'medium',
                status ENUM('assigned', 'in_progress', 'completed', 'paused', 'need_help') NOT NULL DEFAULT 'assigned',
                deadline_date DATE,
                deadline_time TIME,
                created_by VARCHAR(191) NOT NULL,
                assigned_to VARCHAR(191) NOT NULL,
                createdAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updatedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY (assigned_to) REFERENCES users(id) ON DELETE CASCADE
            )
        ");
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        DB::statement("DROP TABLE IF EXISTS tasks");
    }
};
