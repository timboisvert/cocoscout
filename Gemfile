source "https://rubygems.org"

gem "rails", "~> 8.0.2", ">= 8.0.2.1"
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

gem "dotenv-rails", groups: %i[ development test ]

group :development do
  gem "web-console"
  gem "dockerfile-rails", ">= 1.7"
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end

group :test do
  gem "minitest-rails"
end
