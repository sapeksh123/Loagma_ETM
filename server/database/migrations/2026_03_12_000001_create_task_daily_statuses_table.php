<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('task_daily_statuses')) {
            Schema::create('task_daily_statuses', function (Blueprint $table) {
                $table->id();
                $table->string('task_id', 191);
                $table->date('date');
                $table->enum('status', ['assigned', 'in_progress', 'completed', 'paused', 'need_help', 'ignore'])
                    ->default('assigned');
                $table->text('note')->nullable();
                $table->timestamps();

                // Use index + unique key instead of a strict FK to avoid
                // type/collation mismatches with the existing tasks.id column.
                $table->index('task_id');
                $table->unique(['task_id', 'date'], 'task_daily_unique');
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('task_daily_statuses');
    }
};

