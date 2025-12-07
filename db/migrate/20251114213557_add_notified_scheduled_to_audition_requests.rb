# frozen_string_literal: true

class AddNotifiedScheduledToAuditionRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :audition_requests, :notified_scheduled, :boolean
  end
end
