# frozen_string_literal: true

# What every Prawn renderer here needs: text the built-in font can print, money,
# and a light rule between sections.
module PdfHelpers
  private

  # The built-in PDF font only covers Windows-1252; drop anything outside it
  # so a stray emoji or em-space can't crash a render.
  def winansi(str)
    str.to_s.encode("Windows-1252", undef: :replace, invalid: :replace, replace: "").encode("UTF-8")
  rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
    str.to_s
  end

  def money(cents)
    winansi(ActiveSupport::NumberHelper.number_to_currency(cents.to_i / 100.0))
  end

  def rule(pdf, gap: 10)
    pdf.move_down gap
    pdf.stroke_color "cccccc"
    pdf.stroke_horizontal_rule
    pdf.stroke_color "000000"
    pdf.move_down gap
  end
end
