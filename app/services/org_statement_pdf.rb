# frozen_string_literal: true

require "prawn"
require "prawn/table"

# A theater's monthly CocoScout statement as a PDF (bytes). Pure renderer:
# OrgStatementJob calls it off the request thread and attaches the result.
class OrgStatementPdf
  def initialize(statement)
    @statement = statement
    @t = statement.totals
  end

  def render
    Prawn::Fonts::AFM.hide_m17n_warning = true
    pdf = Prawn::Document.new(page_size: "LETTER", margin: 54)
    pdf.text plain("#{@statement.organization.name}: CocoScout statement"), size: 18, style: :bold
    pdf.text plain(@statement.label), size: 11, color: "666666"
    pdf.move_down 6
    pdf.text plain("Plan: #{@t['plan']}"), size: 9, color: "666666"
    pdf.move_down 16

    section(pdf, "What you paid CocoScout")
    rows = (@t["paid"] || []).map { |label, cents| [ plain(label), money(cents) ] }
    rows << [ "Nothing this month", "" ] if rows.empty?
    rows << [ "Total", money(@t["total_paid_cents"]) ]
    table(pdf, rows, bold_last: true)
    if @t["paid_tickets"].to_i.positive?
      pdf.move_down 4
      pdf.text plain("#{@t['paid_tickets']} paid #{@t['paid_tickets'] == 1 ? 'ticket' : 'tickets'} at 50¢. Of the ticket fees and card processing, buyers paid #{money(@t['fees_paid_by_buyers_cents'])} and you paid #{money(@t['fees_paid_by_you_cents'])}. Ticket and course fees come out of the money before it reaches your balance."), size: 8, color: "666666"
    end
    if (@t["bills"] || []).any?
      pdf.move_down 10
      pdf.text "Bills", size: 10, style: :bold
      bill_rows = @t["bills"].map { |b| [ plain([ b["label"], b["period"], b["number"] ].compact.join(" · ")), plain(b["status"]), money(b["amount_cents"]) ] }
      table(pdf, bill_rows)
    end

    pdf.move_down 18
    section(pdf, "Your CocoScout balance")
    balance = [ [ "Opening balance", money(@t["opening_cents"]) ] ]
    balance += (@t["money_in"] || []).map { |label, cents| [ plain(label), money(cents) ] }
    balance += (@t["money_out"] || []).map { |label, cents| [ plain(label), money(cents) ] }
    balance << [ "Closing balance", money(@t["closing_cents"]) ]
    table(pdf, balance, bold_last: true)

    pdf.move_down 24
    pdf.text "Questions about this statement? Reply to the email it came with.", size: 8, color: "888888"
    pdf.render
  end

  private

  def section(pdf, title)
    pdf.text title, size: 12, style: :bold
    pdf.move_down 6
  end

  def table(pdf, rows, bold_last: false)
    pdf.table(rows, width: pdf.bounds.width, cell_style: { size: 9, borders: [ :bottom ], border_color: "dddddd", padding: [ 5, 4 ] }) do |t|
      t.columns(-1).align = :right
      t.row(-1).font_style = :bold if bold_last
    end
  end

  def money(cents)
    plain(ActiveSupport::NumberHelper.number_to_currency(cents.to_i / 100.0))
  end

  # The built-in PDF font only covers Windows-1252.
  def plain(str)
    str.to_s.encode("Windows-1252", undef: :replace, invalid: :replace, replace: "").encode("UTF-8")
  end
end
