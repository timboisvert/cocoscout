# frozen_string_literal: true

module My
  # Where staff say when they can work: one month calendar whose header row is
  # their usual week. A weekday changes every week; a date changes just that
  # date (or a run of them). Every answer is Anytime / Not at all / Only
  # certain hours; the writer turns that into availability entries, so nobody
  # here ever picks between "marking when I'm available" and "marking when I'm
  # not".
  #
  # Each change posts and comes straight back to this page and month (morphed,
  # scroll kept), so what's on screen is always what was saved.
  class WorkAvailabilityController < ApplicationController
    before_action :require_person

    # Months the calendar can page through, starting with this one.
    CALENDAR_MONTHS = 12

    def show
      @picture = WorkAvailabilityPicture.new(@person)
      @day_parts = @person.staffing_day_parts
      @return_path = return_path
      @from_onboarding = onboarding_org_id.present?

      calendar_months
      from = @month
      to = @calendar_last_month.end_of_month
      resolver = StaffAvailabilityResolver.new([ @person.id ], from: from, to: to)
      @days = (from..to).index_with { |date| resolver.day(@person.id, date) }
    end

    # One editor, two scopes: "week" is every such weekday from now on,
    # "dates" is just the date (or run of dates) picked.
    def save
      if params[:scope] == "week"
        writer.set_weekdays!(params[:days], state: params[:state], windows: params[:windows])
        back notice: "Saved your usual #{day_names(params[:days])}."
      else
        starts_on = params[:starts_on]
        ends_on = params[:ends_on].presence || starts_on
        writer.save_exception!(
          starts_on: starts_on, ends_on: ends_on,
          state: params[:state], windows: params[:windows], note: params[:note],
          replacing: params[:replacing_starts_on].present? ? [ params[:replacing_starts_on], params[:replacing_ends_on] ] : nil
        )
        back notice: "Saved #{dates_label(starts_on, ends_on)}."
      end
    rescue StaffAvailabilityWriter::Invalid => e
      back alert: e.message
    end

    def destroy_dates
      writer.remove_exception!(starts_on: params[:starts_on], ends_on: params[:ends_on])
      back notice: "Back to your usual week for #{dates_label(params[:starts_on], params[:ends_on].presence || params[:starts_on])}."
    rescue StaffAvailabilityWriter::Invalid => e
      back alert: e.message
    end

    # "My availability is up to date" — vouches for the coming weeks without changing
    # anything. From onboarding, it's also the way back.
    def confirm
      writer.confirm!
      if params[:stay].present?
        # The box on this page: stay here and show the green check.
        back notice: "Thanks — your availability is up to date."
      elsif onboarding_org_id
        redirect_to my_onboarding_path(onboarding_org_id, availability_done: 1)
      else
        redirect_to my_shifts_path, notice: "Thanks — your availability is confirmed through " \
                                            "#{@person.reload.availability_confirmed_through.strftime('%B %-d')}."
      end
    end

    private

    def require_person
      @person = Current.user&.person
      redirect_to my_shifts_path, alert: "Set up your profile first." unless @person
    end

    def writer
      StaffAvailabilityWriter.new(@person, source: :self_reported)
    end

    # Onboarding sends people here and expects them back; only an org this
    # person actually staffs counts, so the parameter can't point anywhere else.
    def onboarding_org_id
      id = params[:onboarding].presence
      return nil unless id

      @onboarding_org_id ||= OrganizationStaffMember.where(person_id: @person.id, organization_id: id).pick(:organization_id)
    end

    def return_path
      onboarding_org_id ? my_onboarding_path(onboarding_org_id) : my_shifts_path
    end

    def back(**flash)
      month_param = params[:month].presence && month.iso8601
      redirect_to my_work_availability_path(onboarding: onboarding_org_id, month: month_param, anchor: "calendar"), **flash
    end

    # The months the calendar shows and pages to. This month starts at the
    # current week (past days can't be changed); in its last week it folds
    # next month in, so the grid never runs out at the weekend. Mirrors the
    # My Dashboard calendar.
    def calendar_months
      @month = month
      @first_month = Date.current.beginning_of_month
      @final_month = @first_month >> (CALENDAR_MONTHS - 1)
      tail = (@first_month.end_of_month - Date.current).to_i < 7
      @calendar_combined = tail && @month == @first_month

      @prev_month = @month << 1
      @next_month = @month >> 1
      if @calendar_combined
        @next_month = @first_month >> 2
      elsif tail && @month == @first_month >> 1
        @month = @first_month                    # the folded month lives in the combined view
        @calendar_combined = true
        @next_month = @first_month >> 2
      elsif tail && @month == @first_month >> 2
        @prev_month = @first_month
      end
      @calendar_last_month = @calendar_combined ? @first_month >> 1 : @month

      short = ->(m) { m == @first_month && tail ? "#{m.strftime('%b')} / #{(m >> 1).strftime('%b')}" : m.strftime("%b") }
      @prev_label = short.call(@prev_month)
      @next_label = short.call(@next_month)
      @calendar_heading =
        if !@calendar_combined then @month.strftime("%B %Y")
        elsif @month.year == @calendar_last_month.year then "#{@month.strftime('%B')} / #{@calendar_last_month.strftime('%B %Y')}"
        else "#{@month.strftime('%B %Y')} / #{@calendar_last_month.strftime('%B %Y')}"
        end
    end

    # The month asked for: ?month=2026-11-01, kept within the months the
    # calendar pages through.
    def month
      first = Date.current.beginning_of_month
      asked = Date.iso8601(params[:month].to_s).beginning_of_month rescue first
      asked.clamp(first, first >> (CALENDAR_MONTHS - 1))
    end

    # "Sat, Oct 10" / "Sat, Oct 10 – 12", as the Coming up list says it.
    def dates_label(starts_on, ends_on)
      from = Date.iso8601(starts_on.to_s)
      to = Date.iso8601(ends_on.to_s) rescue from
      WorkAvailabilityPicture::DatedAnswer.new(starts_on: from, ends_on: [ to, from ].max).dates_label
    rescue Date::Error
      "those dates"
    end

    def day_names(days)
      names = Array(days).map(&:to_i).select { |d| d.between?(0, 6) }.uniq
                         .sort_by { |d| WorkAvailabilityPicture::WEEK_ORDER.index(d) }
                         .map { |d| Date::DAYNAMES[d] }
      names.to_sentence
    end
  end
end
