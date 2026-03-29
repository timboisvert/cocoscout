# frozen_string_literal: true

module My
  class CoursesController < ApplicationController
    def index
      @person = Current.user.person
      people_ids = Current.user.people.active.pluck(:id)

      # Get all course registrations (confirmed, refunded, cancelled) for the user's profiles
      @registrations = CourseRegistration
        .where(person_id: people_ids)
        .includes(course_offering: { production: :organization })
        .order(registered_at: :desc)
        .to_a

      # Also find courses where the user is an instructor (no registration needed)
      instructor_offerings = CourseOffering
        .joins(:course_offering_instructors)
        .where(course_offering_instructors: { person_id: people_ids })
        .includes(production: :organization)
        .to_a

      # Deduplicate: exclude instructor offerings that already have a registration
      registered_offering_ids = @registrations.map { |r| r.course_offering_id }.to_set
      instructor_only_offerings = instructor_offerings.reject { |o| registered_offering_ids.include?(o.id) }

      # Group into upcoming and past based on session dates
      @upcoming_courses = []
      @past_courses = []

      # Process registered courses
      @registrations.each do |registration|
        offering = registration.course_offering
        upcoming_sessions = offering.upcoming_sessions.to_a
        all_sessions = offering.sessions.to_a

        course_data = {
          registration: registration,
          offering: offering,
          all_sessions: all_sessions,
          upcoming_sessions: upcoming_sessions,
          next_session: upcoming_sessions.first,
          total_sessions: all_sessions.size,
          completed_sessions: all_sessions.count { |s| s.date_and_time < Time.current },
          location: all_sessions.detect { |s| s.location.present? }&.location,
          role: registration.confirmed? ? :student : registration.status.to_sym,
          is_instructor: instructor_offerings.any? { |o| o.id == offering.id }
        }

        if upcoming_sessions.any?
          @upcoming_courses << course_data
        else
          @past_courses << course_data
        end
      end

      # Process instructor-only courses (no registration)
      instructor_only_offerings.each do |offering|
        upcoming_sessions = offering.upcoming_sessions.to_a
        all_sessions = offering.sessions.to_a

        course_data = {
          registration: nil,
          offering: offering,
          all_sessions: all_sessions,
          upcoming_sessions: upcoming_sessions,
          next_session: upcoming_sessions.first,
          total_sessions: all_sessions.size,
          completed_sessions: all_sessions.count { |s| s.date_and_time < Time.current },
          location: all_sessions.detect { |s| s.location.present? }&.location,
          role: :instructor,
          is_instructor: true
        }

        if upcoming_sessions.any?
          @upcoming_courses << course_data
        else
          @past_courses << course_data
        end
      end

      # Sort upcoming by next session date
      @upcoming_courses.sort_by! { |c| c[:next_session]&.date_and_time || Time.current }
      # Sort past by most recent session (reverse chronological)
      @past_courses.sort_by! { |c| c[:all_sessions].last&.date_and_time || Time.at(0) }.reverse!
    end

    def directory
      @offerings = CourseOffering
        .open
        .listed
        .includes(:production, :instructor_person, :organization)
        .order(created_at: :desc)

      # Pre-load session data for each offering
      @offerings_data = @offerings.map do |offering|
        all_sessions = offering.sessions.includes(:location).to_a
        upcoming_sessions = all_sessions.select { |s| s.date_and_time >= Time.current }
        next if upcoming_sessions.empty?

        first_session = all_sessions.first
        last_session = all_sessions.last
        location = all_sessions.detect { |s| s.location.present? }&.location

        # Detect recurring pattern
        days = all_sessions.map { |s| s.date_and_time.strftime("%A") }
        times = all_sessions.map { |s| s.date_and_time.strftime("%-I:%M %p") }
        schedule_pattern = if days.uniq.size == 1 && times.uniq.size == 1
                             "#{days.first.pluralize} at #{times.first}"
        elsif days.uniq.size == 1
                             days.first.pluralize
        end

        {
          offering: offering,
          all_sessions: all_sessions,
          first_session: first_session,
          last_session: last_session,
          total_sessions: all_sessions.size,
          upcoming_sessions_count: upcoming_sessions.size,
          next_session: upcoming_sessions.first,
          location: location,
          schedule_pattern: schedule_pattern,
          instructor: offering.instructor_people.first
        }
      end.compact
    end

    def show
      @person = Current.user.person
      people_ids = Current.user.people.active.pluck(:id)

      @course_offering = CourseOffering.find(params[:id])
      @production = @course_offering.production

      # Check if user is an instructor
      @is_instructor = @course_offering.course_offering_instructors.where(person_id: people_ids).exists?

      # Find user's registration for this course (any status except cancelled)
      @registration = CourseRegistration
        .where(person_id: people_ids, course_offering: @course_offering)
        .where.not(status: :cancelled)
        .order(registered_at: :desc)
        .first

      # Must have a registration OR be the instructor
      raise ActiveRecord::RecordNotFound unless @registration || @is_instructor

      # Load sessions
      @all_sessions = @course_offering.sessions.includes(:location).to_a
      @upcoming_sessions = @all_sessions.select { |s| s.date_and_time >= Time.current }
      @completed_sessions = @all_sessions.count { |s| s.date_and_time < Time.current }
      @next_session = @upcoming_sessions.first
      @location = @all_sessions.detect { |s| s.location.present? }&.location

      # Instructor info
      @instructors = @course_offering.instructor_people.to_a
      @instructor = @instructors.first  # backward compat for contact card
      @lead_coi = @course_offering.course_offering_instructors.first

      # If this user IS the instructor, load registered students for the panel
      if @is_instructor
        @registered_students = @course_offering.course_registrations
          .where(status: :confirmed)
          .includes(:person)
          .order(:registered_at)
          .map(&:person)
          .compact
      end
    end
  end
end
