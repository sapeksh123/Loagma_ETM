### Laravel 12 Backend - Render Dockerfile

## Stage 1: Build PHP dependencies with Composer
FROM composer:2 AS vendor

WORKDIR /app

# Copy only composer files first to leverage Docker layer caching
COPY composer.json composer.lock* ./

# First install without running composer scripts (no artisan yet)
RUN composer install \
    --no-dev \
    --no-interaction \
    --no-progress \
    --no-scripts \
    --prefer-dist

# Copy the rest of the application code (artisan etc.)
COPY . .

# Re-run install so composer scripts can run now that artisan exists
RUN composer install \
    --no-dev \
    --no-interaction \
    --no-progress \
    --prefer-dist \
    --optimize-autoloader


## Stage 2: Runtime image
FROM php:8.3-cli

WORKDIR /app

# Install system dependencies and PHP extensions commonly required by Laravel
RUN apt-get update && apt-get install -y \
        libpq-dev \
        git \
    && docker-php-ext-install \
        pdo_mysql \
        pdo_pgsql \
        bcmath \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy app (including vendor) from the builder image
COPY --from=vendor /app /app

# Ensure storage and cache are writable
RUN chown -R www-data:www-data storage bootstrap/cache

USER www-data

# Recommended production defaults (can be overridden via Render env vars)
ENV APP_ENV=production \
    APP_DEBUG=false \
    LOG_CHANNEL=stderr

# Render sets PORT automatically; default to 8000 for local runs
EXPOSE 8000

# Cache configuration/routes/views on container start, then run the HTTP server
CMD php artisan config:cache \
    && php artisan route:cache \
    && php artisan view:cache \
    && php artisan serve --host=0.0.0.0 --port=${PORT:-8000}

