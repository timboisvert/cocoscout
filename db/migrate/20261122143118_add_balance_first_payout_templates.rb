# frozen_string_literal: true

# The managers' notices for a payout run that pays from the CocoScout balance
# first (Tim, 2026-11-22):
#
#   payout_run_submitted_from_balance  submitted: who the balance paid now,
#                                      and when the rest are paid
#   payout_rest_funding_failed         the bank debit for the rest bounced;
#                                      the people already paid stay paid
#   payout_run_more_paid               a morning's pass paid more people from
#                                      the balance (a notification, no email)
class AddBalanceFirstPayoutTemplates < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "content_templates"
  end

  TEMPLATES = [
    {
      key: "payout_run_submitted_from_balance",
      name: "Payout Run Submitted, Paid From Balance (manager alert)",
      subject: "Payout run submitted: {{paid_count}} paid from your balance",
      body: "<p>Hi {{recipient_name}},</p>" \
            "<p>A {{run_kind}} payout run for {{organization_name}} was just submitted: <strong>{{total}}</strong> to {{people_count}}.</p>" \
            "{{payee_lines}}" \
            "<p>{{paid_count}} ({{paid_total}}) were paid from your CocoScout balance now. " \
            "{{#waiting_on_balance}}The other {{waiting_count}} ({{waiting_total}}) are paid as ticket money clears, " \
            "or from your bank on {{bank_date}}.{{/waiting_on_balance}}" \
            "{{#waiting_on_bank}}The other {{waiting_count}} ({{waiting_total}}) are paid when your bank debit clears.{{/waiting_on_bank}}</p>" \
            "<p><a href=\"{{payout_run_url}}\">View the payout run</a></p>",
      available_variables: %w[recipient_name organization_name run_kind total people_count payee_lines paid_count paid_total
                              waiting_count waiting_total bank_date waiting_on_balance waiting_on_bank payout_run_url]
    },
    {
      key: "payout_rest_funding_failed",
      name: "Payout Rest Funding Failed (manager alert)",
      subject: "The bank debit for the rest of your payout run didn't go through",
      body: "<p>The bank debit for the rest of your {{total}} payout run was declined.</p>" \
            "<p>The {{paid_count}} paid from your CocoScout balance stay paid. The other {{waiting_count}} ({{waiting_total}}) " \
            "wait on the run, and are paid as ticket money clears.</p>" \
            "<p>Check the account we debit in Money settings, then choose Pay the rest from my bank on the run.</p>" \
            "<p><a href=\"{{payout_run_url}}\">View the payout run</a></p>",
      available_variables: %w[organization_name total people_count paid_count waiting_count waiting_total payout_run_url]
    },
    {
      key: "payout_run_more_paid",
      name: "Payout Run, More Paid From Balance (manager notification)",
      subject: "{{paid_count}} paid from your CocoScout balance",
      body: "<p>This morning your CocoScout balance paid {{paid_names}} ({{paid_total}}) on your payout run.</p>" \
            "<p>{{next_words}}</p>" \
            "<p><a href=\"{{payout_run_url}}\">View the payout run</a></p>",
      available_variables: %w[organization_name paid_count paid_names paid_total next_words payout_run_url],
      channel: "message"
    }
  ].freeze

  def up
    TEMPLATES.each do |attrs|
      template = Template.find_or_initialize_by(key: attrs[:key])
      template.assign_attributes(name: attrs[:name], subject: attrs[:subject], body: attrs[:body], category: "payments",
                                 channel: attrs.fetch(:channel, "both"), active: true, available_variables: attrs[:available_variables])
      template.save!
    end
  end

  def down
    Template.where(key: TEMPLATES.map { |t| t[:key] }).delete_all
  end
end
