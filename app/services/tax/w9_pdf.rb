# frozen_string_literal: true

require "prawn"
require "prawn/table"

module Tax
  # Renders a signed W9Submission as a substitute Form W-9 (bytes). The IRS
  # accepts a substitute form as long as it asks for the same information and
  # carries the Part II certification word for word — which this does, with the
  # contractor's electronic signature and when/where they signed.
  #
  # Pure renderer: generated on demand from the encrypted record, never stored,
  # so the full TIN only exists in the bytes handed to whoever opened it.
  class W9Pdf
    def initialize(submission)
      @w9 = submission
    end

    def render
      Prawn::Fonts::AFM.hide_m17n_warning = true
      pdf = Prawn::Document.new(page_size: "LETTER", margin: 54,
                                info: { Title: "Form W-9 — #{winansi(@w9.legal_name)}" })
      header(pdf)
      part_one(pdf)
      part_two(pdf)
      footer(pdf)
      pdf.render
    end

    def filename
      "W-9 #{@w9.legal_name.to_s.gsub(/[^\w\s-]/, '').squish} #{@w9.signed_at.to_date.iso8601}.pdf"
    end

    private

    def header(pdf)
      pdf.text "Substitute Form W-9", size: 20, style: :bold
      pdf.move_down 2
      pdf.text "Request for Taxpayer Identification Number and Certification (Rev. March 2024)", size: 10, color: "555555"
      pdf.move_down 4
      pdf.text "Given to #{winansi(@w9.organization.name)}", size: 9, color: "888888"
      rule(pdf)
    end

    def part_one(pdf)
      rows = [
        [ "1  Name", @w9.legal_name ],
        [ "2  Business name", @w9.business_name.presence || "—" ],
        [ "3a Federal tax classification", @w9.classification_label ],
        [ "4  Exemptions", exemptions_line ],
        [ "5  Address", [ @w9.address_line1, @w9.address_line2 ].compact_blank.join(", ") ],
        [ "6  City, state, ZIP", @w9.city_state_zip ]
      ]
      pdf.table(rows.map { |label, value| [ label, winansi(value) ] },
                width: pdf.bounds.width,
                column_widths: { 0 => 170 },
                cell_style: { size: 10, padding: [ 6, 8 ], border_color: "dddddd" }) do |t|
        t.column(0).font_style = :bold
        t.column(0).background_color = "f7f7f7"
      end

      pdf.move_down 14
      pdf.text "Part I — Taxpayer Identification Number (TIN)", size: 12, style: :bold
      pdf.move_down 6
      label = @w9.tin_type == "ein" ? "Employer identification number" : "Social security number"
      pdf.table([ [ label, @w9.formatted_tin ] ],
                width: pdf.bounds.width,
                column_widths: { 0 => 170 },
                cell_style: { size: 11, padding: [ 6, 8 ], border_color: "dddddd" }) do |t|
        t.column(0).font_style = :bold
        t.column(0).background_color = "f7f7f7"
      end
    end

    def part_two(pdf)
      pdf.move_down 14
      pdf.text "Part II — Certification", size: 12, style: :bold
      pdf.move_down 6
      pdf.text W9Submission::CERTIFICATION_INTRO, size: 9
      W9Submission::CERTIFICATION_ITEMS.each_with_index do |item, i|
        pdf.move_down 3
        pdf.indent(12) { pdf.text "#{i + 1}. #{item}", size: 9 }
      end
      if @w9.subject_to_backup_withholding?
        pdf.move_down 6
        pdf.text "Item 2 crossed out: the signer has been notified by the IRS that they are currently subject to backup withholding.",
                 size: 9, style: :bold
      end

      pdf.move_down 12
      signed = @w9.signed_at.in_time_zone
      pdf.table([
        [ "Signature", "/s/ #{winansi(@w9.signature_name)} (electronically signed)" ],
        [ "Date", signed.strftime("%B %-d, %Y at %-l:%M %p %Z") ]
      ], width: pdf.bounds.width, column_widths: { 0 => 170 },
         cell_style: { size: 10, padding: [ 6, 8 ], border_color: "dddddd" }) do |t|
        t.column(0).font_style = :bold
        t.column(0).background_color = "f7f7f7"
      end
    end

    def footer(pdf)
      rule(pdf)
      details = [ "Signed electronically on CocoScout", "form revision #{@w9.form_revision}" ]
      details << "IP #{@w9.signed_ip}" if @w9.signed_ip.present?
      details << (@w9.e_delivery_consented? ? "consented to electronic 1099 delivery" : "no consent to electronic 1099 delivery")
      pdf.text winansi(details.join(" · ")), size: 8, color: "888888"
    end

    def exemptions_line
      parts = []
      parts << "Exempt payee code #{@w9.exempt_payee_code}" if @w9.exempt_payee_code.present?
      parts << "FATCA code #{@w9.fatca_code}" if @w9.fatca_code.present?
      parts.join(" · ").presence || "None"
    end

    def rule(pdf)
      pdf.move_down 12
      pdf.stroke_color "cccccc"
      pdf.stroke_horizontal_rule
      pdf.stroke_color "000000"
      pdf.move_down 12
    end

    # The built-in PDF font only covers Windows-1252 (see ContractPdf).
    def winansi(str)
      str.to_s.encode("Windows-1252", undef: :replace, invalid: :replace, replace: "").encode("UTF-8")
    rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
      str.to_s
    end
  end
end
