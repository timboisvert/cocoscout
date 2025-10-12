source "https://rubygems.org"

gem "rails"
gem "propshaft"
gem "sqlite3"
gem "pg"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "tailwindcss-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "bcrypt", "~> 3.1.7"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "solid_cache"
gem "bootsnap", require: false
gem "kamal", require: false
gem "thruster", require: false
gem "image_processing", "~> 1.2"
gem "aws-sdk-s3", require: false
gem "honeybadger"
gem "rails_semantic_logger"
gem "pagy"
gem "poppler"

gem "dotenv-rails", groups: %i[ development test ]

group :development do
  gem "byebug", platforms: %i[ mri mingw x64_mingw ]
  gem "web-console"
  gem "dockerfile-rails", ">= 1.7"
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "letter_opener"
end

group :test do
  # gem "minitest-rails" # removed in favor of RSpec
end

group :development, :test do
  gem "rspec-rails"
  gem "capybara"
  gem "factory_bot_rails"
  gem "database_cleaner-active_record"
  gem "selenium-webdriver"
end
