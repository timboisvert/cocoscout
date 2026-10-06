# frozen_string_literal: true

require "prawn"
require "prawn/table"

module Tax
  # Renders a TaxForm1099 as a substitute Form 1099-NEC (Copy B) — the
  # recipient's copy. The recipient's TIN is truncated on Copy B; only the
  # payer's copy (Copy C) shows it in full. The IRS's own paper form is a
  # red-ink scannable version we can't reproduce; this substitute is for
  # electronic delivery to the recipient. E-filing goes through IRIS with the
  # bulk CSV export, not by uploading these PDFs.
  class Form1099NecPdf
    include PdfHelpers

    def initialize(form, copy: :recipient)
      @form = form
      @copy = copy
    end

    def render
      Prawn::Fonts::AFM.hide_m17n_warning = true
      pdf = Prawn::Document.new(page_size: "LETTER", margin: 40,
                                info: { Title: "Form 1099-NEC — #{winansi(@form.recipient_name)}" })
      header(pdf)
      parties(pdf)
      amounts(pdf)
      footer(pdf)
      pdf.render
    end

    def filename
      copy_label = @copy == :payer ? "Copy C" : "Copy B"
      "1099-NEC #{@form.tax_year} #{sanitize(@form.recipient_name)} #{copy_label}.pdf"
    end

    private

    def header(pdf)
      pdf.text "Substitute Form 1099-NEC", size: 18, style: :bold
      pdf.text "Nonemployee Compensation · Tax year #{@form.tax_year}", size: 10, color: "555555"
      pdf.move_down 2
      pdf.text(@copy == :payer ? "Copy C — For Payer" : "Copy B — For Recipient", size: 9, color: "888888")
      rule(pdf)
    end

    def parties(pdf)
      recipient_tin = @copy == :payer ? full_recipient_tin_for_payer : @form.masked_recipient_tin

      payer_lines = [
        winansi(@form.payer_name),
        winansi(@form.payer_address_lines.join("\n"))
      ].join("\n")
      payer_lines += "\n#{winansi(@form.payer_phone)}" if @form.payer_phone.present?
      recipient_lines = [
        winansi(@form.recipient_name),
        winansi(@form.recipient_business_name.presence).to_s,
        winansi(@form.recipient_address_lines.join("\n"))
      ].compact_blank.join("\n")

      pdf.table([
        [ "PAYER", "RECIPIENT" ],
        [ payer_lines, recipient_lines ],
        [ "Payer's TIN\n#{@form.masked_payer_ein}", "Recipient's TIN\n#{recipient_tin}" ]
      ], width: pdf.bounds.width, cell_style: { size: 9, padding: [ 6, 8 ], border_color: "cccccc" }) do |t|
        t.row(0).font_style = :bold
        t.row(0).background_color = "f0f0f0"
      end
    end

    def amounts(pdf)
      pdf.move_down 14
      dollars = ->(cents) { "$#{format('%.2f', cents / 100.0)}" }
      pdf.table([
        [ "Box 1 — Nonemployee compensation", dollars.call(@form.reported_box1_cents) ],
        [ "Box 4 — Federal income tax withheld", dollars.call(@form.federal_withheld_cents) ]
      ], width: pdf.bounds.width, column_widths: { 0 => 320 },
         cell_style: { size: 11, padding: [ 8, 10 ], border_color: "cccccc" }) do |t|
        t.column(0).font_style = :bold
        t.column(0).background_color = "f7f7f7"
        t.column(1).align = :right
      end
      if @form.adjustment_cents.nonzero?
        pdf.move_down 6
        note = "Includes a #{dollars.call(@form.adjustment_cents.abs)} adjustment for payments settled outside CocoScout"
        note += ": #{@form.adjustment_note}" if @form.adjustment_note.present?
        pdf.text winansi(note), size: 8, color: "666666", inline_format: true
      end
    end

    def footer(pdf)
      rule(pdf)
      pdf.text "This is a substitute 1099-NEC. Report this income on your federal tax return.", size: 8, color: "888888"
      if @form.corrects_id.present?
        pdf.move_down 4
        pdf.text "CORRECTED — replaces the 1099-NEC previously issued for tax year #{@form.tax_year}.", size: 9, style: :bold, color: "aa0000"
      end
      if @form.status == "filed"
        pdf.move_down 4
        pdf.text "Filed with the IRS on #{@form.filed_at.to_date.strftime('%B %-d, %Y')}#{@form.filing_reference.present? ? " (ref: #{@form.filing_reference})" : ""}.", size: 8, color: "888888"
      end
    end

    # Copy C (payer's copy) shows the recipient's TIN in full. Falls back to
    # the masked TIN when we don't have the current W-9 handy (superseded).
    def full_recipient_tin_for_payer
      # Copy C shows the recipient's TIN in full — the payer already has it.
      return @form.masked_recipient_tin unless @form.w9_submission && @form.w9_submission.tin.present?

      formatted = @form.w9_submission.formatted_tin
      formatted.presence || @form.masked_recipient_tin
    end

    def sanitize(str)
      str.to_s.gsub(/[^\w\s-]/, "").squish.presence || "Recipient"
    end
  end
end
