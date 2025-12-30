# frozen_string_literal: true

module Manage
  class VacanciesController < Manage::ManageController
    before_action :set_production
    before_action :check_production_access
    before_action :set_vacancy, only: %i[show send_invitations cancel fill]

    def show
      @invitations = @vacancy.invitations.includes(:person).order(created_at: :desc)

      # Get eligible members (people and groups) to invite
      @talent_pool = @production.talent_pool

      # Get all potential members (people and groups) based on role restrictions
      if @vacancy.restricted?
        # For restricted roles, use eligible_members which includes both people and groups
        all_members = @vacancy.eligible_members
      else
        # For unrestricted roles, get all talent pool members (people and groups)
        people = @talent_pool.people.includes(profile_headshots: { image_attachment: :blob })
        groups = @talent_pool.groups.includes(profile_headshots: { image_attachment: :blob })
        all_members = (people.to_a + groups.to_a)
      end

      # Track the member who vacated the role (to show grayed out)
      @vacated_by_id = @vacancy.vacated_by_id
      @vacated_by_type = @vacancy.vacated_by_type

      # Track members who have already been invited (to show grayed out)
      # Note: Currently invitations only support people, not groups
      @already_invited_person_ids = @vacancy.invitations.pluck(:person_id)

      # Track members who already have a role in this show (to show grayed out)
      @already_cast_person_ids = @vacancy.show.show_person_role_assignments
                                              .where(assignable_type: "Person")
                                              .pluck(:assignable_id)
      @already_cast_group_ids = @vacancy.show.show_person_role_assignments
                                             .where(assignable_type: "Group")
                                             .pluck(:assignable_id)

      # Sort so unavailable members appear at the bottom
      @all_potential_members = all_members.sort_by do |member|
        is_vacated = member.class.name == @vacated_by_type && member.id == @vacated_by_id
        is_already_cast = member.is_a?(Person) ? @already_cast_person_ids.include?(member.id) : @already_cast_group_ids.include?(member.id)
        is_already_invited = member.is_a?(Person) && @already_invited_person_ids.include?(member.id)
        is_unavailable = is_vacated || is_already_cast || is_already_invited
        [ is_unavailable ? 1 : 0, member.name.downcase ]
      end

      # Members who can actually be invited (excludes already cast, already invited, and vacated)
      @eligible_members = @all_potential_members.reject do |member|
        is_vacated = member.class.name == @vacated_by_type && member.id == @vacated_by_id
        is_already_cast = member.is_a?(Person) ? @already_cast_person_ids.include?(member.id) : @already_cast_group_ids.include?(member.id)
        is_already_invited = member.is_a?(Person) && @already_invited_person_ids.include?(member.id)
        is_vacated || is_already_cast || is_already_invited
      end

      # For backward compatibility (used in unrestricted roles radio option count)
      @eligible_people = @eligible_members.select { |m| m.is_a?(Person) }

      # Get other cast members for display (excluding the person who vacated)
      @other_cast_assignments = @vacancy.show.show_person_role_assignments
                                            .includes(:role)
                                            .where.not(
                                              assignable_type: @vacated_by_type,
                                              assignable_id: @vacated_by_id
                                            )
                                            .order("roles.position ASC")
      @all_potential_people = @all_potential_members.select { |m| m.is_a?(Person) }
    end

    def send_invitations
      invite_mode = params[:invite_mode]
      email_subject = params[:email_subject]
      email_body = params[:email_body]

      # IDs to exclude: already invited, already cast in this show, or the person who vacated
      already_invited_ids = @vacancy.invitations.pluck(:person_id)
      already_cast_ids = @vacancy.show.show_person_role_assignments
                                      .where(assignable_type: "Person")
                                      .pluck(:assignable_id)
      vacated_by_id = @vacancy.vacated_by_id
      excluded_ids = (already_invited_ids + already_cast_ids + [ vacated_by_id ].compact).uniq

      # Determine which people to invite based on mode
      person_ids = case invite_mode
      when "all"
        # All talent pool members (not restricted role)
        @production.talent_pool.people
              .where.not(id: excluded_ids)
              .pluck(:id)
      else
        # "specific" mode or restricted role - use member_ids from form
        # Parse member_ids which are in format "Person_123" or "Group_456"
        member_ids = params[:member_ids] || []
        person_ids_from_form = []
        group_ids = []

        member_ids.each do |member_id|
          type, id = member_id.split("_", 2)
          if type == "Person"
            person_ids_from_form << id.to_i
          elsif type == "Group"
            group_ids << id.to_i
          end
        end

        # Expand groups into their members (only those with notifications enabled)
        if group_ids.any?
          group_member_ids = GroupMembership.where(group_id: group_ids)
                                            .includes(:person)
                                            .select(&:notifications_enabled?)
                                            .map(&:person_id)
          person_ids_from_form.concat(group_member_ids)
        end

        # Filter out excluded IDs and deduplicate
        person_ids_from_form.uniq - excluded_ids
      end

      if person_ids.empty?
        redirect_to manage_production_vacancy_path(@production, @vacancy),
                    alert: "Please select at least one cast member to invite."
        return
      end

      invited_count = 0

      Person.where(id: person_ids).find_each do |person|
        next unless @vacancy.can_invite?(person)

        invitation = @vacancy.invitations.create!(
          person: person,
          email_subject: email_subject,
          email_body: email_body
        )

        # Send the invitation email
        VacancyInvitationMailer.invitation_email(invitation).deliver_later
        invited_count += 1
      end

      # Mark the vacancy as finding replacement if we sent any invitations
      @vacancy.mark_finding_replacement! if invited_count > 0

      redirect_to manage_production_vacancy_path(@production, @vacancy),
                  notice: "Invited #{invited_count} #{'person'.pluralize(invited_count)}."
    end

    def cancel
      @vacancy.mark_not_filling!(by: Current.user)
      redirect_to manage_production_path(@production),
                  notice: "Vacancy closed without filling."
    end

    def fill
      person_id = params[:person_id]
      person = Person.find(person_id)

      # The fill! method handles removing old assignment, creating new assignment, and updating vacancy status
      @vacancy.fill!(person, by: Current.person)

      redirect_to manage_production_path(@production),
                  notice: "Vacancy filled by #{person.name}."
    end

    private

    def set_production
      @production = Current.organization.productions.find(params[:production_id])
    end

    def set_vacancy
      @vacancy = RoleVacancy.joins(:show)
                            .includes(:role)
                            .where(shows: { production_id: @production.id })
                            .find(params[:id])
    end
  end
end
