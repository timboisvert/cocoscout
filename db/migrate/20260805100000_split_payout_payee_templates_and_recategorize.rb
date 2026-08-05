# frozen_string_literal: true

# The payee payout notice started life as one template whose whole body was
# conditional blocks ({{#first_payout}}…). ContentTemplate#interpolate strips
# every block whose flag isn't set, so with no variables — exactly how the
# superadmin editor previews it — the entire message collapsed to a greeting
# and a link. Unreadable to edit, unpreviewable, and one missing flag away
# from sending that empty thing for real.
#
# Split into three plain templates, one per situation. The job picks the key.
#
# Owned by this migration rather than the seed rake task so production gets
# correct copy on deploy instead of depending on someone remembering a manual
# step — the payout job raises if its template is missing, and that job now
# runs inside the paying path.
class SplitPayoutPayeeTemplatesAndRecategorize < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "content_templates"
  end

  SHARED_VARIABLES = %w[recipient_name organization_name amount payments_url].freeze

  TEMPLATES = [
    {
      key: "payout_sent_to_payee",
      name: "Payout Sent — on its way (payee)",
      subject: "{{amount}} is on its way from {{organization_name}}",
      body: "<p>Hi {{recipient_name}},</p>" \
            "<p><strong>{{organization_name}}</strong> just sent you <strong>{{amount}}</strong>.</p>" \
            "<p>It should reach your bank account <strong>{{expected_window}}</strong>.</p>" \
            "<p><a href=\"{{payments_url}}\">View this payment in My Payments</a></p>",
      available_variables: SHARED_VARIABLES + %w[expected_window]
    },
    {
      key: "payout_sent_to_payee_first_payment",
      name: "Payout Sent — first payment (payee)",
      subject: "{{amount}} is on its way from {{organization_name}}",
      body: "<p>Hi {{recipient_name}},</p>" \
            "<p><strong>{{organization_name}}</strong> just sent you <strong>{{amount}}</strong> — " \
            "your first payment through CocoScout.</p>" \
            "<p>First payments take a bit longer than usual: our payout provider needs extra time to " \
            "finish setting up your account. Expect this one <strong>{{expected_window}}</strong>. " \
            "After this, payments normally arrive within a few business days.</p>" \
            "<p><a href=\"{{payments_url}}\">View this payment in My Payments</a></p>",
      available_variables: SHARED_VARIABLES + %w[expected_window]
    },
    {
      key: "payout_sent_to_payee_no_bank",
      name: "Payout Sent — waiting on a bank account (payee)",
      subject: "{{amount}} from {{organization_name}} is waiting for you",
      body: "<p>Hi {{recipient_name}},</p>" \
            "<p><strong>{{organization_name}}</strong> has <strong>{{amount}}</strong> set aside for you.</p>" \
            "<p>We can't send it yet — there's no bank account on your profile. " \
            "Add one and your money will be on its way.</p>" \
            "<p><a href=\"{{setup_url}}\">Add your bank account</a></p>" \
            "<p><a href=\"{{payments_url}}\">View this payment in My Payments</a></p>",
      available_variables: SHARED_VARIABLES + %w[setup_url]
    }
  ].freeze

  # Two templates sat in a catch-all "notifications" category; file them with
  # the section of the app they belong to.
  RECATEGORIZED = { "payout_run_submitted" => "payments", "contract_signed_manager" => "contracts" }.freeze

  def up
    TEMPLATES.each do |attrs|
      row = Template.find_or_initialize_by(key: attrs[:key])
      row.assign_attributes(
        name: attrs[:name],
        subject: attrs[:subject],
        body: attrs[:body],
        available_variables: attrs[:available_variables],
        category: "payments",
        channel: "both",
        active: true
      )
      row.save!
    end

    RECATEGORIZED.each { |key, category| Template.where(key: key).update_all(category: category) }
  end

  def down
    Template.where(key: %w[payout_sent_to_payee_first_payment payout_sent_to_payee_no_bank]).delete_all
    RECATEGORIZED.each_key { |key| Template.where(key: key).update_all(category: "notifications") }
  end
end
