# frozen_string_literal: true

require "prawn"
require "prawn/table"

# Renders an executed contract to a PDF (bytes). Pure renderer — no I/O, no
# persistence; GenerateContractPdfJob calls this off the request thread and
# attaches the result as a ContractDocument.
#
# The body is the exact document that was signed (the organization's
# content_snapshot), so the PDF matches what both parties agreed to. It's our own
# generated HTML (rich-text template wording + a Deal Terms table), so a small
# Nokogiri walker maps the tags we actually emit onto Prawn.
class ContractPdf
  def initialize(contract)
    @contract = contract
  end

  def render
    Prawn::Fonts::AFM.hide_m17n_warning = true
    pdf = Prawn::Document.new(page_size: "LETTER", margin: 54)
    render_header(pdf)
    render_body(pdf)
    render_signatures(pdf)
    pdf.render
  end

  private

  # The built-in PDF font only covers Windows-1252; drop anything outside it so a
  # stray glyph in a template can never raise mid-render and kill the job.
  def winansi(str)
    str.to_s.encode("Windows-1252", undef: :replace, invalid: :replace, replace: "").encode("UTF-8")
  rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
    str.to_s
  end

  def render_header(pdf)
    title = @contract.production_name.presence || @contract.production&.name || "Contract Agreement"
    pdf.text esc(title), size: 20, style: :bold, inline_format: true
    pdf.move_down 4
    parties = "#{@contract.organization.name} and #{@contract.contractor_name}"
    parties += " · Executed #{@contract.executed_at.strftime('%B %-d, %Y')}" if @contract.executed_at
    pdf.text esc(parties), size: 9, color: "888888", inline_format: true
    pdf.move_down 12
    pdf.stroke_color "cccccc"
    pdf.stroke_horizontal_rule
    pdf.stroke_color "000000"
    pdf.move_down 12
  end

  def render_body(pdf)
    html = @contract.organization_signature&.content_snapshot.presence || @contract.render_signable_document
    Nokogiri::HTML.fragment(html.to_s).children.each do |node|
      if node.text?
        t = node.text.strip
        pdf.text esc(t), inline_format: true, size: 10 unless t.empty?
      else
        render_block(pdf, node)
      end
    end
  end

  def render_block(pdf, node)
    case node.name
    when "h1" then heading(pdf, node, 16)
    when "h2" then heading(pdf, node, 14)
    when "h3" then heading(pdf, node, 13)
    when "h4", "h5", "h6" then heading(pdf, node, 11)
    when "hr"
      pdf.move_down 6
      pdf.stroke_color "cccccc"
      pdf.stroke_horizontal_rule
      pdf.stroke_color "000000"
      pdf.move_down 6
    when "ul", "ol" then render_list(pdf, node, ordered: node.name == "ol")
    when "table" then render_table(pdf, node)
    when "br" then pdf.move_down 4
    else
      # div / p / blockquote / span / anything else → a paragraph.
      text = inline(node).strip
      if text.empty?
        pdf.move_down 6 # our template uses <div><br></div> as spacers
      else
        pdf.text text, inline_format: true, size: 10, leading: 2
        pdf.move_down 4
      end
    end
  end

  def heading(pdf, node, size)
    text = inline(node).strip
    return if text.empty?

    pdf.move_down 4
    pdf.text text, inline_format: true, size: size, style: :bold
    pdf.move_down 3
  end

  def render_list(pdf, node, ordered:)
    items = node.element_children.select { |c| c.name == "li" }
    items.each_with_index do |li, i|
      bullet = ordered ? "#{i + 1}." : "•"
      pdf.indent(14) do
        pdf.text "#{bullet}  #{inline(li).strip}", inline_format: true, size: 10, leading: 2
      end
    end
    pdf.move_down 4
  end

  def render_table(pdf, node)
    rows = node.css("tr").map do |tr|
      tr.css("th, td").map { |c| winansi(c.text.strip) }
    end.reject(&:empty?)
    return if rows.empty?

    has_header = node.css("thead tr").any?
    pdf.move_down 4
    pdf.table(rows, width: pdf.bounds.width, cell_style: { size: 9, padding: [ 4, 6 ], border_color: "dddddd" }) do |t|
      t.row(0).font_style = :bold if has_header
      t.row(0).background_color = "f5f5f5" if has_header
    end
    pdf.move_down 6
  rescue StandardError
    # Never let a table quirk kill the whole PDF — fall back to plain text.
    rows.each { |r| pdf.text esc(r.join("   ·   ")), size: 9, inline_format: true }
    pdf.move_down 4
  end

  def render_signatures(pdf)
    pdf.move_down 18
    pdf.stroke_color "cccccc"
    pdf.stroke_horizontal_rule
    pdf.stroke_color "000000"
    pdf.move_down 10
    pdf.text "Signatures", size: 13, style: :bold
    pdf.move_down 8

    @contract.contract_signatures.sort_by { |s| s.signed_at || Time.current }.each do |sig|
      role = sig.role_organization? ? @contract.organization.name : "Contractor"
      pdf.text "<b>#{esc(sig.signer_name.to_s)}</b>  —  #{esc(role)}", inline_format: true, size: 10
      meta = []
      meta << "Signed #{sig.signed_at.strftime('%B %-d, %Y at %-l:%M %p')}" if sig.signed_at
      meta << "IP #{sig.ip_address}" if sig.ip_address.present?
      meta << sig.signer_email if sig.signer_email.present?
      pdf.text esc(meta.join("  ·  ")), size: 8, color: "666666", inline_format: true
      pdf.text "Signed electronically via CocoScout", size: 8, color: "999999"
      pdf.move_down 8
    end
  end

  # Build Prawn inline markup (<b>/<i>) from a node's children, escaping text.
  def inline(node)
    node.children.map { |child| inline_child(child) }.join
  end

  def inline_child(node)
    case node.name
    when "text" then esc(node.text)
    when "br" then "\n"
    when "strong", "b" then "<b>#{inline(node)}</b>"
    when "em", "i" then "<i>#{inline(node)}</i>"
    when "u" then "<u>#{inline(node)}</u>"
    else inline(node) # unwrap unknown/inline tags (a, span, …), keep their text
    end
  end

  # Escape for Prawn's inline_format (which parses <b>, <i>, & etc.), and drop any
  # glyphs the built-in font can't render.
  def esc(str)
    winansi(str).gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
  end
end
