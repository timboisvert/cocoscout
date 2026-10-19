# frozen_string_literal: true

# Telling people Tap to Pay on iPhone is here (Apple's publishing review 6.1
# and 6.3, at launch): the launch email and an in-app message, which the
# app pushes, to everyone who can sell at a door that has it. Run once per
# organization when its Tap to Pay is switched on, from the console:
#
#   TapToPayLaunch.announce!(organizations: [org], sender: User.find_by!(email_address: "..."))
#
# dry_run: true lists who would hear and sends nothing.
class TapToPayLaunch
  def self.audience(organizations)
    organizations.select { |organization| TapToPay.available_for?(organization) }.flat_map do |organization|
      managers = User.where(id: organization.organization_roles.where(company_role: "manager").select(:user_id))
                     .or(User.where(id: organization.owner_id))
      sellers = User.where(id: organization.ticketing_access_grants.active.where(access_level: "box_office").select(:user_id))
      managers.to_a + sellers.to_a
    end.uniq
  end

  def self.announce!(organizations:, sender:, dry_run: false)
    users = audience(organizations)
    return users if dry_run

    settings_url = Rails.application.routes.url_helpers.door_tap_to_pay_url(**Rails.application.config.action_mailer.default_url_options.to_h)
    rendered = ContentTemplateService.render("tap_to_pay_launch_message", { settings_url: settings_url })
    users.each do |user|
      TapToPayMailer.launch(user).deliver_later
      person = user.person
      next unless person

      MessageService.send_direct(sender: sender, recipient_person: person, subject: rendered[:subject], body: rendered[:body],
                                 template_key: "tap_to_pay_launch_message", push_body: rendered[:push_body], system_generated: true)
    end
    users
  end
end
