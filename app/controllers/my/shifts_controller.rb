# frozen_string_literal: true

module My
  # Talent-side view of house staffing shifts the user has been assigned to
  # (the Staffing module's counterpart to "My Shows & Events"), plus the place
  # where staff mark the dates they're unavailable to work.
  class ShiftsController < ApplicationController
    SCOPES = %w[all_day day_shifts evening_shifts].freeze

    def index
      @people = Current.user.people.active.order(:created_at).to_a
      people_ids = @people.map(&:id)
      @people_by_id = @people.index_by(&:id)

      assignments = ShiftAssignment
        .where(person_id: people_ids)
        .joins(:shift)
        .where("shifts.ends_at >= ?", Time.current)
        .includes(:person, shift: [ :house_role, :organization, :source ])
        .order("shifts.starts_at ASC")
        .to_a

      @rows = assignments.map { |a| { assignment: a, shift: a.shift, person: a.person } }
      @rows_by_day = @rows.group_by { |r| r[:shift].starts_at.to_date }
      @has_any = @rows.any?

      # Unavailability for the calendar/summary (the client renders both). Cover
      # the current month through ~12 months out so month navigation has data.
      person = Current.user.person
      @unavailability_entries =
        if person
          person.staff_unavailabilities
                .where(date: Date.current.beginning_of_month..(Date.current + 12.months))
                .order(:date)
                .map { |u| { date: u.date.iso8601, scope: u.scope } }
        else
          []
        end
    end

    # Upsert/clear unavailability for one or more dates. Called by the client-side
    # calendar via fetch; responds JSON.
    def create_unavailability
      person = Current.user.person
      return render(json: { ok: false, error: "No profile" }, status: :unprocessable_entity) unless person

      scope = params[:scope].to_s
      dates = Array(params[:dates]).map { |d| safe_date(d) }.compact
      dates << safe_date(params[:date]) if params[:date].present?
      dates = dates.compact.uniq
      return render(json: { ok: false, error: "No dates" }, status: :unprocessable_entity) if dates.empty?

      if scope == "clear"
        person.staff_unavailabilities.where(date: dates).destroy_all
      elsif SCOPES.include?(scope)
        dates.each do |date|
          record = person.staff_unavailabilities.find_or_initialize_by(date: date)
          record.scope = scope
          record.save!
        end
      else
        return render(json: { ok: false, error: "Invalid scope" }, status: :unprocessable_entity)
      end

      render json: { ok: true }
    end

    private

    def safe_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
