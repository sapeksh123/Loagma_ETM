<?php

return [
    'default' => env('BROADCAST_CONNECTION', 'log'),

    'connections' => [
        'reverb' => [
            'driver' => 'reverb',
            'key' => env('REVERB_APP_KEY', 'local-reverb-key'),
            'secret' => env('REVERB_APP_SECRET', 'local-reverb-secret'),
            'app_id' => env('REVERB_APP_ID', 'local-reverb-app'),
            'options' => [
                // Internal endpoint used by Laravel when dispatching broadcasts.
                // Keep this separate from public websocket host values.
                'host' => env('REVERB_INTERNAL_HOST', env('REVERB_HOST', '127.0.0.1')),
                'port' => (int) env(
                    'REVERB_INTERNAL_PORT',
                    env('REVERB_SERVER_PORT', env('REVERB_PORT', 8080))
                ),
                'scheme' => env('REVERB_INTERNAL_SCHEME', env('REVERB_SCHEME', 'http')),
                'useTLS' => env('REVERB_INTERNAL_SCHEME', env('REVERB_SCHEME', 'http')) === 'https',
            ],
            // Fail fast instead of blocking API requests for ~30s when broadcast target is unreachable.
            'client_options' => [
                'timeout' => (float) env('REVERB_HTTP_TIMEOUT', 3.0),
                'connect_timeout' => (float) env('REVERB_HTTP_CONNECT_TIMEOUT', 2.0),
            ],
        ],

        'log' => [
            'driver' => 'log',
        ],

        'null' => [
            'driver' => 'null',
        ],
    ],
];
