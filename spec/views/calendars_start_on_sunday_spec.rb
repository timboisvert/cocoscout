# frozen_string_literal: true

require "rails_helper"

# Every calendar's week starts on Sunday (Tim, 2026-11-24): the weekday
# header, and where the first of the month lands under it. December 2026
# starts on a Tuesday and ends on a Thursday.
RSpec.describe "Calendars start on Sunday", type: :view do
  def html(...) = Nokogiri::HTML.fragment(render(...))

  let(:december) { Time.zone.local(2026, 12, 1) }

  describe "the shared month calendar" do
    let(:doc) do
      html(partial: "shared/month_calendar",
           locals: { current_month: december, month_link: ->(month) { "/calendar?month=#{month.to_date}" },
                     items_by_date: {}, item_partial: "shared/none" })
    end
    let(:grids) { doc.css(".grid.grid-cols-7") }

    it "heads the columns Sunday to Saturday" do
      expect(grids.first.element_children.map { |cell| cell.text.squish }).to eq(%w[Sun Mon Tue Wed Thu Fri Sat])
    end

    it "puts the 1st under its weekday and fills the last week out to Saturday" do
      cells = grids[1].element_children.map { |cell| cell.text.squish }

      expect(cells.size).to eq(35)
      expect(cells.first(3)).to eq([ "", "", "1" ])
      expect(cells.last(3)).to eq([ "31", "", "" ])
    end

    it "starts the current month at this week's Sunday when asked to start from the current week" do
      travel_to Time.zone.local(2026, 12, 16, 12) do
        doc = html(partial: "shared/month_calendar",
                   locals: { current_month: december, month_link: ->(month) { "/calendar?month=#{month.to_date}" },
                             items_by_date: {}, item_partial: "shared/none", start_from_current_week: true })
        cells = doc.css(".grid.grid-cols-7")[1].element_children.map { |cell| cell.text.squish }

        # Wednesday the 16th: the grid opens on Sunday the 13th, in the first column.
        expect(cells.first).to eq("13")
      end
    end
  end

  describe "the small month in a day picker" do
    let(:doc) do
      html(partial: "shared/mini_month",
           locals: { month: december.to_date, pick: :day, day_path: ->(day) { "/day/#{day}" }, selected_day: Date.new(2026, 12, 10) })
    end

    it "heads the columns Sunday to Saturday" do
      expect(doc.css(".grid.grid-cols-7").first.element_children.map(&:text)).to eq(%w[S M T W T F S])
    end

    it "puts the 1st under Tuesday" do
      cells = doc.css(".grid.grid-cols-7")[1].element_children

      expect(cells.first(3).map { |cell| cell.text.squish }).to eq([ "", "", "1" ])
      expect(cells.size).to eq(35)
    end
  end

  # The week picker on Scheduling and Home picks a week of the staff schedule,
  # which runs Monday to Sunday (Shift#week_start), so each row is that week.
  it "keeps the week picker's rows on the staff schedule's week" do
    doc = html(partial: "shared/mini_month",
               locals: { month: december.to_date, pick: :week, week_path: ->(week) { "/week/#{week}" }, selected_week: Date.new(2026, 12, 7) })

    expect(doc.css(".grid.grid-cols-7").first.element_children.map(&:text)).to eq(%w[M T W T F S S])
    expect(doc.css("[data-week-row]").map { |row| row["data-week-row"] }).to all(satisfy { |day| Date.iso8601(day).monday? })
  end

  it "has no view that asks a calendar for another first day" do
    views = Dir[Rails.root.join("app/views/**/*.erb")]
    offenders = views.select { |path| File.read(path).match?(/week_starts_on|beginning_of_week\(:monday\)/) }

    expect(offenders.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }).to eq([])
  end
end
