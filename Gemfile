# frozen_string_literal: true

source "https://rubygems.org"

gem "aws-sdk-s3", require: false
gem "bcrypt", "~> 3.1.7"
gem "bootsnap", require: false
gem "image_processing", "~> 1.2"
gem "importmap-rails"
gem "kamal", require: false
gem "mail", "~> 2.9.0" # Pin to 2.8.x to avoid breaking changes in 2.9.0
gem "pagy", "~> 43.2.0"
gem "pg"
gem "propshaft"
gem "puma", ">= 5.0"
gem "rails"
gem "rails_autolink"
gem "sentry-rails"
gem "sentry-ruby"
gem "solid_cache"
gem "solid_queue"
gem "sqlite3"
gem "stackprof"
gem "stimulus-rails"
gem "tailwindcss-rails"
gem "thruster", require: false
gem "turbo-rails"
gem "tzinfo-data", platforms: %i[windows jruby]

group :production do
  gem "mailgun-ruby", "~> 1.2"
  gem "poppler"
end

group :development do
  gem "brakeman", require: false
  gem "byebug", platforms: %i[mri windows]
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "derailed_benchmarks", require: false
  gem "dockerfile-rails", ">= 1.7"
  gem "letter_opener"
  gem "rubocop-rails-omakase", require: false, group: [ :development ]
  gem "ruby-lsp", require: false
  gem "ruby-lsp-rails", require: false
  gem "ruby-lsp-rspec", require: false
  gem "web-console"
end

group :development, :test do
  gem "capybara"
  gem "database_cleaner-active_record"
  gem "dotenv-rails"
  gem "factory_bot_rails"
  gem "rspec-rails"
  gem "selenium-webdriver"
end
