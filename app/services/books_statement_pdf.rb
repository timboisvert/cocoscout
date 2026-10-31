# frozen_string_literal: true

require "prawn"
require "prawn/table"

# A statement (BooksStatements::Statement) as a PDF, letter size.
class BooksStatementPdf
  include PdfHelpers

  def initialize(organization, statement)
    @organization = organization
    @s = statement
  end

  def render
    Prawn::Fonts::AFM.hide_m17n_warning = true
    pdf = Prawn::Document.new(page_size: "LETTER", margin: 54, info: { Title: winansi("#{@organization.name}: #{@s.title}") })
    pdf.text winansi(@organization.name), size: 16, style: :bold
    pdf.text winansi(@s.title), size: 13
    pdf.text winansi("#{@s.subtitle} · #{@s.basis_note}"), size: 9, color: "666666"
    pdf.move_down 14
    cols = @s.columns
    @s.sections.each do |section|
      pdf.text winansi(section.title), size: 10, style: :bold
      pdf.move_down 3
      rows = section.lines.map { |l| [ winansi(l.label), money(l.cents) ] + cols.map { |pid, _| money(l.by_production[pid].to_i) } }
      rows << [ "Nothing", "" ] + cols.map { "" } if rows.empty?
      rows << [ winansi(section.total_label), money(section.total_cents) ] + cols.map { |pid, _| money(section.by_production[pid].to_i) }
      header = cols.any? ? [ [ "", "Total" ] + cols.map { |_, name| winansi(name) } ] : []
      pdf.table(header + rows, width: pdf.bounds.width, cell_style: { size: 9, borders: [], padding: [ 2, 4 ] }) do |t|
        t.columns(1..-1).align = :right
        t.row(-1).font_style = :bold
        t.row(0).font_style = :bold if cols.any?
      end
      pdf.move_down 10
    end
    rule(pdf, gap: 4)
    pdf.table([ [ winansi(@s.bottom.label), money(@s.bottom.cents) ] + cols.map { |pid, _| money(@s.bottom.by_production[pid].to_i) } ],
              width: pdf.bounds.width, cell_style: { size: 10, borders: [], padding: [ 2, 4 ], font_style: :bold }) { |t| t.columns(1..-1).align = :right }
    pdf.move_down 20
    pdf.text winansi("From CocoScout Books, #{Time.current.strftime('%B %-d, %Y')}.#{@organization.books_locked_through ? " Books locked through #{BooksLock.label(@organization)}." : ''}"), size: 8, color: "999999"
    pdf.render
  end
end
