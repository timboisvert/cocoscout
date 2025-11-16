# frozen_string_literal: true

# Load all question type classes to ensure they register themselves
# This runs on every request in development and once in production
Rails.application.config.to_prepare do
  Dir[Rails.root.join("app/models/question_types/*.rb")].sort.each do |file|
    load file
  end
end
