<p align="center"><a href="https://laravel.com" target="_blank"><img src="https://raw.githubusercontent.com/laravel/art/master/logo-lockup/5%20SVG/2%20CMYK/1%20Full%20Color/laravel-logolockup-cmyk-red.svg" width="400" alt="Laravel Logo"></a></p>

<p align="center">
<a href="https://github.com/laravel/framework/actions"><img src="https://github.com/laravel/framework/workflows/tests/badge.svg" alt="Build Status"></a>
<a href="https://packagist.org/packages/laravel/framework"><img src="https://img.shields.io/packagist/dt/laravel/framework" alt="Total Downloads"></a>
<a href="https://packagist.org/packages/laravel/framework"><img src="https://img.shields.io/packagist/v/laravel/framework" alt="Latest Stable Version"></a>
<a href="https://packagist.org/packages/laravel/framework"><img src="https://img.shields.io/packagist/l/laravel/framework" alt="License"></a>
</p>

## About Laravel

Laravel is a web application framework with expressive, elegant syntax. We believe development must be an enjoyable and creative experience to be truly fulfilling. Laravel takes the pain out of development by easing common tasks used in many web projects, such as:

- [Simple, fast routing engine](https://laravel.com/docs/routing).
- [Powerful dependency injection container](https://laravel.com/docs/container).
- Multiple back-ends for [session](https://laravel.com/docs/session) and [cache](https://laravel.com/docs/cache) storage.
- Expressive, intuitive [database ORM](https://laravel.com/docs/eloquent).
- Database agnostic [schema migrations](https://laravel.com/docs/migrations).
- [Robust background job processing](https://laravel.com/docs/queues).
- [Real-time event broadcasting](https://laravel.com/docs/broadcasting).

Laravel is accessible, powerful, and provides tools required for large, robust applications.

## Learning Laravel

Laravel has the most extensive and thorough [documentation](https://laravel.com/docs) and video tutorial library of all modern web application frameworks, making it a breeze to get started with the framework. You can also check out [Laravel Learn](https://laravel.com/learn), where you will be guided through building a modern Laravel application.

If you don't feel like reading, [Laracasts](https://laracasts.com) can help. Laracasts contains thousands of video tutorials on a range of topics including Laravel, modern PHP, unit testing, and JavaScript. Boost your skills by digging into our comprehensive video library.

## Laravel Sponsors

We would like to extend our thanks to the following sponsors for funding Laravel development. If you are interested in becoming a sponsor, please visit the [Laravel Partners program](https://partners.laravel.com).

### Premium Partners

- **[Vehikl](https://vehikl.com)**
- **[Tighten Co.](https://tighten.co)**
- **[Kirschbaum Development Group](https://kirschbaumdevelopment.com)**
- **[64 Robots](https://64robots.com)**
- **[Curotec](https://www.curotec.com/services/technologies/laravel)**
- **[DevSquad](https://devsquad.com/hire-laravel-developers)**
- **[Redberry](https://redberry.international/laravel-development)**
- **[Active Logic](https://activelogic.com)**

## Contributing

Thank you for considering contributing to the Laravel framework! The contribution guide can be found in the [Laravel documentation](https://laravel.com/docs/contributions).

## Code of Conduct

In order to ensure that the Laravel community is welcoming to all, please review and abide by the [Code of Conduct](https://laravel.com/docs/contributions#code-of-conduct).

## Security Vulnerabilities

If you discover a security vulnerability within Laravel, please send an e-mail to Taylor Otwell via [taylor@laravel.com](mailto:taylor@laravel.com). All security vulnerabilities will be promptly addressed.

## License

The Laravel framework is open-sourced software licensed under the [MIT license](https://opensource.org/licenses/MIT).

## Chat Deployment Checklist

For the realtime chat module to work smoothly in production, verify all of the following:

1. Run database migrations:
   `php artisan migrate --force`
2. Ensure the chat broadcasting driver is Reverb:
   `BROADCAST_CONNECTION=reverb`
3. Ensure cache and queue use Redis:
   `CACHE_STORE=redis`
   `QUEUE_CONNECTION=redis`
4. Provide a real Redis service, not just `127.0.0.1`, unless Redis is actually running on the same machine:
   `REDIS_URL=...` or `REDIS_HOST=...`
5. Start the required long-running processes in production:
   `php artisan queue:work`
   `php artisan reverb:start --host=0.0.0.0 --port=8080`
6. Set separate public and internal Reverb endpoints:
   `APP_URL=https://your-domain`
   Public websocket values for clients:
   `REVERB_HOST=your-domain`
   `REVERB_PORT=443`
   `REVERB_SCHEME=https`
   Internal broadcast dispatch values for Laravel server-to-Reverb calls:
   `REVERB_INTERNAL_HOST=127.0.0.1`
   `REVERB_INTERNAL_PORT=10000`
   `REVERB_INTERNAL_SCHEME=http`
7. Keep broadcast HTTP dispatch timeouts short to avoid blocking API responses when Reverb is unhealthy:
   `REVERB_HTTP_TIMEOUT=3`
   `REVERB_HTTP_CONNECT_TIMEOUT=2`
8. Emergency fallback (if chat APIs stall due broadcast dispatch):
   `CHAT_BROADCAST_ENABLED=false`
   This keeps chat APIs responsive while temporarily disabling realtime push events.
9. If the runtime does not have the PHP Redis extension installed, install `predis/predis` and switch:
   `REDIS_CLIENT=predis`
10. Verify the new chat endpoints are reachable:
   `POST /api/chat/realtime/auth`
   `POST /api/chat/threads/{id}/receipts`
   `GET /api/chat/threads/{id}/messages?before_sort_key=...`
   `GET /api/chat/threads/{id}/messages?after_sort_key=...`
