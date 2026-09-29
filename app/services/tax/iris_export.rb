# frozen_string_literal: true

require "csv"

module Tax
  # Bulk 1099-NEC upload for the IRS Information Returns Intake System (IRIS).
  # IRIS accepts CSV per the "Publication 5717 IRIS Application for TCC Taxpayer
  # Portal" template. Columns are the union of every form type; empties are
  # blank. The set below covers the NEC-only fields we produce.
  #
  # This is a Phase 1 exporter: it hands you a file to upload, it doesn't
  # transmit. The Phase 3 e-file partner will replace this with an API call
  # and set filed_at itself.
  class IrisExport
    HEADERS = %w[
      RecordType TaxYear PayerName PayerEIN PayerAddress1 PayerAddress2
      PayerCity PayerState PayerZip PayerPhone
      RecipientName RecipientTIN RecipientAddress1 RecipientAddress2
      RecipientCity RecipientState RecipientZip
      NECBox1 FederalWithheld
      Corrected AccountNumber
    ].freeze

    def initialize(forms)
      @forms = forms
    end

    def to_csv
      CSV.generate do |csv|
        csv << HEADERS
        @forms.each { |form| csv << row_for(form) }
      end
    end

    def filename(tax_year)
      "1099-NEC #{tax_year} IRIS #{Time.zone.now.strftime('%Y-%m-%d')}.csv"
    end

    private

    def row_for(form)
      tin_full = form.w9_submission&.tin
      [
        "1099-NEC",
        form.tax_year,
        form.payer_name,
        form.payer_ein_last4.present? ? "*****#{form.payer_ein_last4}" : "",
        form.payer_address_line1, form.payer_address_line2,
        form.payer_city, form.payer_state, form.payer_zip, form.payer_phone,
        form.recipient_name,
        tin_full.presence || "",
        form.recipient_address_line1, form.recipient_address_line2,
        form.recipient_city, form.recipient_state, form.recipient_zip,
        cents_to_dollars(form.reported_box1_cents),
        cents_to_dollars(form.federal_withheld_cents),
        form.corrects_id.present? ? "Y" : "N",
        form.id
      ]
    end

    def cents_to_dollars(cents)
      format("%.2f", cents.to_i / 100.0)
    end
  end
end
