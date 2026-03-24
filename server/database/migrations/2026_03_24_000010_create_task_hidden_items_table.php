<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('task_hidden_items')) {
            return;
        }

        Schema::create('task_hidden_items', function (Blueprint $table) {
            $table->id();
            $table->string('task_id');
            $table->string('hidden_by_user_id');
            $table->timestamps();

            $table->unique(['task_id', 'hidden_by_user_id'], 'task_hidden_unique_user_task');
            $table->index(['hidden_by_user_id', 'created_at'], 'task_hidden_user_created_idx');
            $table->index('task_id', 'task_hidden_task_idx');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('task_hidden_items');
    }
};
