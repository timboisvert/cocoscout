# frozen_string_literal: true

# An organization's invoices for money it's owed under contracts: numbered in
# order (SG-0012), from the details it sets in Contract Settings → Invoices.
# Anything it leaves blank falls back to what CocoScout already knows (its
# name, its tax address, its support email).
module IssuesInvoices
  extend ActiveSupport::Concern

  # What an organization can set on its invoices (invoice_details).
  INVOICE_DETAIL_KEYS = %w[name address email phone note].freeze

  included do
    has_many :contract_invoices, dependent: :destroy

    normalizes :invoice_prefix, with: ->(prefix) { prefix.to_s.strip.upcase.presence }
    validates :invoice_prefix, format: { with: /\A[A-Z0-9]{1,8}\z/, message: "can only be letters and numbers, up to 8" }, allow_nil: true
  end

  class_methods do
    # "Stars & Garters" → "SG"; a one-word name gives its first three letters.
    def invoice_initials(name)
      words = name.to_s.scan(/[A-Za-z0-9]+/)
      initials = words.map { |word| word[0] }.join.upcase.first(4)
      return initials if initials.length >= 2

      words.join.upcase.first(3).presence || "INV"
    end
  end

  def invoice_prefix_or_default
    invoice_prefix.presence || self.class.invoice_initials(name)
  end

  # The details saved in settings, over the ones CocoScout already knows.
  def invoice_details_with_defaults
    defaults_for_invoices.merge(Hash(invoice_details).slice(*INVOICE_DETAIL_KEYS).compact_blank)
  end

  def defaults_for_invoices
    tax = tax_setting
    city_line = [ [ tax&.city, tax&.state ].compact_blank.join(", "), tax&.zip ].compact_blank.join(" ")
    {
      "name" => name.to_s,
      "address" => [ tax&.address_line1, tax&.address_line2, city_line ].compact_blank.join("\n"),
      "email" => ticketing_profile&.support_email.presence || owner&.email_address,
      "phone" => tax&.phone,
      "note" => ""
    }
  end

  # Who the invoice is from.
  def invoice_seller
    details = invoice_details_with_defaults
    InvoiceDocument::Party.new(name: details["name"], lines: details["address"].to_s.split(/\r?\n/).map(&:strip),
                               email: details["email"], phone: details["phone"])
  end

  # Where a payer's reply to an invoice or receipt goes.
  def invoice_reply_to
    invoice_details_with_defaults["email"].presence
  end
end
