<?php

namespace App\Http\Controllers;

use Illuminate\Support\Facades\DB;

class RoleController extends Controller
{
    public function index()
    {
        try {
            $roles = DB::table('roles')->get();

            return response()->json([
                'status' => 'success',
                'data' => $roles
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage()
            ], 500);
        }
    }
}
