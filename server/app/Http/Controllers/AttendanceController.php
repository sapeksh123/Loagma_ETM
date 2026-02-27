<?php

namespace App\Http\Controllers;

use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class AttendanceController extends Controller
{
    protected function nowIst(): Carbon
    {
        return Carbon::now('Asia/Kolkata');
    }

    public function today(Request $request)
    {
        $validated = $request->validate([
            'user_id' => 'required|string',
        ]);

        return response()->json(
            $this->buildTodaySummary($validated['user_id'])
        );
    }

    public function punchIn(Request $request)
    {
        $validated = $request->validate([
            'user_id' => 'required|string',
        ]);

        $userId = $validated['user_id'];
        $now = $this->nowIst();
        $today = $now->toDateString();

        $attendance = DB::table('attendances')
            ->where('user_id', $userId)
            ->where('date', $today)
            ->first();

        if ($attendance && $attendance->punch_out_at === null) {
            return response()->json([
                'status' => 'error',
                'message' => 'You are already punched in for today.',
            ], 400);
        }

        if (!$attendance) {
            DB::table('attendances')->insert([
                'id' => Str::uuid()->toString(),
                'user_id' => $userId,
                'date' => $today,
                'punch_in_at' => $now,
                'total_work_seconds' => 0,
                'total_break_seconds' => 0,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        } else {
            // Previously completed day, allow re-open? Keep simple: block.
            return response()->json([
                'status' => 'error',
                'message' => 'Today\'s attendance is already completed.',
            ], 400);
        }

        return response()->json([
            'status' => 'success',
            'message' => 'Punch-in recorded successfully.',
            'data' => $this->buildTodaySummary($userId),
        ]);
    }

    public function punchOut(Request $request)
    {
        $validated = $request->validate([
            'user_id' => 'required|string',
        ]);

        $userId = $validated['user_id'];
        $now = $this->nowIst();
        $today = $now->toDateString();

        $attendance = DB::table('attendances')
            ->where('user_id', $userId)
            ->where('date', $today)
            ->first();

        if (!$attendance) {
            return response()->json([
                'status' => 'error',
                'message' => 'You have not punched in today.',
            ], 400);
        }

        if ($attendance->punch_out_at !== null) {
            return response()->json([
                'status' => 'error',
                'message' => 'You have already punched out for today.',
            ], 400);
        }

        $activeBreak = DB::table('attendance_breaks')
            ->where('attendance_id', $attendance->id)
            ->whereNull('end_time')
            ->first();

        if ($activeBreak) {
            return response()->json([
                'status' => 'error',
                'message' => 'End your current break before punching out.',
            ], 400);
        }

        [$workSeconds, $breakSeconds] = $this->calculateDurations($attendance, $now);

        DB::table('attendances')
            ->where('id', $attendance->id)
            ->update([
                'punch_out_at' => $now,
                'total_work_seconds' => $workSeconds,
                'total_break_seconds' => $breakSeconds,
                'updated_at' => $now,
            ]);

        return response()->json([
            'status' => 'success',
            'message' => 'Punch-out recorded successfully.',
            'data' => $this->buildTodaySummary($userId),
        ]);
    }

    public function startBreak(Request $request)
    {
        try {
            $validated = $request->validate([
                'user_id' => 'required|string',
                'type' => 'required|in:tea,lunch,emergency',
                'reason' => 'nullable|string',
            ]);
        } catch (ValidationException $e) {
            return response()->json([
                'status' => 'error',
                'message' => 'Validation failed',
                'errors' => $e->errors(),
            ], 422);
        }

        $userId = $validated['user_id'];
        $type = $validated['type'];
        $reason = $validated['reason'] ?? null;

        if ($type === 'emergency' && empty($reason)) {
            return response()->json([
                'status' => 'error',
                'message' => 'Reason is required for emergency break.',
            ], 422);
        }

        $now = $this->nowIst();
        $today = $now->toDateString();

        $attendance = DB::table('attendances')
            ->where('user_id', $userId)
            ->where('date', $today)
            ->first();

        if (!$attendance || $attendance->punch_out_at !== null) {
            return response()->json([
                'status' => 'error',
                'message' => 'You must be punched in to start a break.',
            ], 400);
        }

        $activeBreak = DB::table('attendance_breaks')
            ->where('attendance_id', $attendance->id)
            ->whereNull('end_time')
            ->first();

        if ($activeBreak) {
            return response()->json([
                'status' => 'error',
                'message' => 'You already have an active break.',
            ], 400);
        }

        DB::table('attendance_breaks')->insert([
            'id' => Str::uuid()->toString(),
            'attendance_id' => $attendance->id,
            'type' => $type,
            'reason' => $reason,
            'start_time' => $now,
            'duration_seconds' => 0,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        return response()->json([
            'status' => 'success',
            'message' => ucfirst($type) . ' break started.',
            'data' => $this->buildTodaySummary($userId),
        ]);
    }

    public function endBreak(Request $request)
    {
        try {
            $validated = $request->validate([
                'user_id' => 'required|string',
            ]);

            $userId = $validated['user_id'];
            $now = $this->nowIst();
            $today = $now->toDateString();

            $attendance = DB::table('attendances')
                ->where('user_id', $userId)
                ->where('date', $today)
                ->first();

            if (!$attendance) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'No attendance found for today.',
                ], 400);
            }

            $activeBreak = DB::table('attendance_breaks')
                ->where('attendance_id', $attendance->id)
                ->whereNull('end_time')
                ->first();

            if (!$activeBreak) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'No active break to end.',
                ], 400);
            }

            $start = Carbon::parse($activeBreak->start_time, 'Asia/Kolkata');
            $duration = $now->diffInSeconds($start);

            DB::table('attendance_breaks')
                ->where('id', $activeBreak->id)
                ->update([
                    'end_time' => $now,
                    'duration_seconds' => $duration,
                    'updated_at' => $now,
                ]);

            // Update totals on attendance
            [$workSeconds, $breakSeconds] = $this->calculateDurations($attendance, $now);

            DB::table('attendances')
                ->where('id', $attendance->id)
                ->update([
                    'total_work_seconds' => $workSeconds,
                    'total_break_seconds' => $breakSeconds,
                    'updated_at' => $now,
                ]);

            return response()->json([
                'status' => 'success',
                'message' => 'Break ended.',
                'data' => $this->buildTodaySummary($userId),
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Build today's attendance summary for a user.
     */
    protected function buildTodaySummary(string $userId): array
    {
        $now = $this->nowIst();
        $today = $now->toDateString();

        $attendance = DB::table('attendances')
            ->where('user_id', $userId)
            ->where('date', $today)
            ->first();

        if (!$attendance) {
            return [
                'status' => 'not_punched_in',
                'punch_in_time' => null,
                'punch_out_time' => null,
                'work_duration_seconds' => 0,
                'break_duration_seconds' => 0,
                'current_break' => null,
            ];
        }

        $breaks = DB::table('attendance_breaks')
            ->where('attendance_id', $attendance->id)
            ->get();

        $activeBreak = $breaks->firstWhere('end_time', null);

        $completedBreakSeconds = 0;
        foreach ($breaks as $break) {
            if ($break->end_time !== null) {
                $start = Carbon::parse($break->start_time, 'Asia/Kolkata');
                $end = Carbon::parse($break->end_time, 'Asia/Kolkata');
                $completedBreakSeconds += $end->diffInSeconds($start);
            }
        }

        $activeBreakSeconds = 0;
        if ($activeBreak) {
            $start = Carbon::parse($activeBreak->start_time, 'Asia/Kolkata');
            $activeBreakSeconds = $now->diffInSeconds($start);
        }

        $totalBreakSeconds = $completedBreakSeconds + $activeBreakSeconds;

        $punchIn = Carbon::parse($attendance->punch_in_at, 'Asia/Kolkata');
        $workEnd = $attendance->punch_out_at
            ? Carbon::parse($attendance->punch_out_at, 'Asia/Kolkata')
            : $now;

        $workSeconds = max(
            0,
            $workEnd->diffInSeconds($punchIn) - $totalBreakSeconds
        );

        if ($attendance->punch_out_at !== null) {
            $status = 'completed';
        } elseif ($activeBreak) {
            $status = 'on_break';
        } else {
            $status = 'working';
        }

        return [
            'status' => $status,
            'punch_in_time' => $punchIn->toIso8601String(),
            'punch_out_time' => $attendance->punch_out_at
                ? Carbon::parse($attendance->punch_out_at, 'Asia/Kolkata')->toIso8601String()
                : null,
            'work_duration_seconds' => $workSeconds,
            'break_duration_seconds' => $totalBreakSeconds,
            'current_break' => $activeBreak
                ? [
                    'type' => $activeBreak->type,
                    'reason' => $activeBreak->reason,
                    'started_at' => Carbon::parse(
                        $activeBreak->start_time,
                        'Asia/Kolkata'
                    )->toIso8601String(),
                    'duration_seconds' => $activeBreakSeconds,
                ]
                : null,
        ];
    }

    /**
     * Calculate work and break durations up to a given moment.
     */
    protected function calculateDurations(object $attendance, Carbon $asOf): array
    {
        $breaks = DB::table('attendance_breaks')
            ->where('attendance_id', $attendance->id)
            ->get();

        $completedBreakSeconds = 0;
        foreach ($breaks as $break) {
            if ($break->end_time !== null) {
                $start = Carbon::parse($break->start_time, 'Asia/Kolkata');
                $end = Carbon::parse($break->end_time, 'Asia/Kolkata');
                $completedBreakSeconds += $end->diffInSeconds($start);
            }
        }

        $activeBreakSeconds = 0;
        foreach ($breaks as $break) {
            if ($break->end_time === null) {
                $start = Carbon::parse($break->start_time, 'Asia/Kolkata');
                $activeBreakSeconds = $asOf->diffInSeconds($start);
                break;
            }
        }

        $totalBreakSeconds = $completedBreakSeconds + $activeBreakSeconds;

        $punchIn = Carbon::parse($attendance->punch_in_at, 'Asia/Kolkata');
        $workEnd = $attendance->punch_out_at
            ? Carbon::parse($attendance->punch_out_at, 'Asia/Kolkata')
            : $asOf;

        $workSeconds = max(
            0,
            $workEnd->diffInSeconds($punchIn) - $totalBreakSeconds
        );

        return [$workSeconds, $totalBreakSeconds];
    }
}

