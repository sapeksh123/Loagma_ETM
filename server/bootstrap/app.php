<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

// Some container images do not expose POSIX signal constants.
// Reverb's start command references these constants directly.
if (!defined('SIGINT')) {
    define('SIGINT', 2);
}

if (!defined('SIGTERM')) {
    define('SIGTERM', 15);
}

if (!defined('SIGQUIT')) {
    define('SIGQUIT', 3);
}

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__ . '/../routes/web.php',
        api: __DIR__ . '/../routes/api.php',
        channels: __DIR__ . '/../routes/channels.php',
        commands: __DIR__ . '/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->alias([
            'chat.actor' => \App\Http\Middleware\ResolveChatActor::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        //
    })->create();
