# frozen_string_literal: true

# Which months a forward-looking month calendar shows and pages to: this month
# through `months` ahead, asked for with ?month=2026-11-01. This month starts
# at the current week (past days can't be changed), and in its last week it
# folds next month in so the grid never runs out at the weekend — mirroring
# the My Dashboard calendar. Shared by the staff Work Availability page and
# the managers' Staffing → Availability page.
#
#   cal = ForwardMonthCalendar.new(params[:month], months: 12)
#   render "shared/month_calendar", **cal.month_calendar_locals, month_link: ...
class ForwardMonthCalendar
  attr_reader :month, :first_month, :final_month, :prev_month, :next_month, :last_month

  def initialize(asked, months:, today: Date.current)
    @today = today
    @first_month = today.beginning_of_month
    @final_month = @first_month >> (months - 1)
    @month = self.class.clamp(asked, first: @first_month, final: @final_month)

    tail = (@first_month.end_of_month - today).to_i < 7
    @combined = tail && @month == @first_month
    @prev_month = @month << 1
    @next_month = @month >> 1
    if @combined
      @next_month = @first_month >> 2
    elsif tail && @month == @first_month >> 1
      @month = @first_month # the folded month lives in the combined view
      @combined = true
      @next_month = @first_month >> 2
    elsif tail && @month == @first_month >> 2
      @prev_month = @first_month
    end
    @last_month = @combined ? @first_month >> 1 : @month
    @tail = tail
  end

  # "2026-11-01" (or anything) → a month within [first, final].
  def self.clamp(asked, first:, final:)
    date = Date.iso8601(asked.to_s).beginning_of_month rescue first
    date.clamp(first, final)
  end

  def combined? = @combined

  # The dates the grid covers.
  def range
    @month..@last_month.end_of_month
  end

  def heading
    if !@combined then @month.strftime("%B %Y")
    elsif @month.year == @last_month.year then "#{@month.strftime('%B')} / #{@last_month.strftime('%B %Y')}"
    else "#{@month.strftime('%B %Y')} / #{@last_month.strftime('%B %Y')}"
    end
  end

  def prev_label = short(@prev_month)
  def next_label = short(@next_month)

  def can_go_prev? = @month > @first_month
  def can_go_next? = @next_month <= @final_month

  # Everything shared/month_calendar needs except month_link / items.
  def month_calendar_locals
    {
      current_month: @month, last_month: @last_month, heading: heading,
      prev_month: @prev_month, next_month: @next_month, prev_label: prev_label, next_label: next_label,
      can_go_prev: can_go_prev?, can_go_next: can_go_next?, start_from_current_week: true
    }
  end

  private

  def short(m)
    m == @first_month && @tail ? "#{m.strftime('%b')} / #{(m >> 1).strftime('%b')}" : m.strftime("%b")
  end
end
