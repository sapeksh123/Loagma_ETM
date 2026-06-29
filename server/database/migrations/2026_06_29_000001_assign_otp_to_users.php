<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        // Generate easy OTPs for all users (1111, 2222, 3333, etc.)
        $users = DB::table('users')->get();
        $counter = 1;

        foreach ($users as $user) {
            // Create easy OTP: 1111, 2222, 3333, 4444, etc.
            $otp = str_repeat((string)($counter % 10), 4);

            DB::table('users')
                ->where('id', $user->id)
                ->update([
                    'otp' => $otp,
                    'otpExpiry' => now()->addDays(365), // 1 year expiry
                    'updatedAt' => now(),
                ]);

            $counter++;
        }
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        // Clear OTPs if needed
        DB::table('users')->update([
            'otp' => null,
            'otpExpiry' => null,
        ]);
    }
};
