# frozen_string_literal: true

module Manage
  class OrgShowsController < Manage::ManageController
    def index
      # Store the shows filter
      @filter = params[:filter] || session[:shows_filter] || "upcoming"
      session[:shows_filter] = @filter

      # Handle event type filter (show, rehearsal, meeting, class, workshop) - checkboxes
      @event_type_filter = params[:event_type] ? params[:event_type].split(",") : EventTypes.all

      # Get all productions for the organization
      @productions = Current.organization.productions.order(:name)

      # Get shows across all productions, eager load location, event_linkage, and production
      @shows = Show.where(production: @productions)
                   .includes(:location, :production, event_linkage: :shows)

      # Apply event type filter
      @shows = @shows.where(event_type: @event_type_filter)

      case @filter
      when "past"
        @shows = @shows.where("shows.date_and_time <= ?", Time.current).order(Arel.sql("shows.date_and_time DESC"))
      else
        @filter = "upcoming"
        @shows = @shows.where("shows.date_and_time > ?", Time.current).order(Arel.sql("shows.date_and_time ASC"))
      end

      # Load into memory
      @shows = @shows.to_a

      # Load cast and vacancy data for each show
      show_ids = @shows.map(&:id)

      # Get all assignments for these shows
      assignments = ShowPersonRoleAssignment
        .where(show_id: show_ids)
        .includes(:role, assignable: { profile_headshots: { image_attachment: :blob } })
        .to_a

      @assignments_by_show = assignments.group_by(&:show_id)

      # Get all roles for these shows
      @roles_by_show = {}
      @shows.each do |show|
        @roles_by_show[show.id] = show.available_roles.to_a
      end

      # Get open vacancies for these shows
      all_vacancies = RoleVacancy
        .where(status: %w[open finding_replacement not_filling])
        .joins("LEFT JOIN role_vacancy_shows ON role_vacancy_shows.role_vacancy_id = role_vacancies.id")
        .where("role_vacancies.show_id IN (?) OR role_vacancy_shows.show_id IN (?)", show_ids, show_ids)
        .distinct
        .includes(:role, :vacated_by, :affected_shows)
        .to_a

      # Build cant_make_it_by_assignment for each show
      @cant_make_it_by_show = {}
      all_vacancies.each do |vacancy|
        next unless vacancy.vacated_by.present?

        affected_show_ids = vacancy.affected_shows.any? ? vacancy.affected_shows.pluck(:id) : [ vacancy.show_id ]

        affected_show_ids.each do |affected_show_id|
          next unless show_ids.include?(affected_show_id)
          @cant_make_it_by_show[affected_show_id] ||= {}
          key = [ vacancy.vacated_by_type, vacancy.vacated_by_id ]
          @cant_make_it_by_show[affected_show_id][key] = vacancy
        end
      end

      # Load sign-up registrations for shows that have linked sign-up forms
      sign_up_registrations = SignUpRegistration
        .joins(sign_up_slot: :sign_up_form_instance)
        .where(sign_up_form_instances: { show_id: show_ids })
        .where(status: %w[confirmed waitlisted])
        .includes(:person, person: { profile_headshots: { image_attachment: :blob } }, sign_up_slot: { sign_up_form_instance: :sign_up_form })
        .to_a

      @sign_up_registrations_by_show = sign_up_registrations.group_by { |r| r.sign_up_slot.sign_up_form_instance.show_id }
    end

    def calendar
      # Store the shows filter
      @filter = params[:filter] || session[:shows_filter] || "upcoming"
      session[:shows_filter] = @filter

      # Get all productions for the organization
      @productions = Current.organization.productions.order(:name)

      # Get shows across all productions, eager load location and production
      @shows = Show.where(production: @productions)
                   .includes(:location, :production)

      case @filter
      when "past"
        @shows = @shows.where("shows.date_and_time <= ?", Time.current).order(:date_and_time)
      else
        @filter = "upcoming"
        @shows = @shows.where("shows.date_and_time > ?", Time.current).order(:date_and_time)
      end

      # Load into memory and group shows by month for calendar display
      @shows_by_month = @shows.to_a.group_by { |show| show.date_and_time.beginning_of_month }
    end
  end
end
