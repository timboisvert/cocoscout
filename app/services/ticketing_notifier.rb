# frozen_string_literal: true

# Sends a Ticketing notice to whoever the theater chose for that kind
# (TicketingNotifications), by email, off the request thread. Each kind has a
# seeded content template, ticketing_<kind>. Notices that should only ever go
# once — a show selling out, its show-day summary, a day's summary — pass
# `once:` with the thing they're about and the occasion; a repeat is dropped.
#
# Disputes also go to CocoScout's superadmins, whoever the theater chose.
class TicketingNotifier
  def self.notify(organization, kind, variables: {}, about: nil, occasion: nil, once: false)
    TicketingNotificationJob.perform_later(
      organization.id, kind.to_s, variables.transform_keys(&:to_s).transform_values { |v| v.is_a?(String) ? v : v.to_s },
      about&.class&.polymorphic_name.to_s, about&.id.to_i, occasion.to_s, once
    )
  end

  # Called by the job: claims the once-only slot, then sends.
  def self.deliver(organization, kind, variables, about_type: "", about_id: 0, occasion: "", once: false)
    return if once && !claim(organization, kind, about_type, about_id, occasion)

    recipients = TicketingNotifications.new(organization).emails_for(kind)
    recipients |= User::SUPERADMIN_EMAILS if kind == "dispute"
    common = {
      "organization_name" => organization.name,
      "ticketing_url" => Rails.application.routes.url_helpers.manage_ticketing_url(**url_options),
      "settings_url" => Rails.application.routes.url_helpers.manage_ticketing_settings_section_url(section: "notifications", **url_options)
    }
    recipients.each do |to|
      AppMailer.with(template_key: "ticketing_#{kind}", to: to, variables: common.merge(variables)).send_template.deliver_later
    end
    recipients.size
  end

  def self.claim(organization, kind, about_type, about_id, occasion)
    result = TicketingNotificationLog.insert(
      { organization_id: organization.id, kind: kind, about_type: about_type, about_id: about_id, occasion: occasion, created_at: Time.current },
      unique_by: :index_ticketing_notification_logs_once
    )
    result.rows.any?
  end

  def self.url_options
    Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end

  private_class_method :claim, :url_options
end
