# frozen_string_literal: true

# Telling everyone with an account that CocoScout has an app (Tim,
# 2026-11-09: "some way of emailing everybody who's a CocoScout user and
# telling them about the app"; 14 of 1,052 people had ever opened it). One
# email each, ever: users.app_announced_at is stamped as it's queued, so
# running it again only reaches whoever is left. The words are the
# "get_the_app_announcement" template (PlatformTemplates).
#
# Run from the console, a batch at a time, the people seen most recently
# first:
#
#   AppAnnouncement.send_test!("you@example.com") # one copy, to look at
#   AppAnnouncement.announce!(dry_run: true)      # how many would hear
#   AppAnnouncement.announce!(limit: 50)          # the next fifty
#   AppAnnouncement.announce!(limit: 400, seen_since: 90.days.ago)
#
# limit is there for the mail provider's daily cap. Nobody hears who already
# has the app, asked for their account to be deleted, has an address that
# bounced or complained, or never came in after signing up.
class AppAnnouncement
  TEMPLATE = "get_the_app_announcement"

  def self.audience(seen_since: nil)
    scope = User.where(app_announced_at: nil, deletion_requested_at: nil)
                .where.not(last_seen_at: nil)
                .where.not(id: AppActivityDay.select(:user_id))
                .where("LOWER(users.email_address) NOT IN (SELECT email FROM email_suppressions)")
    scope = scope.where(last_seen_at: seen_since..) if seen_since
    scope.order(last_seen_at: :desc, id: :asc)
  end

  # Returns how many were queued (or would be, on a dry run).
  def self.announce!(limit: 50, seen_since: nil, dry_run: false)
    return audience(seen_since: seen_since).count if dry_run

    users = audience(seen_since: seen_since).limit(limit).to_a
    users.each do |user|
      # Stamped first: a second run, or a second console, never doubles up.
      next unless User.where(id: user.id, app_announced_at: nil).update_all(app_announced_at: Time.current) == 1

      mail(to: user.email_address, user: user).deliver_later
    end
    users.size
  end

  # One copy to an address, to look at before anyone is told. Nobody is
  # stamped as told, so it can be sent as often as it takes.
  def self.send_test!(email)
    user = User.find_by(email_address: email.to_s.strip.downcase)
    mail(to: email, user: user).deliver_later
    email
  end

  # The email itself (also what the dev preview at /rails/mailers shows).
  def self.mail(to:, user: nil)
    AppMailer.with(template_key: TEMPLATE, to: to, variables: variables_for(user), hide_app_note: true,
                   inline_images: BADGES.transform_values(&:to_s)).send_template
  end

  # The two store badges, drawn as PNGs to match the site's (email apps show
  # neither SVG nor web fonts). 3x, shown at 120×40 and 135×40.
  BADGES = {
    "app_store_badge" => Rails.root.join("app", "assets", "images", "app_store_badge_email.png"),
    "google_play_badge" => Rails.root.join("app", "assets", "images", "google_play_badge_email.png")
  }.freeze

  def self.variables_for(user)
    {
      "first_name" => user&.person&.first_name.presence || "there",
      "app_url" => Rails.application.routes.url_helpers.get_the_app_url(**(Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 })),
      "ios_url" => AppStores::APP_STORE_URL,
      "android_url" => AppStores::PLAY_STORE_URL
    }
  end
end
