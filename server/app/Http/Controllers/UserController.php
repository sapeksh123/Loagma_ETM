<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class UserController extends Controller
{
    public function index(Request $request)
    {
        try {
            $perPage = (int) $request->query('per_page', 10);
            $perPage = max(5, min($perPage, 50));

            $page = (int) $request->query('page', 1);
            $search = trim((string) $request->query('search', ''));

            $query = DB::table('users')
                ->select(
                    'id',
                    'employeeCode',
                    'name',
                    'email',
                    'contactNumber',
                    'alternativeNumber',
                    'roleId',
                    'roles',
                    'departmentId',
                    'isActive',
                    'lastLogin',
                    'createdAt',
                    'updatedAt',
                    'dateOfBirth',
                    'gender',
                    'image',
                    'city',
                    'state',
                    'country'
                );

            if ($search !== '') {
                $query->where(function ($q) use ($search) {
                    $q->where('name', 'LIKE', '%' . $search . '%')
                        ->orWhere('employeeCode', 'LIKE', '%' . $search . '%')
                        ->orWhere('email', 'LIKE', '%' . $search . '%')
                        ->orWhere('contactNumber', 'LIKE', '%' . $search . '%');
                });
            }

            $paginator = $query
                ->orderBy('createdAt', 'desc')
                ->paginate($perPage, ['*'], 'page', $page);

            return response()->json([
                'status' => 'success',
                'data' => $paginator->items(),
                'meta' => [
                    'current_page' => $paginator->currentPage(),
                    'per_page' => $paginator->perPage(),
                    'last_page' => $paginator->lastPage(),
                    'total' => $paginator->total(),
                    'has_more' => $paginator->hasMorePages(),
                ],
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }
}
