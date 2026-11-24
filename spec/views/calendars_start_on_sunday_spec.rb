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
  # which runs Sunday through Saturday: each row is that week, named by its Sunday.
  it "draws the week picker's rows Sunday through Saturday" do
    doc = html(partial: "shared/mini_month",
               locals: { month: december.to_date, pick: :week, week_path: ->(week) { "/week/#{week}" }, selected_week: Date.new(2026, 12, 6) })

    expect(doc.css(".grid.grid-cols-7").first.element_children.map(&:text)).to eq(%w[S M T W T F S])
    rows = doc.css("[data-week-row]")
    expect(rows.map { |row| row["data-week-row"] }).to eq(%w[2026-11-29 2026-12-06 2026-12-13 2026-12-20 2026-12-27])
    expect(rows[1]["class"]).to include("bg-pink-500")
    expect(rows[1].css("span").first(7).map(&:text)).to eq(%w[6 7 8 9 10 11 12])
  end

  describe "the week itself" do
    it "starts on Sunday for the staff schedule and everything else that asks for a week" do
      expect(Date.beginning_of_week).to eq(:sunday)
      expect(Date.new(2026, 12, 9).beginning_of_week).to eq(Date.new(2026, 12, 6))
      expect(Date.new(2026, 12, 9).end_of_week).to eq(Date.new(2026, 12, 12))
      expect(build(:shift, starts_at: Time.zone.local(2026, 12, 12, 23)).week_start).to eq(Date.new(2026, 12, 6))
      expect(build(:shift, starts_at: Time.zone.local(2026, 12, 13, 10)).week_start).to eq(Date.new(2026, 12, 13))
    end

    # Weekly contract settlement is the one place that keeps Monday weeks:
    # payments on existing contracts are dated by them.
    it "is asked for Monday by name only where weekly contract payments are settled" do
      files = Dir[Rails.root.join("app/**/*.{rb,erb}")].select { |path| File.read(path).match?(/:monday\b|SETTLEMENT_WEEK_STARTS_ON/) }

      expect(files.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }.sort)
        .to eq(%w[app/models/contract.rb app/services/contract_payment_sync_service.rb])
      expect(Contract::SETTLEMENT_WEEK_STARTS_ON).to eq(:monday)
      expect(Date.new(2026, 12, 9).beginning_of_week(Contract::SETTLEMENT_WEEK_STARTS_ON)).to eq(Date.new(2026, 12, 7))
    end
  end

  it "has no view that asks a calendar for another first day" do
    views = Dir[Rails.root.join("app/views/**/*.erb")]
    offenders = views.select { |path| File.read(path).match?(/week_starts_on|beginning_of_week\(:monday\)/) }

    expect(offenders.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }).to eq([])
  end
end
