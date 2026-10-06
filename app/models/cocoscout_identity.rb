# frozen_string_literal: true

# CocoScout's own business details, for the invoices it issues organizations
# (Pro and usage) and the "payments processed by" line on theirs. Public
# details, so they live here rather than in credentials.
module CocoScoutIdentity
  LEGAL_NAME = "Coco Runs Everything LLC"
  BRAND = "CocoScout"
  ADDRESS_LINES = [ "1714 S. Desplaines St.", "Chicago, IL 60616" ].freeze
  EMAIL = "info@cocoscout.com"
  LOGO_PATH = Rails.root.join("app/assets/images/cocoscoutsmall.png")

  def self.party
    InvoiceDocument::Party.new(name: "#{BRAND} (#{LEGAL_NAME})", lines: ADDRESS_LINES, email: EMAIL)
  end
end
