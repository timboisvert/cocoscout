# frozen_string_literal: true

class AddInvitationNotificationSentAtToAuditionRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :audition_requests, :invitation_notification_sent_at, :datetime
  end
end
