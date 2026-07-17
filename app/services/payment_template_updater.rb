# frozen_string_literal: true

# Environment-aware, idempotent updates to payment-related content templates for
# the Venmo/Zelle -> Stripe-bank transition. Reads each template as it exists in
# THIS environment (dev/prod bodies differ) and adjusts in place, so it's safe to
# run anywhere and safe to re-run (re-runs are no-ops). Driven by the
# `content_templates:apply_payment_updates` rake task.
module PaymentTemplateUpdater
  module_function

  # Generic phrase swaps applied across a template's subject/body/description so
  # the update works regardless of the exact wording in a given environment.
  REPLACEMENTS = {
    "Venmo or Zelle" => "bank account",
    "Venmo/Zelle" => "bank account",
    "Venmo and Zelle" => "bank account",
    "Venmo, Zelle" => "your bank account"
  }.freeze

  # Existing templates that may still reference the old payment apps.
  REMINDER_KEYS = %w[payment_setup_reminder].freeze

  NUDGE_KEY = "payment_setup_nudge"

  # Returns an array of human-readable log lines describing what changed.
  def apply!
    [ ensure_nudge!, *refresh_reminders! ]
  end

  # The nudge appended to cast/talent-pool messages when a recipient hasn't
  # connected a bank yet. Created if absent; if it already exists we leave the
  # body alone (respecting local customization) and only ensure it's active.
  def ensure_nudge!
    nudge = ContentTemplate.find_or_initialize_by(key: NUDGE_KEY)

    if nudge.new_record?
      nudge.assign_attributes(
        name: "Payment Setup Nudge",
        category: "payments",
        channel: "message",
        template_type: "structured",
        subject: "Set up your payment details",
        description: "Appended to cast / talent-pool messages when the recipient hasn't connected a bank yet.",
        active: true,
        body: <<~HTML.strip,
          <hr>
          <p><strong>Getting paid through CocoScout.</strong> We pay you straight to your bank account. If you haven't set that up yet, it only takes a minute: <a href="{{payment_setup_url}}">set up your payment details</a>.</p>
        HTML
        available_variables: [ { "name" => "payment_setup_url", "description" => "URL to the payment setup page" } ]
      )
      nudge.save!
      "#{NUDGE_KEY}: created"
    elsif !nudge.active?
      nudge.update!(active: true)
      "#{NUDGE_KEY}: reactivated"
    else
      "#{NUDGE_KEY}: already present (left as-is)"
    end
  end

  # Targeted, idempotent phrase replacement on existing reminder templates.
  def refresh_reminders!
    REMINDER_KEYS.map do |key|
      template = ContentTemplate.find_by(key: key)
      next "#{key}: not present (skipped)" unless template

      before = template_fields(template)
      %i[subject body description].each do |field|
        text = template.public_send(field)
        next if text.blank?

        REPLACEMENTS.each { |from, to| text = text.gsub(from, to) }
        template.public_send("#{field}=", text)
      end

      if template_fields(template) == before
        "#{key}: already current"
      else
        template.save!
        "#{key}: updated (removed Venmo/Zelle wording)"
      end
    end
  end

  def template_fields(template)
    [ template.subject, template.body, template.description ]
  end
end
