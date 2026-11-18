# frozen_string_literal: true

# The one email telling everyone CocoScout has an app, as it will be sent
# (AppAnnouncement). In development: /rails/mailers/app_announcement/get_the_app
class AppAnnouncementPreview < ActionMailer::Preview
  def get_the_app
    user = User.where.not(last_seen_at: nil).order(last_seen_at: :desc).first
    AppAnnouncement.mail(to: user&.email_address || "you@example.com", user: user)
  end
end
