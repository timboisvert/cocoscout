# frozen_string_literal: true

source "https://rubygems.org"

gem "aws-sdk-s3", require: false
gem "bcrypt", "~> 3.1.7"
gem "bootsnap", require: false
gem "csv" # bundled with Ruby <3.4; required by lib/tasks/mics_import_chicago.rake
gem "image_processing", "~> 1.2"
gem "importmap-rails"
gem "kamal", require: false
gem "mail", "~> 2.9.0" # Pin to 2.8.x to avoid breaking changes in 2.9.0
gem "pagy", "~> 43.2.2"
gem "pg"
gem "prawn"        # PDF generation (signed contract documents)
gem "prawn-table"  # tables inside those PDFs
# prawn requires matrix at load time but does not declare it, and matrix stopped
# being a default gem in Ruby 3.1. It used to arrive via poppler -> cairo.
gem "matrix"
gem "propshaft"
gem "puma", ">= 5.0"
gem "rack-attack"
gem "rails"
gem "rails_autolink"
gem "sentry-rails"
gem "sentry-ruby"
gem "solid_cache"
gem "solid_queue"
gem "stripe"
gem "stimulus-rails"
gem "tailwindcss-rails"
gem "thruster", require: false
gem "turbo-rails"
gem "tzinfo-data", platforms: %i[windows jruby]
gem "redis"
gem "rpush"

group :production do
  gem "mailgun-ruby", "~> 1.2"
end

group :development do
  gem "brakeman", require: false
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "dockerfile-rails", ">= 1.7"
  gem "letter_opener"
  gem "rubocop-rails-omakase", require: false, group: [ :development ]
  gem "ruby-lsp", require: false
  gem "ruby-lsp-rails", require: false
  gem "ruby-lsp-rspec", require: false
  # Was top-level to feed Sentry profiling; that's off, so it's a dev profiler now.
  gem "stackprof", require: false
  gem "web-console"
end

group :development, :test do
  gem "database_cleaner-active_record"
  gem "dotenv-rails"
  gem "factory_bot_rails"
  # N+1 detection: warns in development, and fails specs that opt in.
  # pg_query is prosopite's Postgres fingerprinter, not optional.
  gem "pg_query"
  gem "prosopite"
  gem "rspec-rails"
end
