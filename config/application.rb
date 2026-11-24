# frozen_string_literal: true

require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"  # ActionCable removed — messaging no longer uses websockets
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Cocoscout
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # This is a temporary hack that will be revisited at some point
    config.time_zone = "Central Time (US & Canada)"

    # The week starts on Sunday (Tim, 2026-11-24: "that's what Americans
    # expect"): every calendar, the staff schedule's week (Sunday through
    # Saturday, and the day a published week is stored by), and the weekly
    # rows of reports. beginning_of_week and end_of_week follow this. The one
    # exception asks for Monday by name: weekly contract settlement
    # (Contract, ContractPaymentSyncService), whose payments are already
    # dated by Monday-to-Sunday weeks.
    config.beginning_of_week = :sunday

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # rubocop: custom cops (loaded only by RuboCop via .rubocop.yml `require`),
    # not by the app — and their RuboCop:: constants don't match zeitwerk's
    # path-based naming, so they must stay out of autoload/eager-load.
    config.autoload_lib(ignore: %w[assets tasks rubocop])

    config.log_level = ENV["LOG_LEVEL"] || :info
    # config.semantic_logger.application = "cocoscout"
    # config.semantic_logger.environment = ENV["STACK_NAME"] || Rails.env

    config.generators.system_tests = nil

    config.active_record.timestamped_migrations = true
  end
end
