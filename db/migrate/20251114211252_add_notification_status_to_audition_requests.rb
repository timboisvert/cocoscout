# frozen_string_literal: true

class AddNotificationStatusToAuditionRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :audition_requests, :notified_status, :string
  end
end
