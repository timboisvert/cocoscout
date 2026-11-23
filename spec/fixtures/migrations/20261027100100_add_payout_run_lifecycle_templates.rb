# frozen_string_literal: true

# The manager notices for a payout run's lifecycle (Tim, 2026-10-27): submitted
# (and funded, when the money settled in the same request), funded, everyone's
# paid, partly paid. Each goes to the people Money settings → Notifications
# names, as a Notification and an email. Migration-owned so they ship with the
# deploy: the jobs raise on a missing template, inside the paying path.
#
# payout_run_submitted used to be seeded by lib/tasks/content_templates.rake.
# A hand-edited copy is left alone; the rake task's original wording is
# replaced with the version that can say "and funded".
class AddPayoutRunLifecycleTemplates < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "content_templates"
  end

  # Word for word what the rake task seeded, so an untouched copy is recognized.
  RAKE_SUBMITTED_BODY =
    "<p>Hi {{recipient_name}},</p>" \
    "<p>A {{run_kind}} payout run for {{organization_name}} was just submitted: " \
    "<strong>{{total}}</strong> to {{people_count}}.</p>" \
    "{{payee_lines}}" \
    "<p>Deposits are expected to land <strong>{{expected_window}}</strong> " \
    "(people who haven't connected a bank yet are paid from this run once they do).</p>" \
    "<p><a href=\"{{payout_run_url}}\">View the payout run</a></p>"

  SUBMITTED = {
    key: "payout_run_submitted",
    name: "Payout Run Submitted (manager alert)",
    subject: "Payout run submitted{{#funded}} and funded{{/funded}} — {{total}} to {{people_count}}",
    body: "<p>Hi {{recipient_name}},</p>" \
          "<p>A {{run_kind}} payout run for {{organization_name}} was just submitted" \
          "{{#funded}} and funded{{/funded}}: <strong>{{total}}</strong> to {{people_count}}.</p>" \
          "{{payee_lines}}" \
          "<p>{{#funded}}Payments are going out now. {{/funded}}" \
          "{{#not_funded}}Payments go out once the money comes in from your bank. {{/not_funded}}" \
          "Deposits are expected to land <strong>{{expected_window}}</strong> " \
          "(people who haven't connected a bank yet are paid from this run once they do).</p>" \
          "<p><a href=\"{{payout_run_url}}\">View the payout run</a></p>",
    available_variables: %w[recipient_name organization_name run_kind total people_count payday expected_window
                            payee_lines payout_run_url funded not_funded]
  }.freeze

  TEMPLATES = [
    {
      key: "payout_run_funded",
      name: "Payout Run Funded (manager alert)",
      subject: "Your {{total}} payout run is funded — payments are going out",
      body: "<p>The money for your {{total}} payout run to {{people_count}} came in from your bank, " \
            "and payments are going out now.</p>" \
            "<p>Deposits are expected to land <strong>{{expected_window}}</strong>.</p>" \
            "<p><a href=\"{{payout_run_url}}\">View the payout run</a></p>",
      available_variables: %w[organization_name total people_count payday expected_window payout_run_url]
    },
    {
      key: "payout_run_completed",
      name: "Payout Run Completed (manager alert)",
      subject: "Everyone's paid: {{people_count}}, {{total}}",
      body: "<p>Your payout run from {{payday}} is done: <strong>{{total}}</strong> went out to {{people_count}}.</p>" \
            "<p>Deposits are expected to land <strong>{{expected_window}}</strong>.</p>" \
            "<p><a href=\"{{payout_run_url}}\">View the payout run</a></p>",
      available_variables: %w[organization_name total people_count payday expected_window payout_run_url]
    },
    {
      key: "payout_run_partly_paid",
      name: "Payout Run Partly Paid (manager alert)",
      subject: "{{paid_count}} paid, {{waiting_count}} waiting on bank details",
      body: "<p>Your payout run from {{payday}} paid <strong>{{paid_total}}</strong> to {{paid_count}}.</p>" \
            "<p>Still waiting on bank details: <strong>{{waiting_names}}</strong> ({{waiting_total}}). " \
            "Their money stays on this run and goes out by itself once they connect a bank.</p>" \
            "<p><a href=\"{{payout_run_url}}\">View the payout run</a></p>",
      available_variables: %w[organization_name payday paid_count paid_total waiting_count waiting_names waiting_total
                              payout_run_url]
    }
  ].freeze

  def up
    TEMPLATES.each { |attrs| write!(attrs) }

    submitted = Template.find_by(key: SUBMITTED[:key])
    return write!(SUBMITTED) if submitted.nil? || submitted.body == RAKE_SUBMITTED_BODY

    # Hand-edited: keep the words, but the notice now goes as both a
    # Notification and an email.
    submitted.update!(channel: "both", available_variables: SUBMITTED[:available_variables])
  end

  def down
    Template.where(key: TEMPLATES.map { |t| t[:key] }).delete_all
  end

  private

  def write!(attrs)
    template = Template.find_or_initialize_by(key: attrs[:key])
    template.assign_attributes(
      name: attrs[:name],
      subject: attrs[:subject],
      body: attrs[:body],
      category: "payments",
      channel: "both",
      active: true,
      available_variables: attrs[:available_variables]
    )
    template.save!
  end
end
