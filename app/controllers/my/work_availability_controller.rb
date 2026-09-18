# frozen_string_literal: true

module My
  # Where staff say when they can work: their usual week, and the exceptions
  # to it. Every answer is Anytime / Not at all / Only certain hours; the
  # writer turns that into availability entries, so nobody here ever picks
  # between "marking when I'm available" and "marking when I'm not".
  #
  # Each change posts and comes straight back to this page (morphed, scroll
  # kept), so what's on screen is always what was saved.
  class WorkAvailabilityController < ApplicationController
    before_action :require_person

    # Months the calendar can step through, starting with this one.
    CALENDAR_MONTHS = 4

    def show
      @picture = WorkAvailabilityPicture.new(@person)
      @day_parts = @person.staffing_day_parts
      @return_path = return_path
      @from_onboarding = onboarding_org_id.present?

      first = Date.current.beginning_of_month
      @months = (0...CALENDAR_MONTHS).map { |i| first >> i }
      last = @months.last.end_of_month
      resolver = StaffAvailabilityResolver.new([ @person.id ], from: first, to: last)
      @days = (first..last).index_with { |date| resolver.day(@person.id, date) }
    end

    def update_week
      writer.set_weekdays!(params[:days], state: params[:state], windows: params[:windows])
      back notice: "Saved your usual #{day_names(params[:days])}."
    rescue StaffAvailabilityWriter::Invalid => e
      back alert: e.message
    end

    def save_exception
      writer.save_exception!(
        starts_on: params[:starts_on], ends_on: params[:ends_on].presence || params[:starts_on],
        state: params[:state], windows: params[:windows], note: params[:note],
        replacing: params[:replacing_starts_on].present? ? [ params[:replacing_starts_on], params[:replacing_ends_on] ] : nil
      )
      back notice: "Saved."
    rescue StaffAvailabilityWriter::Invalid => e
      back alert: e.message
    end

    def destroy_exception
      writer.remove_exception!(starts_on: params[:starts_on], ends_on: params[:ends_on])
      back notice: "Removed."
    rescue StaffAvailabilityWriter::Invalid => e
      back alert: e.message
    end

    # "This is all right" — vouches for the coming weeks without changing
    # anything. From onboarding, it's also the way back.
    def confirm
      writer.confirm!
      if onboarding_org_id
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
      redirect_to my_work_availability_path(onboarding: onboarding_org_id), **flash
    end

    def day_names(days)
      names = Array(days).map(&:to_i).select { |d| d.between?(0, 6) }.uniq
                         .sort_by { |d| WorkAvailabilityPicture::WEEK_ORDER.index(d) }
                         .map { |d| Date::DAYNAMES[d] }
      names.to_sentence
    end
  end
end
