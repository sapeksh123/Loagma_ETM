<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        if (!Schema::hasTable('attendances')) {
            Schema::create('attendances', function (Blueprint $table) {
                $table->string('id', 191)->primary();
                $table->string('user_id', 191);
                $table->date('date');
                $table->dateTime('punch_in_at');
                $table->dateTime('punch_out_at')->nullable();
                $table->integer('total_work_seconds')->default(0);
                $table->integer('total_break_seconds')->default(0);
                $table->timestamps();

                $table->unique(['user_id', 'date']);
            });
        }

        if (!Schema::hasTable('attendance_breaks')) {
            Schema::create('attendance_breaks', function (Blueprint $table) {
                $table->string('id', 191)->primary();
                $table->string('attendance_id', 191);
                $table->enum('type', ['tea', 'lunch', 'emergency']);
                $table->string('reason')->nullable();
                $table->dateTime('start_time');
                $table->dateTime('end_time')->nullable();
                $table->integer('duration_seconds')->default(0);
                $table->timestamps();
            });
        }
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('attendance_breaks');
        Schema::dropIfExists('attendances');
    }
};

