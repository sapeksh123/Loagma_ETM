<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
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

    private function authUserSelectColumns(): array
    {
        return [
            'id',
            'name',
            'email',
            'contactNumber',
            'roleId',
            'employeeCode',
            'isActive',
            'lastLogin',
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
            $view = trim(strtolower((string) request()->query('view', 'full')));
            $isMinimalView = in_array($view, ['minimal', 'auth'], true);

            if ($digitsOnly === '') {
                return response()->json([
                    'status' => 'error',
                    'message' => 'Invalid contact number',
                ], 422);
            }

            $normalizedTen = strlen($digitsOnly) >= 10
                ? substr($digitsOnly, -10)
                : $digitsOnly;

            $selectColumns = $isMinimalView ? $this->authUserSelectColumns() : $this->userSelectColumns();

            // Fast path: index-friendly direct contact matches.
            $candidates = array_values(array_unique(array_filter([
                $rawInput,
                $digitsOnly,
                $normalizedTen,
                '+91' . $normalizedTen,
                '91' . $normalizedTen,
            ])));

            if (!empty($candidates)) {
                $directMatch = DB::table('users')
                    ->select($selectColumns)
                    ->whereIn('contactNumber', $candidates)
                    ->orderBy('createdAt', 'desc')
                    ->first();

                if ($directMatch) {
                    return response()->json([
                        'status' => 'success',
                        'data' => $directMatch,
                    ]);
                }
            }

            $cacheKey = implode(':', [
                'user-by-contact',
                $isMinimalView ? 'minimal' : 'full',
                $normalizedTen,
            ]);

            $cachedUser = Cache::remember($cacheKey, now()->addSeconds(30), function () use ($digitsOnly, $normalizedTen, $isMinimalView) {
                $normalizedContactSql = $this->normalizedContactSql();

                $query = DB::table('users')->select(
                    $isMinimalView ? $this->authUserSelectColumns() : $this->userSelectColumns()
                );

                $query->whereRaw("{$normalizedContactSql} = ?", [$digitsOnly]);

                if (strlen($normalizedTen) === 10) {
                    $query->orWhereRaw("RIGHT({$normalizedContactSql}, 10) = ?", [$normalizedTen]);
                }

                return $query->orderBy('createdAt', 'desc')->first();
            });

            if (!$cachedUser) {
                return response()->json([
                    'status' => 'error',
                    'message' => 'User not found',
                ], 404);
            }

            return response()->json([
                'status' => 'success',
                'data' => $cachedUser,
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => $e->getMessage(),
            ], 500);
        }
    }
}
