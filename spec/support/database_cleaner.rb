# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:deletion)
  end

  config.before(:each) do
    DatabaseCleaner.strategy = if RSpec.current_example.metadata[:type] == :system
                                 :deletion
    else
                                 :transaction
    end
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end

  config.after(:suite) do
    # Close all database connections to prevent locks
    ActiveRecord::Base.connection_pool.disconnect!
  end
end
