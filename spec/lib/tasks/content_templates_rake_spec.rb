# frozen_string_literal: true

require "rails_helper"

# The payee payout notices ship their copy from a migration, not the seed task,
# so this guards the property that made them worth splitting in the first
# place: each one must read as a complete message on its own, with no
# conditional blocks that vanish when the superadmin editor previews them
# without variables.
RSpec.describe "payee payout notice templates" do
  KEYS = %w[
    payout_sent_to_payee
    payout_sent_to_payee_first_payment
    payout_sent_to_payee_no_bank
  ].freeze

  it "are all present, on both channels, and filed under payments" do
    KEYS.each do |key|
      template = ContentTemplate.find_by(key: key)
      expect(template).to be_present, "missing content template #{key}"
      expect(template.channel).to eq("both")
      expect(template.category).to eq("payments")
      expect(template).to be_active
    end
  end

  it "never collapse to an empty message when previewed with no variables" do
    KEYS.each do |key|
      template = ContentTemplate.find_by(key: key)

      # This is exactly what the superadmin preview does. The old single
      # all-conditional template rendered down to a greeting and a link here.
      previewed = ContentTemplate.interpolate(template.body, {})
      words = previewed.gsub(%r{<[^>]+>}, " ").gsub(/\{\{\w+\}\}/, " ").split.size

      expect(previewed).not_to include("{{#"), "#{key} still has conditional blocks"
      expect(words).to be > 15, "#{key} previews as near-empty copy (#{words} words)"
    end
  end

  it "each say what the payee actually needs to know" do
    base = {
      recipient_name: "Allison", organization_name: "Stars and Garters", amount: "$150.00",
      expected_window: "August 7 – August 11, 2026",
      payments_url: "https://cocoscout.example/my/payments",
      setup_url: "https://cocoscout.example/my/payments/setup"
    }

    standard = ContentTemplateService.render("payout_sent_to_payee", base)
    first    = ContentTemplateService.render("payout_sent_to_payee_first_payment", base)
    no_bank  = ContentTemplateService.render("payout_sent_to_payee_no_bank", base)

    # Everyone learns the amount, who sent it, and where to see the detail.
    [ standard, first, no_bank ].each do |rendered|
      expect(rendered[:subject]).to be_present
      expect(rendered[:body]).to include("$150.00").and include("Stars and Garters")
      expect(rendered[:body]).not_to include("{{")
      # Tim's rule: never name the payout provider to a payee.
      expect(rendered[:body]).not_to match(/stripe/i)
    end

    expect(standard[:body]).to include("August 7")
    expect(standard[:body]).not_to include("first payment")

    expect(first[:body]).to include("first payment through CocoScout").and include("our payout provider")

    expect(no_bank[:subject]).to include("waiting for you")
    expect(no_bank[:body]).to include("set aside").and include(base[:setup_url])
  end
end
