# frozen_string_literal: true

class UpdateLastSeenJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    # Use update_column to skip callbacks and validations for efficiency
    user.update_column(:last_seen_at, Time.current)
  end
end
