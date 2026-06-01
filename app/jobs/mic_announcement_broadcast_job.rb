# frozen_string_literal: true

# Fan out a MicAnnouncement to every active subscriber's preferred
# channel (email today, web/native push later).
class MicAnnouncementBroadcastJob < ApplicationJob
  queue_as :default

  def perform(announcement_id)
    announcement = MicAnnouncement.find_by(id: announcement_id)
    return unless announcement

    MicSignupAlert.where(mic_id: announcement.mic_id, active: true).find_each do |alert|
      MicAnnouncementMailer.posted(announcement, alert.user).deliver_later if Array(alert.channels).include?("email")
    end
  end
end
