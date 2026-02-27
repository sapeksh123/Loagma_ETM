<?php

namespace App\Http\Controllers;

use Illuminate\Support\Facades\DB;

class DepartmentController extends Controller
{
    public function index()
    {
        try {
            $departments = DB::table('departments')->get();

            return response()->json([
                'status' => 'success',
                'data' => $departments
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage()
            ], 500);
        }
    }
}
