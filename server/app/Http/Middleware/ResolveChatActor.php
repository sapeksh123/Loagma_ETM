<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class ResolveChatActor
{
    /**
     * Resolve acting chat user from request headers.
     */
    public function handle(Request $request, Closure $next): Response
    {
        $userId = trim((string) $request->header('X-User-Id', ''));
        $role = trim((string) $request->header('X-User-Role', ''));

        if ($userId === '' || $role === '') {
            return response()->json([
                'status' => 'error',
                'message' => 'Missing chat identity headers (X-User-Id, X-User-Role)',
            ], 401);
        }

        $request->attributes->set('actor_user_id', $userId);
        $request->attributes->set('actor_role', $role);

        return $next($request);
    }
}
