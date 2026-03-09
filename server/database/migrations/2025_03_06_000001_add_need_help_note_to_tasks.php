<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('tasks') && !Schema::hasColumn('tasks', 'need_help_note')) {
            Schema::table('tasks', function (Blueprint $table) {
                $table->text('need_help_note')->nullable()->after('status');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('tasks') && Schema::hasColumn('tasks', 'need_help_note')) {
            Schema::table('tasks', function (Blueprint $table) {
                $table->dropColumn('need_help_note');
            });
        }
    }
};

