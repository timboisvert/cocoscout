# frozen_string_literal: true

require "prawn"
require "prawn/table"

# An InvoiceDocument as a PDF (bytes): who it's from, who it's to, what it's
# for, the lines, the total, and where it stands (PAID or VOID stamped on it).
# Pure renderer, served on demand and never stored, so it always matches the
# money it describes.
class InvoicePdf
  include PdfHelpers

  GREEN = "1a7f37"
  GRAY = "666666"

  def initialize(document)
    @doc = document
  end

  def render
    Prawn::Fonts::AFM.hide_m17n_warning = true
    pdf = Prawn::Document.new(page_size: "LETTER", margin: 54, info: { Title: winansi("#{@doc.title} #{@doc.number}") })
    header(pdf)
    rule(pdf, gap: 14)
    parties(pdf)
    pdf.move_down 18
    lines(pdf)
    status(pdf)
    notes(pdf)
    sections(pdf)
    footer(pdf)
    pdf.render
  end

  private

  def header(pdf)
    top = pdf.cursor
    width = pdf.bounds.width
    pdf.bounding_box([ 0, top ], width: width * 0.58) do
      if (logo = logo_image)
        pdf.image logo, fit: [ 140, 52 ]
        pdf.move_down 8
      end
      party(pdf, @doc.seller, size: 12)
    end
    left_bottom = pdf.cursor

    pdf.bounding_box([ width * 0.58, top ], width: width * 0.42) do
      pdf.text winansi(@doc.title.upcase), size: 22, style: :bold, align: :right
      pdf.text winansi(@doc.number), size: 11, align: :right
      pdf.move_down 6
      pdf.text "Issued #{long_date(@doc.issued_on)}", size: 9, color: GRAY, align: :right if @doc.issued_on
      pdf.text "Due #{long_date(@doc.due_on)}", size: 9, color: GRAY, align: :right if @doc.due_on
      if @doc.stamp
        pdf.move_down 10
        pdf.text @doc.stamp, size: 24, style: :bold, align: :right, color: @doc.paid? ? GREEN : "999999", character_spacing: 2
      end
    end
    pdf.move_cursor_to [ left_bottom, pdf.cursor ].min
  end

  def parties(pdf)
    bill_to = [ @doc.bill_to.name, *@doc.bill_to.lines, @doc.bill_to.email, @doc.bill_to.phone ].compact_blank
    reference = @doc.reference.map { |label, value| "#{label}: #{value}" }
    rows = [ [ "BILL TO", reference.any? ? "FOR" : "" ], [ winansi(bill_to.join("\n")), winansi(reference.join("\n")) ] ]
    pdf.table(rows, width: pdf.bounds.width, column_widths: [ pdf.bounds.width / 2 ] * 2,
                    cell_style: { size: 9, borders: [], padding: [ 2, 0, 2, 0 ] }) do |t|
      t.row(0).font_style = :bold
      t.row(0).text_color = GRAY
      t.row(0).size = 8
    end
  end

  def lines(pdf)
    rows = [ [ "Description", "Amount" ] ]
    @doc.items.each do |item|
      text = esc(winansi(item.description))
      text += "\n<font size='8'><color rgb='#{GRAY}'>#{esc(winansi(item.detail))}</color></font>" if item.detail
      rows << [ text, money(item.amount_cents) ]
    end
    rows << [ "Total", money(@doc.total_cents) ]
    pdf.table(rows, width: pdf.bounds.width, column_widths: { 1 => 110 },
                    cell_style: { size: 10, borders: [ :bottom ], border_color: "dddddd", padding: [ 7, 4 ], inline_format: true }) do |t|
      t.row(0).font_style = :bold
      t.row(0).size = 8
      t.row(0).text_color = GRAY
      t.row(-1).font_style = :bold
      t.row(-1).borders = []
      t.columns(1).align = :right
    end
  end

  def status(pdf)
    return if @doc.status_line.blank?

    pdf.move_down 10
    pdf.text winansi(@doc.status_line), size: 10, style: :bold, color: @doc.paid? ? GREEN : "333333"
  end

  def notes(pdf)
    return if @doc.notes.empty?

    pdf.move_down 14
    @doc.notes.each do |note|
      pdf.text winansi(note), size: 9, color: "444444"
      pdf.move_down 4
    end
  end

  def sections(pdf)
    @doc.sections.each do |title, lines|
      pdf.move_down 14
      pdf.text winansi(title), size: 9, style: :bold
      pdf.move_down 3
      pdf.text winansi(lines.join(", ")), size: 9, color: "444444"
    end
  end

  def footer(pdf)
    return if @doc.footer.blank?

    pdf.move_down 20
    pdf.text winansi(@doc.footer), size: 8, color: "888888"
  end

  def party(pdf, party, size:)
    pdf.text winansi(party.name), size: size, style: :bold
    [ *party.lines, party.email, party.phone ].compact_blank.each do |line|
      pdf.text winansi(line), size: 9, color: GRAY
    end
  end

  # A PNG Prawn can draw: CocoScout's own file, or the organization's logo
  # converted. A logo that won't convert is left off rather than failing.
  def logo_image
    logo = @doc.logo
    return nil if logo.blank?
    return logo.to_s if logo.is_a?(String) || logo.is_a?(Pathname)
    return nil unless logo.respond_to?(:attached?) && logo.attached?

    StringIO.new(logo.variant(resize_to_limit: [ 420, 160 ], format: :png).processed.download)
  rescue StandardError => e
    Rails.logger.warn("InvoicePdf: logo left off (#{e.class}: #{e.message})")
    nil
  end

  def long_date(date)
    date.strftime("%B %-d, %Y")
  end

  def esc(text)
    text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
  end
end
