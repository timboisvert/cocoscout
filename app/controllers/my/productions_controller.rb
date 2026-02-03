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
      # This includes both direct talent pools AND shared talent pools
      production_ids = Set.new

      # Productions via person's direct talent pool memberships
      person_production_ids = TalentPoolMembership
        .where(member_type: "Person", member_id: people_ids)
        .joins(:talent_pool)
        .pluck("talent_pools.production_id")
      production_ids.merge(person_production_ids)

      # Productions via shared talent pools (person is in a talent pool that's shared with other productions)
      if people_ids.any?
        shared_person_production_ids = Production
          .joins(talent_pool_shares: { talent_pool: :talent_pool_memberships })
          .where(talent_pool_memberships: { member_type: "Person", member_id: people_ids })
          .pluck(:id)
        production_ids.merge(shared_person_production_ids)
      end

      # Productions via group's direct talent pool memberships
      if group_ids.any?
        group_production_ids = TalentPoolMembership
          .where(member_type: "Group", member_id: group_ids)
          .joins(:talent_pool)
          .pluck("talent_pools.production_id")
        production_ids.merge(group_production_ids)

        # Productions via shared talent pools (group is in a talent pool that's shared with other productions)
        shared_group_production_ids = Production
          .joins(talent_pool_shares: { talent_pool: :talent_pool_memberships })
          .where(talent_pool_memberships: { member_type: "Group", member_id: group_ids })
          .pluck(:id)
        production_ids.merge(shared_group_production_ids)
      end

      @productions = Production.where(id: production_ids)
                               .includes(:organization)
                               .order(:name)
                               .to_a

      # Build lookup of which entities are in each production's effective talent pool
      @production_entities = {}
      @productions.each do |production|
        entities = []
        talent_pool = production.effective_talent_pool

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
      @talent_pool = @production.effective_talent_pool

      # Check if user is in this production's effective talent pool
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

      # Build calendar data for all shows in this production
      # Load shows from 6 months ago to 12 months in the future
      start_date = 6.months.ago.beginning_of_month
      end_date = 12.months.from_now.end_of_month

      @calendar_shows = @production.shows
        .where("date_and_time >= ? AND date_and_time <= ?", start_date, end_date)
        .where(canceled: false)
        .includes(:location, :event_linkage)
        .order(:date_and_time)
        .to_a

      # Build assignment lookup for highlighting user's assignments
      all_assignments = ShowPersonRoleAssignment
        .where(show_id: @calendar_shows.map(&:id))
        .where(
          "(assignable_type = 'Person' AND assignable_id IN (?)) OR (assignable_type = 'Group' AND assignable_id IN (?))",
          people_ids, group_ids
        )
        .includes(:role)
        .to_a

      @calendar_assignments_by_show = all_assignments.group_by(&:show_id)

      # Group shows by month for the calendar view
      @calendar_shows_by_month = @calendar_shows.group_by { |show| show.date_and_time.beginning_of_month }

      # Load messages for this production (where production is a regardable)
      production_message_ids = MessageRegard.where(regardable: @production).pluck(:message_id)
      @production_messages = Message.where(id: production_message_ids)
                                    .where(parent_message_id: nil)  # Only root messages
                                    .includes(:sender, :recipient, :message_regards, :child_messages, images_attachments: :blob)
                                    .order(created_at: :desc)
                                    .limit(20)

      # For the send message modal
      @email_draft = EmailDraft.new
    end

    def leave
      @production = Production.find(params[:id])
      @talent_pool = @production.effective_talent_pool

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

    def email
      @person = Current.user.person
      return redirect_to my_dashboard_path, alert: "No profile found." unless @person

      @production = Production.find(params[:production_id])

      # Verify user is in talent pool
      unless @person.in_talent_pool_for?(@production)
        redirect_to my_productions_path, alert: "You're not in the talent pool for this production."
        return
      end

      @email_log = EmailLog.for_recipient_entity(@person)
                           .where(production_id: @production.id)
                           .find_by(id: params[:id])

      unless @email_log
        redirect_to my_production_path(@production, tab: 2), alert: "Email not found."
      end
    end

    private

    def notify_producers_of_departure(groups_removed)
      # Get all users with production permissions who have notifications enabled
      @production.production_permissions.includes(:user).each do |permission|
        next unless permission.notifications_enabled?
        next unless permission.user.present?

        # Build the message
        groups_text = groups_removed.any? ? groups_removed.join(", ") : "the production"
        talent_pool_url = Rails.application.routes.url_helpers.manage_auditions_url(
          production_id: @production.id,
          host: ENV.fetch("HOST", "localhost:3000")
        )
        rendered = ContentTemplateService.render("talent_left_production", {
          recipient_name: permission.user.person&.first_name || "there",
          talent_name: Current.user.person&.full_name || "A talent",
          production_name: @production.name,
          groups_removed: groups_text,
          talent_pool_url: talent_pool_url
        })

        MessageService.send_direct(
          sender: nil,
          recipient_person: permission.user.person,
          subject: rendered[:subject],
          body: rendered[:body],
          production: @production,
          organization: @production.organization
        )
      end
    end
  end
end
