<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('subtask_daily_statuses')) {
            Schema::create('subtask_daily_statuses', function (Blueprint $table) {
                $table->id();
                $table->string('task_id', 191);
                $table->unsignedInteger('subtask_index');
                $table->date('date');
                $table->enum('status', ['assigned', 'in_progress', 'completed', 'paused', 'need_help', 'ignore'])
                    ->default('assigned');
                $table->text('note')->nullable();
                $table->timestamps();

                // Index + unique instead of a strict FK to avoid
                // type/collation mismatches with tasks.id.
                $table->index('task_id');
                $table->unique(['task_id', 'subtask_index', 'date'], 'subtask_daily_unique');
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('subtask_daily_statuses');
    }
};

