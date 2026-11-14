# frozen_string_literal: true

# Notifications to CocoScout's superadmins (User#superadmin?, the people in
# User::SUPERADMIN_EMAILS) about the business (Tim, 2026-11-14: "I get no
# notification when someone signs up for Pro"): an organization made, and an
# organization starting to pay for Pro. The Notifications list and a push to
# their phones, never an email; the words are SuperadminTemplates. Nobody is
# shown as the sender: the push says CocoScout. A tap opens the organization
# in Superadmin. A notice that can't be sent is logged and never fails what
# it is about.
class SuperadminNotices
  CATEGORY = "platform"

  class << self
    # Organization#after_create_commit.
    def organization_created(organization)
      owner = organization.owner
      deliver(
        kind: "organization_created", template_key: "superadmin_organization_created", subject: organization,
        variables: { organization_name: organization.name,
                     owner_name: (owner&.person&.name.presence || owner&.email_address.presence || "Someone"),
                     organization_url: urls.organization_detail_url(organization, **url_options) },
        path: urls.organization_detail_path(organization)
      )
    end

    # An organization that wasn't paying for Pro now is, once per upgrade:
    # via: :subscription (a Pro subscription of its own; SubscriptionSyncService)
    # or :monthly_bill (Organization#start_pro_on_monthly_bill!). A renewal, a
    # repeat sync, or a trial turning into a paid plan is not one.
    #
    # Webhooks can arrive out of order (a late "incomplete" between two
    # "active"s), so a second start within a day of the last one is the same
    # upgrade and tells nobody again.
    def pro_started(organization, via:)
      return if Notification.where(category: CATEGORY, kind: "pro_started", subject: organization).where(created_at: 1.day.ago..).exists?

      deliver(
        kind: "pro_started", template_key: "superadmin_pro_started", subject: organization,
        variables: { organization_name: organization.name, plan: plan_words(organization, via),
                     finances_url: urls.finances_org_detail_url(org_id: organization.id, **url_options) },
        path: urls.finances_org_detail_path(org_id: organization.id)
      )
    end

    def recipients = User.where(email_address: User::SUPERADMIN_EMAILS).select(&:superadmin?)

    private

    def deliver(kind:, template_key:, variables:, path:, subject:)
      recipients.each do |user|
        Notifier.deliver(user: user, category: CATEGORY, kind: kind, template_key: template_key,
                         variables: variables, path: path, subject: subject)
      end
    rescue StandardError => e
      Rails.logger.error("[SuperadminNotices] #{kind} for organization #{subject&.id} not sent: #{e.class}: #{e.message}")
      Sentry.capture_exception(e) if defined?(Sentry)
    end

    def plan_words(organization, via)
      return "Pro on the monthly bill" if via.to_sym == :monthly_bill

      plan = organization.subscription_interval == "year" ? "Pro, yearly" : "Pro, monthly"
      organization.subscription_status == "trialing" ? "#{plan}, on a trial" : plan
    end

    def urls = Rails.application.routes.url_helpers
    def url_options = Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end
end
