# frozen_string_literal: true

# Where Apple Pay, Google Pay and the rest stand on CocoScout's Stripe
# account, in plain lines (bin/rails stripe:wallets). Read-only except
# register!, which adds the payment method domains Elements needs.
#
# Our checkouts (tickets, passes, courses) use the Payment Element with
# dynamic payment methods, so what buyers see is the account's default
# payment method configuration, on the domains registered here. The hosted
# contract pay page is Stripe's own domain and needs no registration.
class StripeWalletCheck
  DOMAINS = %w[cocoscout.com www.cocoscout.com].freeze

  # Card-priced and confirmed on the spot: what checkout should offer.
  WANTED = %w[card apple_pay google_pay link].freeze

  # Why each of the others doesn't belong in our checkout.
  UNWANTED = {
    "us_bank_account" => "ACH bank debit takes up to 4 business days to clear: the buyer's hold expires first, and it hides Link's instant bank payments",
    "klarna" => "about 6% plus 30¢ a payment, twice what the buyer's fees cover",
    "affirm" => "about 6% a payment, twice what the buyer's fees cover",
    "afterpay_clearpay" => "about 6% plus 30¢ a payment, twice what the buyer's fees cover",
    "cashapp" => "a wallet you said you don't need",
    "amazon_pay" => "a wallet you said you don't need",
    "paypal" => "different fees and flows from cards",
    "zip" => "buy now, pay later: higher fees",
    "revolut_pay" => "a wallet you said you don't need",
    "crypto" => "stablecoin payments, not needed for tickets and classes"
  }.freeze

  # Methods a US buyer paying in dollars can be shown. Everything else on the
  # list (Bancontact, Pix, Kakao Pay...) needs another currency or country,
  # so it never appears in our checkout whatever its switch says.
  US_DOLLAR = (WANTED + %w[us_bank_account klarna affirm afterpay_clearpay cashapp amazon_pay zip crypto]).freeze

  def self.report(out = $stdout, days: 30)
    new(out).report(days: days)
  end

  def self.register!(out = $stdout, domains: DOMAINS)
    new(out).register!(domains)
  end

  def initialize(out)
    @out = out
  end

  def report(days:)
    domains_section
    methods_section
    usage_section(days)
  end

  def register!(domains)
    existing = Stripe::PaymentMethodDomain.list(limit: 100).auto_paging_each.index_by(&:domain_name)
    domains.each do |name|
      domain = existing[name] || Stripe::PaymentMethodDomain.create(domain_name: name)
      domain = Stripe::PaymentMethodDomain.validate(domain.id)
      say "#{existing[name] ? 'Already registered' : 'Registered'} #{name}: #{statuses(domain)}"
    end
  end

  private

  def say(line = "")
    @out.puts(line)
  end

  def domains_section
    say "Payment method domains (Apple Pay and Google Pay show only on these):"
    domains = Stripe::PaymentMethodDomain.list(limit: 100).auto_paging_each.to_a
    DOMAINS.each do |name|
      domain = domains.find { |d| d.domain_name == name }
      say(domain ? "  #{name}: #{statuses(domain)}" : "  #{name}: NOT REGISTERED. Run bin/rails stripe:register_payment_domains, or add it in the Dashboard.")
    end
    (domains.map(&:domain_name) - DOMAINS).each do |name|
      say "  #{name}: #{statuses(domains.find { |d| d.domain_name == name })} (also registered)"
    end
    say
  end

  def statuses(domain)
    parts = %w[apple_pay google_pay link].map do |method|
      detail = domain.respond_to?(method) ? domain.public_send(method) : nil
      status = detail&.status || "unknown"
      error = detail&.status_details&.error_message if detail.respond_to?(:status_details)
      "#{method.tr('_', ' ')} #{status}#{" (#{error})" if error.present?}"
    end
    "#{domain.enabled ? '' : 'DISABLED · '}#{parts.join(', ')}"
  end

  def methods_section
    config = Stripe::PaymentMethodConfiguration.list(limit: 100).auto_paging_each.find(&:is_default)
    unless config
      say "No default payment method configuration found."
      return say
    end

    offered = config.to_hash.select { |_, v| v.is_a?(Hash) && v[:available] }.keys.map(&:to_s).sort
    say "What checkout offers now (default configuration \"#{config.name}\"):"
    WANTED.each { |method| say "  #{method.tr('_', ' ')}: #{offered.include?(method) ? 'on' : 'OFF, turn it on'}" }
    ((offered - WANTED) & US_DOLLAR).each do |method|
      say "  #{method.tr('_', ' ')}: on, and US buyers can see it. Turn it off: #{UNWANTED[method] || 'not needed for tickets and classes'}"
    end
    harmless = offered - US_DOLLAR
    say "  Also on, but never shown for US dollar payments: #{harmless.map { |m| m.tr('_', ' ') }.join(', ')}" if harmless.any?
    say
  end

  def usage_section(days)
    tally = Hash.new(0)
    Stripe::Charge.list(created: { gte: days.days.ago.to_i }, limit: 100).auto_paging_each.first(2000).each do |charge|
      next unless charge.paid

      details = charge.payment_method_details
      kind = details&.type.to_s
      wallet = details&.card&.wallet&.type if kind == "card" && details.card.respond_to?(:wallet)
      tally[wallet.present? ? "card via #{wallet.tr('_', ' ')}" : kind.tr("_", " ")] += 1
    end
    say "How people paid in the last #{days} days (successful charges):"
    if tally.empty?
      say "  none"
    else
      tally.sort_by { |_, count| -count }.each { |kind, count| say "  #{kind}: #{count}" }
    end
  end
end
