# frozen_string_literal: true

# Someone asked to delete their CocoScout account (Account Settings, on the
# website or in the app). The superadmins hear about it by email and finish
# it from the person's Superadmin page.
module AccountDeletionRequest
  TEMPLATE_KEY = "account_deletion_requested"

  # device: "iPhone" or "Android" (DeviceLabel), when it came from the app.
  def self.notify_superadmins(user, from_app: false, device: nil)
    person = user.person
    variables = {
      name: person&.name.presence || user.email_address,
      email: user.email_address,
      where: from_app ? "the #{device || 'phone'} app" : "the website",
      requested_on: (user.deletion_requested_at || Time.current).strftime("%B %-d, %Y"),
      person_url: person ? Rails.application.routes.url_helpers.person_detail_url(person, **url_options) : Rails.application.routes.url_helpers.people_list_url(**url_options)
    }
    User::SUPERADMIN_EMAILS.each do |email|
      AppMailer.with(template_key: TEMPLATE_KEY, to: email, variables: variables).send_template.deliver_later
    end
  end

  def self.url_options
    Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end
end
