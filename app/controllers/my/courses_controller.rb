# frozen_string_literal: true

module My
  class CoursesController < ApplicationController
    def index
      @person = Current.user.person
      people_ids = Current.user.people.active.pluck(:id)

      # Get all confirmed course registrations for the user's profiles
      @registrations = CourseRegistration
        .confirmed
        .where(person_id: people_ids)
        .includes(course_offering: { production: :organization })
        .order(registered_at: :desc)
        .to_a

      # Group into upcoming and past based on session dates
      @upcoming_courses = []
      @past_courses = []

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
          location: all_sessions.detect { |s| s.location.present? }&.location
        }

        if upcoming_sessions.any?
          @upcoming_courses << course_data
        else
          @past_courses << course_data
        end
      end

      # Sort upcoming by next session date
      @upcoming_courses.sort_by! { |c| c[:next_session].date_and_time }
      # Sort past by most recent session (reverse chronological)
      @past_courses.sort_by! { |c| c[:all_sessions].last&.date_and_time || Time.at(0) }.reverse!
    end

    def show
      @person = Current.user.person
      people_ids = Current.user.people.active.pluck(:id)

      @course_offering = CourseOffering.find(params[:id])
      @production = @course_offering.production

      # Find user's registration for this course
      @registration = CourseRegistration
        .where(person_id: people_ids, course_offering: @course_offering)
        .where.not(status: :cancelled)
        .order(registered_at: :desc)
        .first

      raise ActiveRecord::RecordNotFound unless @registration

      # Load sessions
      @all_sessions = @course_offering.sessions.includes(:location).to_a
      @upcoming_sessions = @all_sessions.select { |s| s.date_and_time >= Time.current }
      @completed_sessions = @all_sessions.count { |s| s.date_and_time < Time.current }
      @next_session = @upcoming_sessions.first
      @location = @all_sessions.detect { |s| s.location.present? }&.location

      # Instructor info
      @instructor = @course_offering.instructor_person
    end
  end
end
