# frozen_string_literal: true

class MicAnnouncementMailer < ApplicationMailer
  def posted(announcement, user)
    @announcement = announcement
    @mic = announcement.mic
    @user = user
    mail(to: user.email_address, subject: "#{@mic.name}: #{announcement.title.presence || 'News'}")
  end
end
