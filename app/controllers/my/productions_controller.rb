# frozen_string_literal: true

module My
  class ProductionsController < ApplicationController
    def index
      @person = Current.user.person
      @people = Current.user.people.active.order(:created_at).to_a
      people_ids = @people.map(&:id)

      # Get groups from all profiles
      @groups = Group.active
                     .joins(:group_memberships)
                     .where(group_memberships: { person_id: people_ids })
                     .distinct
                     .order(:name)
                     .to_a
      group_ids = @groups.map(&:id)

      # Get all productions where user (via any profile or group) is in the talent pool
      production_ids = Set.new

      # Productions via person memberships
      person_production_ids = TalentPoolMembership
        .where(member_type: "Person", member_id: people_ids)
        .joins(:talent_pool)
        .pluck("talent_pools.production_id")
      production_ids.merge(person_production_ids)

      # Productions via group memberships
      if group_ids.any?
        group_production_ids = TalentPoolMembership
          .where(member_type: "Group", member_id: group_ids)
          .joins(:talent_pool)
          .pluck("talent_pools.production_id")
        production_ids.merge(group_production_ids)
      end

      @productions = Production.where(id: production_ids)
                               .includes(:organization)
                               .order(:name)
                               .to_a

      # Build lookup of which entities are in each production's talent pool
      @production_entities = {}
      @productions.each do |production|
        entities = []
        talent_pool = production.talent_pool

        @people.each do |person|
          if TalentPoolMembership.exists?(talent_pool: talent_pool, member: person)
            entities << { type: "person", entity: person }
          end
        end

        @groups.each do |group|
          if TalentPoolMembership.exists?(talent_pool: talent_pool, member: group)
            entities << { type: "group", entity: group }
          end
        end

        @production_entities[production.id] = entities
      end
    end

    def show
      @person = Current.user.person
      @people = Current.user.people.active.order(:created_at).to_a
      people_ids = @people.map(&:id)

      @groups = Group.active
                     .joins(:group_memberships)
                     .where(group_memberships: { person_id: people_ids })
                     .distinct
                     .order(:name)
                     .to_a
      group_ids = @groups.map(&:id)

      @production = Production.find(params[:id])
      @talent_pool = @production.talent_pool

      # Check if user is in this production's talent pool
      @person_memberships = TalentPoolMembership.where(talent_pool: @talent_pool, member_type: "Person", member_id: people_ids).includes(:member)
      @group_memberships = TalentPoolMembership.where(talent_pool: @talent_pool, member_type: "Group", member_id: group_ids).includes(:member)

      unless @person_memberships.any? || @group_memberships.any?
        redirect_to my_productions_path, alert: "You're not in the talent pool for this production."
        return
      end

      # Get upcoming shows for this production where user is assigned
      @upcoming_assignments = ShowPersonRoleAssignment
        .joins(:show)
        .where(shows: { production_id: @production.id })
        .where("shows.date_and_time >= ?", Time.current)
        .where(
          "(assignable_type = 'Person' AND assignable_id IN (?)) OR (assignable_type = 'Group' AND assignable_id IN (?))",
          people_ids, group_ids
        )
        .includes(:show, :role)
        .order("shows.date_and_time ASC")
        .to_a
    end

    def leave
      @production = Production.find(params[:id])
      @talent_pool = @production.talent_pool

      @people = Current.user.people.active.to_a
      people_ids = @people.map(&:id)

      @groups = Group.active
                     .joins(:group_memberships)
                     .where(group_memberships: { person_id: people_ids })
                     .distinct
                     .to_a
      group_ids = @groups.map(&:id)

      # Find which groups were actually in the talent pool before removal
      groups_in_pool = @groups.select do |group|
        TalentPoolMembership.exists?(talent_pool: @talent_pool, member: group)
      end

      # Remove all memberships for this user's profiles and groups
      TalentPoolMembership.where(talent_pool: @talent_pool, member_type: "Person", member_id: people_ids).destroy_all
      TalentPoolMembership.where(talent_pool: @talent_pool, member_type: "Group", member_id: group_ids).destroy_all

      # Notify producers with notifications enabled
      notify_producers_of_departure(groups_in_pool)

      redirect_to my_productions_path, notice: "You've been removed from #{@production.name}'s talent pool."
    end

    private

    def notify_producers_of_departure(groups_removed)
      # Get all users with production permissions who have notifications enabled
      @production.production_permissions.includes(:user).each do |permission|
        next unless permission.notifications_enabled?
        next unless permission.user.present?

        Manage::AuditionMailer.talent_left_production(
          permission.user,
          @production,
          Current.user.person,
          groups_removed
        ).deliver_later
      end
    end
  end
end
