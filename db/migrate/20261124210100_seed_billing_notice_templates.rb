# frozen_string_literal: true

# The words of the failed-payment email and the yearly renewal reminder.
# Rendering a missing key raises, so they're seeded here.
class SeedBillingNoticeTemplates < ActiveRecord::Migration[8.1]
  KEYS = %w[cocoscout_payment_failed cocoscout_pro_renewal].freeze

  def up
    PlatformTemplates.ensure!(keys: KEYS)
  end

  def down
    ContentTemplate.where(key: KEYS).delete_all
  end
end
