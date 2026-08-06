# frozen_string_literal: true

# Copy for a payout the payee's bank sent back. Migration-owned so it ships
# with the deploy — the notification job runs off a webhook inside the money
# path, and a missing template there would raise.
class AddPayoutReturnedTemplates < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "content_templates"
  end

  TEMPLATES = [
    {
      key: "payout_returned_to_payee",
      name: "Payout Returned (payee)",
      subject: "We couldn't get {{amount}} into your bank account",
      body: "<p>Hi {{recipient_name}},</p>" \
            "<p>{{organization_name}} sent you <strong>{{amount}}</strong>, but your bank sent it back. " \
            "That usually means the account was closed, or the details don't quite match.</p>" \
            "<p>The money is safe and still yours — once your bank details are right, it goes out again.</p>" \
            "<p><a href=\"{{setup_url}}\">Check your bank details</a></p>",
      # Never names Stripe: payees deal with CocoScout, not our payout provider.
      available_variables: %w[recipient_name organization_name amount setup_url],
      channel: "both"
    },
    {
      key: "payout_returned_manager",
      name: "Payout Returned (manager alert)",
      subject: "{{amount}} to {{payee_name}} came back",
      body: "<p>{{amount}} we sent {{payee_name}} was returned by their bank.</p>" \
            "<p>The money is back with {{organization_name}} and is owed to them again — " \
            "it'll be picked up by your next payout run once their bank details are fixed. " \
            "We've asked them to check.</p>" \
            "{{#reason}}<p class=\"text-sm\">Reason given: {{reason}}</p>{{/reason}}" \
            "<p><a href=\"{{payout_run_url}}\">View the payout run</a></p>",
      available_variables: %w[payee_name organization_name amount reason payout_run_url],
      channel: "message"
    },
    {
      key: "payout_funding_failed",
      name: "Payout Funding Failed (manager alert)",
      subject: "The debit for your {{total}} payout run didn't go through",
      body: "<p>The bank debit funding your {{total}} payout run to {{people_count}} was declined, " \
            "so nothing has been sent.</p>" \
            "<p>Check the account we debit in Money settings, then submit the run again.</p>" \
            "<p><a href=\"{{payout_run_url}}\">View the payout run</a></p>",
      available_variables: %w[organization_name total people_count payout_run_url],
      channel: "both"
    }
  ].freeze

  def up
    TEMPLATES.each do |attrs|
      template = Template.find_or_initialize_by(key: attrs[:key])
      template.assign_attributes(
        name: attrs[:name],
        subject: attrs[:subject],
        body: attrs[:body],
        category: "payments",
        channel: attrs[:channel],
        active: true,
        available_variables: attrs[:available_variables]
      )
      template.save!
    end
  end

  def down
    Template.where(key: TEMPLATES.map { |t| t[:key] }).delete_all
  end
end
