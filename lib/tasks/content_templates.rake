# frozen_string_literal: true

namespace :content_templates do
  desc "Apply the Stripe-bank payment updates to content templates (idempotent, env-aware)"
  task apply_payment_updates: :environment do
    PaymentTemplateUpdater.apply!.each { |line| puts line }
  end
end
