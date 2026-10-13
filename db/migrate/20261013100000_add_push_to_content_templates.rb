# frozen_string_literal: true

# Push notifications from the app get their own switch and copy on each content
# template: "push" turns the phone buzz on or off for the in-app message the
# template creates, and "push_body" is what the notification says (blank means
# the subject). Messages remember which template made them (template_key) and
# the rendered push text, so the phone shows the copy the superadmin wrote.
#
# A few housekeeping notices ship quiet: the superadmin mic filings, the
# sign-up waitlist confirmation, and the payment/payout setup reminders.
class AddPushToContentTemplates < ActiveRecord::Migration[8.1]
  QUIET = %w[mic_submission_filed mic_claim_filed mic_challenge_filed mic_suggestion_filed
             sign_up_queued payment_setup_reminder payout_setup_reminder].freeze

  def up
    add_column :content_templates, :push, :boolean, default: true, null: false
    add_column :content_templates, :push_body, :text
    add_column :messages, :template_key, :string
    add_column :messages, :push_body, :string

    ContentTemplate.where(key: QUIET).update_all(push: false)
  end

  def down
    remove_column :messages, :push_body
    remove_column :messages, :template_key
    remove_column :content_templates, :push_body
    remove_column :content_templates, :push
  end
end
