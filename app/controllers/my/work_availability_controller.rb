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

    # The months the calendar shows and pages to (see ForwardMonthCalendar).
    def calendar_months
      cal = ForwardMonthCalendar.new(params[:month], months: CALENDAR_MONTHS)
      @month = cal.month
      @first_month = cal.first_month
      @final_month = cal.final_month
      @prev_month = cal.prev_month
      @next_month = cal.next_month
      @prev_label = cal.prev_label
      @next_label = cal.next_label
      @calendar_last_month = cal.last_month
      @calendar_heading = cal.heading
    end

    # The month asked for: ?month=2026-11-01, kept within the months the
    # calendar pages through.
    def month
      first = Date.current.beginning_of_month
      ForwardMonthCalendar.clamp(params[:month], first: first, final: first >> (CALENDAR_MONTHS - 1))
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
