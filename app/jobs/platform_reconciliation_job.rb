# frozen_string_literal: true

# Every morning: bring in Stripe's newest lines, run the money check, and
# email the superadmins when it needs a look.
class PlatformReconciliationJob < ApplicationJob
  queue_as :background

  def perform
    begin
      StripeBalanceImport.run!
    rescue Stripe::StripeError => e
      Rails.logger.warn("[PlatformReconciliationJob] import failed: #{e.message}")
    end
    row = PlatformReconciliationCheck.run!
    return unless PlatformReconciliationCheck.alert?(row)
    # On a laptop the check compares Stripe's test account with local data,
    # which never agree, so it would email every morning (Tim, 2026-10-12).
    # The check still runs and shows on the Stripe check page; only
    # production's is worth an email.
    return if Rails.env.development?

    variables = PlatformMoneyCheckContent.for(row)
    User::SUPERADMIN_EMAILS.each do |email|
      AppMailer.with(template_key: "cocoscout_money_check", to: email, variables: variables).send_template.deliver_later
    end
  end
end
