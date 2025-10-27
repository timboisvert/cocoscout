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
# gem "rails_semantic_logger" Check soon if you can put this back, and also uncomment the config in application.rb
gem "pagy"

group :production do
  gem "poppler"
  gem "mailgun_rails"
end

group :development do
  gem "byebug", platforms: %i[ mri windows ]
  gem "web-console"
  gem "dockerfile-rails", ">= 1.7"
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "letter_opener"
  gem "ruby-lsp", require: false
  gem "ruby-lsp-rails", require: false
  gem "ruby-lsp-rspec", require: false
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
  gem "dotenv-rails"
end
