# frozen_string_literal: true

module SuperadminFinancesHelper
  # Cents as dollars, e.g. -$12.50.
  def usd(cents)
    cents.nil? ? "—" : number_to_currency(cents.to_i / 100.0)
  end

  # An org's plan in a few words: what it pays CocoScout for.
  def plan_words(org)
    plan = if org.comped_indefinitely? then "Plan comped"
    elsif org.comped? then "Plan comped until #{org.comped_until.strftime('%b %-d')}"
    elsif org.subscription_status == "past_due" then "Pro, past due"
    elsif org.subscription_status.in?(SubscriptionSyncService::ACCESS_STATUSES) then org.subscription_interval == "year" ? "Pro, yearly" : "Pro, monthly"
    else "Free"
    end
    return plan unless org.on_paid_plan?

    "#{plan} · #{org.comped_usage? ? 'usage comped' : 'usage billed'}"
  end

  def plan_tone(org)
    return "bg-red-50 text-red-700 border-red-200" if org.subscription_status == "past_due"
    return "bg-green-50 text-green-700 border-green-200" if org.comped?
    return "bg-pink-50 text-pink-700 border-pink-200" if org.on_paid_plan?

    "bg-gray-50 text-gray-600 border-gray-200"
  end
end
