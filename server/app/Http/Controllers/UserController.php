<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class UserController extends Controller
{
    private function userSelectColumns(): array
    {
        return [
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
            'country',
        ];
    }

    private function normalizedContactSql(): string
    {
        return "REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(contactNumber, ' ', ''), '-', ''), '(', ''), ')', ''), '+', '')";
    }

    public function index(Request $request)
    {
        try {
            $perPage = (int) $request->query('per_page', 10);
            $perPage = max(5, min($perPage, 50));

            $page = (int) $request->query('page', 1);
            $search = trim((string) $request->query('search', ''));

            $query = DB::table('users')->select($this->userSelectColumns());

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

    public function showByContact(string $contactNumber)
    {
        try {
            $rawInput = trim($contactNumber);
            $digitsOnly = preg_replace('/\D+/', '', $rawInput) ?? '';

            if ($digitsOnly === '') {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Invalid contact number',
                ], 422);
            }

            $normalizedTen = strlen($digitsOnly) >= 10
                ? substr($digitsOnly, -10)
                : $digitsOnly;

            $normalizedContactSql = $this->normalizedContactSql();

            $query = DB::table('users')->select($this->userSelectColumns());

            $query->whereRaw("{$normalizedContactSql} = ?", [$digitsOnly]);

            if (strlen($normalizedTen) === 10) {
                $query->orWhereRaw("RIGHT({$normalizedContactSql}, 10) = ?", [$normalizedTen]);
            }

            $user = $query->orderBy('createdAt', 'desc')->first();

            if (!$user) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'User not found',
                ], 404);
            }

            return response()->json([
                'status' => 'success',
                'data' => $user,
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }
}
