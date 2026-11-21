# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t rails8_on_docker .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name rails8_on_docker rails8_on_docker

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Layers are arranged so a deploy that only changes code uploads only the code
# and the compiled assets (Tim, 2026-11-14: most of a deploy was uploading
# layers to the build cache). The gems and their bootsnap cache sit in layers
# that change only with Gemfile.lock; the app's own bootsnap cache is made last,
# in a small layer of its own. Nothing is chowned recursively after a copy,
# because that writes every file again as one more layer.

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.13
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 sqlite3 libpq5 libvips libglib2.0-0 libcairo2 libcairo-gobject2 libpoppler-glib8 poppler-utils libgirepository-1.0-1 gir1.2-glib-2.0 gir1.2-poppler-0.18 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"

# Gems: changes only when Gemfile.lock does
FROM base AS gems

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git pkg-config libpq-dev libvips poppler-utils libglib2.0-dev libcairo2-dev libgirepository1.0-dev libpoppler-glib-dev && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems, and compile them for bootsnap
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Throw-away stage for the assets
FROM gems AS build

# Copy application code
COPY . .

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile


# Final stage for app image
FROM base

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

# Gems and their bootsnap cache: the same layers until Gemfile.lock changes
COPY --from=gems "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=gems --chown=rails:rails /rails/tmp/cache/bootsnap /rails/tmp/cache/bootsnap

# The application, without the build's caches. Code stays owned by root; the
# rails user owns only what it writes at runtime.
COPY --from=build --exclude=tmp/cache --exclude=log --exclude=storage --exclude=db /rails /rails
COPY --from=build --chown=rails:rails /rails/db /rails/db
RUN mkdir -p log storage && \
    chown rails:rails log storage tmp/cache && \
    find tmp -path tmp/cache -prune -o -exec chown rails:rails {} +
USER 1000:1000

# Precompile bootsnap code for the app itself: a small layer of its own
RUN bundle exec bootsnap precompile app/ lib/

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=5 \
    CMD curl -f http://localhost:80/up || exit 1

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
