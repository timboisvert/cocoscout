# frozen_string_literal: true

module Manage
  class OrgCastingController < Manage::ManageController
    before_action :require_current_organization

    def index
      # Store the shows filter (default to upcoming)
      @filter = params[:filter] || session[:casting_filter] || "upcoming"
      session[:casting_filter] = @filter

      # Hide canceled events toggle (default: true - hide canceled)
      @hide_canceled = if params[:hide_canceled].present?
        params[:hide_canceled] == "true"
      else
        session[:casting_hide_canceled].nil? ? true : session[:casting_hide_canceled]
      end
      session[:casting_hide_canceled] = @hide_canceled

      # Get all in-house productions for the organization (exclude third-party)
      @productions = Current.organization.productions.type_in_house.order(:name)

      # Get shows with casting enabled across all in-house productions
      base_shows = Show.where(production: @productions, casting_enabled: true)
                       .includes(:production, :location, :custom_roles, show_person_role_assignments: :role)

      # Apply canceled filter
      base_shows = base_shows.where(canceled: false) if @hide_canceled

      case @filter
      when "past"
        @shows = base_shows.where("date_and_time < ?", Time.current).order(date_and_time: :desc)
      else
        @filter = "upcoming"
        @shows = base_shows.where("date_and_time >= ?", Time.current).order(:date_and_time)
      end

      # Load into memory
      @shows = @shows.to_a

      # Preload roles per production
      @roles_by_production = {}
      @productions.each do |production|
        @roles_by_production[production.id] = production.roles.order(:position).to_a
      end

      # Precompute max assignment updated_at per show
      show_ids = @shows.map(&:id)
      @assignments_max_updated_at_by_show = ShowPersonRoleAssignment
        .where(show_id: show_ids)
        .group(:show_id)
        .maximum(:updated_at)

      # Precompute max role updated_at per show for custom roles
      @roles_max_updated_at_by_show = {}
      @shows.each do |show|
        if show.use_custom_roles?
          @roles_max_updated_at_by_show[show.id] = show.custom_roles.map(&:updated_at).compact.max
        else
          roles = @roles_by_production[show.production_id] || []
          @roles_max_updated_at_by_show[show.id] = roles.map(&:updated_at).compact.max
        end
      end

      # Preload assignables (people and groups) with their headshots
      all_assignments = @shows.flat_map(&:show_person_role_assignments)

      person_ids = all_assignments.select { |a| a.assignable_type == "Person" }.map(&:assignable_id).uniq
      group_ids = all_assignments.select { |a| a.assignable_type == "Group" }.map(&:assignable_id).uniq

      @people_by_id = Person
                      .where(id: person_ids)
                      .includes(profile_headshots: { image_attachment: :blob })
                      .index_by(&:id)

      @groups_by_id = Group
                      .where(id: group_ids)
                      .includes(profile_headshots: { image_attachment: :blob })
                      .index_by(&:id)

      # Load cancelled vacancies for all shows
      @cancelled_vacancies_by_show = {}
      @shows.each do |show|
        @cancelled_vacancies_by_show[show.id] = show.cancelled_vacancies_by_assignment
      end

      # Load open vacancies for non-linked shows
      @open_vacancies_by_show = {}
      @shows.each do |show|
        next if show.linked?
        open_vacancies = show.role_vacancies.open.includes(:role, :vacated_by).to_a
        @open_vacancies_by_show[show.id] = open_vacancies.group_by(&:role_id)
      end

      # Load sign-up registrations for shows with linked sign-up forms
      sign_up_registrations = SignUpRegistration
        .joins(sign_up_slot: :sign_up_form_instance)
        .where(sign_up_form_instances: { show_id: show_ids })
        .where(status: %w[confirmed waitlisted])
        .includes(:person, person: { profile_headshots: { image_attachment: :blob } }, sign_up_slot: { sign_up_form_instance: :sign_up_form })
        .to_a

      @sign_up_registrations_by_show = sign_up_registrations.group_by { |r| r.sign_up_slot.sign_up_form_instance.show_id }
    end
  end
end
