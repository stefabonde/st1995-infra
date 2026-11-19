# PHP 7.4 (EOL) + apache/mod_php con il backport di sicurezza ufficiale per
# CVE-2026-109618 / CVE-2026-109619 (php/php-src, ramo PHP-7.4-CVE-2026-109618-109619).
#
# Ricetta = docker-library/php @ b9f1715 (7.4/bullseye/apache), con queste differenze:
#  - sorgente: archivio GitHub del commit del backport (pin per SHA) al posto del tarball 7.4.33
#  - bison in piu' e ./buildconf (il sorgente git non contiene configure ne' parser generati)
#  - suffisso di versione per riconoscere a runtime una build patchata
#  - repo Debian bullseye (EOL) su archive.debian.org
# Build: vedi build.sh. Tag: php74-patched:<sha corto>.

FROM debian:bullseye-slim

# Debian 11 (bullseye) e' EOL: i repo sono passati ad archive.debian.org
RUN sed -i -e 's|deb.debian.org/debian-security|archive.debian.org/debian-security|' -e 's|deb.debian.org/debian|archive.debian.org/debian|' -e '/bullseye-updates/d' /etc/apt/sources.list \
    && echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99archive

# prevent Debian's PHP packages from being installed
RUN set -eux; \
	{ \
		echo 'Package: php*'; \
		echo 'Pin: release *'; \
		echo 'Pin-Priority: -1'; \
	} > /etc/apt/preferences.d/no-debian-php

# dependencies required for running "phpize" (see persistent deps below)
ENV PHPIZE_DEPS \
		autoconf \
		dpkg-dev \
		file \
		g++ \
		gcc \
		libc-dev \
		make \
		pkg-config \
		re2c

