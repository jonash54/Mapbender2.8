# PHP version is parameterised so you can flip between a known-good
# baseline (7.4) and the target (8.3) without changing anything else.
#   docker compose build --build-arg PHP_VERSION=7.4
#   docker compose build --build-arg PHP_VERSION=8.3
ARG PHP_VERSION=7.4
FROM php:${PHP_VERSION}-apache

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq-dev \
        libpng-dev \
        libjpeg-dev \
        libfreetype6-dev \
        libwebp-dev \
        libxml2-dev \
        libcurl4-openssl-dev \
        libmagickwand-dev \
        libzip-dev \
        libonig-dev \
        libgettextpo-dev \
        gettext \
        postgresql-client \
        unzip \
        git \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# GD: configure differs slightly between PHP 7.4 and 8.x
RUN if php -r 'exit(version_compare(PHP_VERSION,"7.4","<")?0:1);'; then \
        docker-php-ext-configure gd --with-freetype-dir=/usr --with-jpeg-dir=/usr --with-webp-dir=/usr ; \
    else \
        docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp ; \
    fi \
    && docker-php-ext-install -j$(nproc) gd pgsql pdo_pgsql mbstring gettext curl xml zip

# Imagick: pecl version varies by PHP. Best-effort; if it fails we keep going
# so the rest of the image still builds (only the welded-PNG-rotate path needs it).
RUN pecl install imagick \
    && docker-php-ext-enable imagick \
    || echo "imagick install failed - skipping (class_weldMaps2PNG_rotate.php will not work)"

RUN a2enmod rewrite deflate headers expires

COPY apache-mapbender.conf /etc/apache2/sites-available/000-default.conf
COPY php.ini /usr/local/etc/php/conf.d/zz-mapbender.ini
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Repo is bind-mounted at /var/www/mapbender by docker-compose.
WORKDIR /var/www/mapbender

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["apache2-foreground"]
