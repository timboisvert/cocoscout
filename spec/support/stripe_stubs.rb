# frozen_string_literal: true

# PayoutFundingService.ach_configuration_id asks Stripe which payment-method
# configuration allows ACH before every bank debit. Specs never talk to
# Stripe, so answer "none" everywhere; a spec that cares stubs its own list.
RSpec.configure do |config|
  config.before(:each) do
    allow(Stripe::PaymentMethodConfiguration).to receive(:list).and_return(double("pmc_list", data: []))
  end
end