# persistent / runtime deps
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		$PHPIZE_DEPS \
		ca-certificates \
		curl \
		xz-utils \
	; \
	rm -rf /var/lib/apt/lists/*

ENV PHP_INI_DIR /usr/local/etc/php
RUN set -eux; \
	mkdir -p "$PHP_INI_DIR/conf.d"; \
	[ ! -d /var/www/html ]; \
	mkdir -p /var/www/html; \
	chown www-data:www-data /var/www/html; \
	chmod 777 /var/www/html

ENV APACHE_CONFDIR /etc/apache2
ENV APACHE_ENVVARS $APACHE_CONFDIR/envvars

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends apache2; \
	rm -rf /var/lib/apt/lists/*; \
	\
	sed -ri 's/^export ([^=]+)=(.*)$/: ${\1:=\2}\nexport \1/' "$APACHE_ENVVARS"; \
	\
	. "$APACHE_ENVVARS"; \
	for dir in \
		"$APACHE_LOCK_DIR" \
		"$APACHE_RUN_DIR" \
		"$APACHE_LOG_DIR" \
	; do \
		rm -rvf "$dir"; \
		mkdir -p "$dir"; \
		chown "$APACHE_RUN_USER:$APACHE_RUN_GROUP" "$dir"; \
		chmod 777 "$dir"; \
	done; \
	\
	rm -rvf /var/www/html/*; \
	\
	ln -sfT /dev/stderr "$APACHE_LOG_DIR/error.log"; \
	ln -sfT /dev/stdout "$APACHE_LOG_DIR/access.log"; \
	ln -sfT /dev/stdout "$APACHE_LOG_DIR/other_vhosts_access.log"; \
	chown -R --no-dereference "$APACHE_RUN_USER:$APACHE_RUN_GROUP" "$APACHE_LOG_DIR"

# Apache + PHP requires preforking Apache for best results
RUN a2dismod mpm_event && a2enmod mpm_prefork

# PHP files should be handled by PHP, and should be preferred over any other file type
RUN { \
		echo '<FilesMatch \.php$>'; \
		echo '\tSetHandler application/x-httpd-php'; \
		echo '</FilesMatch>'; \
		echo; \
		echo 'DirectoryIndex disabled'; \
		echo 'DirectoryIndex index.php index.html'; \
		echo; \
		echo '<Directory /var/www/>'; \
		echo '\tOptions -Indexes'; \
		echo '\tAllowOverride All'; \
		echo '</Directory>'; \
	} | tee "$APACHE_CONFDIR/conf-available/docker-php.conf" \
	&& a2enconf docker-php

ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"
ENV PHP_CPPFLAGS="$PHP_CFLAGS"
ENV PHP_LDFLAGS="-Wl,-O1 -pie"

# Backport ufficiale: commit 712e60f9 "Avoid state corruption via bailout"
# (Fix GHSA-w8hw-w9fx-j79w / CVE-2026-109618, GHSA-6wmf-4rv5-p3rp / CVE-2026-109619)
ENV PHP_VERSION 7.4.33
ENV PHP_PATCH_SHA 712e60f9edfd03f0960fc4fc3c2c375f42b90aa2
ENV PHP_EXTRA_VERSION -cve2026-109618-backport

ARG MAKE_JOBS

# Il sorgente viene ricompresso in /usr/src/php.tar.xz perche' docker-php-ext-install
# (docker-php-source extract) lo cerca li'.
RUN set -eux; \
	mkdir -p /usr/src; \
	cd /usr/src; \
	curl -fsSL -o php-src.tar.gz "https://github.com/php/php-src/archive/${PHP_PATCH_SHA}.tar.gz"; \
	mkdir php-src; \
	tar -xzf php-src.tar.gz -C php-src --strip-components=1; \
	rm php-src.tar.gz; \
	tar -C php-src -cJf php.tar.xz .; \
	rm -rf php-src

COPY docker-php-source /usr/local/bin/

RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		apache2-dev \
		bison \
		libargon2-dev \
		libcurl4-openssl-dev \
		libonig-dev \
		libreadline-dev \
		libsodium-dev \
		libsqlite3-dev \
		libssl-dev \
		libxml2-dev \
		zlib1g-dev \
	; \
	\
	export \
		CFLAGS="$PHP_CFLAGS" \
		CPPFLAGS="$PHP_CPPFLAGS" \
		LDFLAGS="$PHP_LDFLAGS" \
	; \
	chmod +x /usr/local/bin/docker-php-source; \
	docker-php-source extract; \
	cd /usr/src/php; \
	sed -i "s|^PHP_EXTRA_VERSION=.*|PHP_EXTRA_VERSION=\"${PHP_EXTRA_VERSION}\"|" configure.ac; \
	grep -q "^PHP_EXTRA_VERSION=\"${PHP_EXTRA_VERSION}\"" configure.ac; \
	./buildconf --force; \
	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
	debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
	if [ ! -d /usr/include/curl ]; then \
		ln -sT "/usr/include/$debMultiarch/curl" /usr/local/include/curl; \
	fi; \
	./configure \
		--build="$gnuArch" \
		--with-config-file-path="$PHP_INI_DIR" \
		--with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
		--enable-option-checking=fatal \
		--with-mhash \
		--with-pic \
		--enable-ftp \
		--enable-mbstring \
		--enable-mysqlnd \
		--with-password-argon2 \
		--with-sodium=shared \
		--with-pdo-sqlite=/usr \
		--with-sqlite3=/usr \
		--with-curl \
		--with-iconv \
		--with-openssl \
		--with-readline \
		--with-zlib \
		--disable-phpdbg \
		--with-pear \
		$(test "$gnuArch" = 's390x-linux-gnu' && echo '--without-pcre-jit') \
		--with-libdir="lib/$debMultiarch" \
		--disable-cgi \
		--with-apxs2 \
	; \
	make -j "${MAKE_JOBS:-$(nproc)}"; \
	find -type f -name '*.a' -delete; \
	make install; \
	find \
		/usr/local \
		-type f \
		-perm '/0111' \
		-exec sh -euxc ' \
			strip --strip-all "$@" || : \
		' -- '{}' + \
	; \
	make clean; \
	\
	cp -v php.ini-* "$PHP_INI_DIR/"; \
	\
	cd /; \
	docker-php-source delete; \
	\
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
	find /usr/local -type f -executable -exec ldd '{}' ';' \
		| awk '/=>/ { print $(NF-1) }' \
		| sort -u \
		| xargs -r dpkg-query --search \
		| cut -d: -f1 \
		| sort -u \
		| xargs -r apt-mark manual \
	; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*; \
	\
	pecl update-channels; \
	rm -rf /tmp/pear ~/.pearrc; \
	\
	php --version

COPY docker-php-ext-* docker-php-entrypoint /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-php-*

# sodium was built as a shared module, so let's enable it too
RUN docker-php-ext-enable sodium

ENTRYPOINT ["docker-php-entrypoint"]
STOPSIGNAL SIGWINCH

COPY apache2-foreground /usr/local/bin/
RUN chmod +x /usr/local/bin/apache2-foreground
WORKDIR /var/www/html

EXPOSE 80
CMD ["apache2-foreground"]
