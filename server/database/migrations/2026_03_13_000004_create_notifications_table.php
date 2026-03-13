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
            CREATE TABLE notifications (
                id VARCHAR(191) PRIMARY KEY,
                employee_id VARCHAR(191) NOT NULL,
                task_id VARCHAR(191) NOT NULL,
                subtask_index INT NULL,
                type VARCHAR(50) NOT NULL,
                title VARCHAR(255) NOT NULL,
                message TEXT NOT NULL,
                is_read BOOLEAN NOT NULL DEFAULT FALSE,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (employee_id) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
                INDEX notifications_employee_id_index (employee_id),
                INDEX notifications_task_id_index (task_id),
                INDEX notifications_is_read_index (is_read),
                INDEX notifications_created_at_index (created_at)
            )
        ");
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        DB::statement("DROP TABLE IF EXISTS notifications");
    }
};

