# frozen_string_literal: true

module My
  class OpenRequestsController < ApplicationController
    def index
      @person = Current.user.person
      @people = Current.user.people.active.order(:created_at).to_a
      people_ids = @people.map(&:id)
      people_by_id = @people.index_by(&:id)

      # Get groups from all profiles
      @groups = Group.active
                     .joins(:group_memberships)
                     .where(group_memberships: { person_id: people_ids })
                     .distinct
                     .order(:name)
                     .to_a
      groups_by_id = @groups.index_by(&:id)

      @filter = params[:filter] || session[:open_requests_filter] || "awaiting"
      session[:open_requests_filter] = @filter

      # Handle entity filter - now uses person_ID format
      default_entities = @people.map { |p| "person_#{p.id}" } + @groups.map { |g| "group_#{g.id}" }
      @entity_filter = params[:entity] ? params[:entity].split(",") : default_entities

      # Build selected entity IDs for batch queries
      selected_person_ids = @people.select { |p| @entity_filter.include?("person_#{p.id}") }.map(&:id)
      selected_group_ids = @groups.select { |g| @entity_filter.include?("group_#{g.id}") }.map(&:id)

      # ========================================
      # Section 1: Shows - Availability & Sign-ups
      # ========================================
      load_shows_data(selected_person_ids, selected_group_ids, people_by_id, groups_by_id)

      # ========================================
      # Section 1b: Non-event Sign-ups (shared_pool forms)
      # ========================================
      load_non_event_signups(selected_person_ids, people_by_id)

      # ========================================
      # Section 2: Questionnaires
      # ========================================
      load_questionnaires_data(selected_person_ids, people_by_id)

      # Check if user is part of any productions (for showing content even when filtered results are empty)
      productions_exist = Production.joins(talent_pools: :people).where(people: { id: people_ids }).exists?
      groups_in_productions = @groups.any? { |g| g.talent_pool_memberships.joins(talent_pool: :production).exists? }
      @has_any_productions = productions_exist || groups_in_productions

      # Calculate badge counts for navigation
      @total_open_count = @availability_items.count { |i| i[:availability].nil? } +
                          @signup_items.count { |i| i[:registration].nil? } +
                          @questionnaire_items.size
    end

    def update_availability
      show = Show.find(params[:show_id])
      entity_type = params[:entity_type] # "Person" or "Group"
      entity_id = params[:entity_id].to_i
      status = params[:status]

      # Verify user has access to this entity
      entity = if entity_type == "Person"
                 Current.user.people.find_by(id: entity_id)
      else
                 Group.joins(:group_memberships)
                      .where(group_memberships: { person_id: Current.user.people.pluck(:id) })
                      .find_by(id: entity_id)
      end

      unless entity
        return render json: { error: "Not authorized" }, status: :forbidden
      end

      availability = ShowAvailability.find_or_initialize_by(
        show: show,
        available_entity_type: entity_type,
        available_entity_id: entity_id
      )
      availability.status = status
      availability.save!

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "request-item-#{show.id}-#{entity_type.downcase}_#{entity_id}",
            partial: "my/open_requests/request_item",
            locals: { item: build_availability_item(show, entity, availability) }
          )
        end
        format.json { render json: { success: true } }
      end
    end

    def sign_up
      show = Show.find(params[:show_id])
      person = Current.user.people.find_by(id: params[:person_id])

      unless person
        return render json: { error: "Not authorized" }, status: :forbidden
      end

      # Find the sign-up form instance for this show (open or scheduled for pre-registration)
      instance = SignUpFormInstance.joins(:sign_up_form)
                                   .where(show_id: show.id)
                                   .where(status: %w[open scheduled])
                                   .where(sign_up_forms: { archived_at: nil })
                                   .first

      unless instance
        return redirect_to my_requests_path, alert: "Sign-up is not currently open for this event."
      end

      # Check if sign-up is allowed
      form = instance.sign_up_form
      if instance.status == "scheduled"
        # Pre-registration - check if talent can self pre-register and we're within the window
        unless form.allows_talent_self_pre_registration? && form.pre_registration_open_for?(show)
          return redirect_to my_requests_path, alert: "Sign-up is not currently open for this event."
        end
      end

      # Helper to check if slot has capacity
      slot_has_capacity = ->(s) {
        current = s.sign_up_registrations.where(status: %w[confirmed waitlisted]).count
        current < (s.capacity || 1)
      }

      # Find first available slot
      slot = instance.sign_up_slots.order(:position).find { |s| slot_has_capacity.call(s) }

      if slot.nil? && instance.sign_up_form.slot_generation_mode != "simple_capacity"
        return redirect_to my_requests_path, alert: "No spots available for this event."
      end

      registration = SignUpRegistration.find_or_initialize_by(
        person: person,
        sign_up_slot: slot,
        sign_up_form_instance: instance
      )

      if registration.new_record?
        registration.status = slot_has_capacity.call(slot) ? "confirmed" : "waitlisted"
        registration.registered_at = Time.current
        registration.position = slot.sign_up_registrations.maximum(:position).to_i + 1
        registration.save!
      elsif registration.status == "cancelled"
        # Re-activate cancelled registration
        registration.update!(
          status: slot_has_capacity.call(slot) ? "confirmed" : "waitlisted",
          registered_at: Time.current,
          cancelled_at: nil
        )
      end

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "request-item-#{show.id}-person_#{person.id}",
            partial: "my/open_requests/request_item",
            locals: { item: build_signup_item(show, person, instance, registration) }
          )
        end
        format.json { render json: { status: "signed_up" } }
        format.html { redirect_to my_requests_path, notice: "You've been signed up!" }
      end
    end

    def decline_signup
      show = Show.find(params[:show_id])
      person = Current.user.people.find_by(id: params[:person_id])

      unless person
        return render json: { error: "Not authorized" }, status: :forbidden
      end

      # Find any existing registration for this show (via slot -> instance -> show)
      registration = SignUpRegistration.joins(sign_up_slot: { sign_up_form_instance: :show })
                                       .where(shows: { id: show.id })
                                       .where(person_id: person.id)
                                       .where.not(status: "cancelled")
                                       .first

      if registration
        # Cancel existing registration
        registration.update!(status: "cancelled", cancelled_at: Time.current)
      end

      # Create a declined availability record to track they said no
      ShowAvailability.find_or_create_by!(
        show: show,
        available_entity_type: "Person",
        available_entity_id: person.id
      ) do |avail|
        avail.status = "no"
      end

      respond_to do |format|
        format.turbo_stream do
          instance = SignUpFormInstance.joins(:sign_up_form)
                                       .where(show_id: show.id)
                                       .first
          render turbo_stream: turbo_stream.replace(
            "request-item-#{show.id}-person_#{person.id}",
            partial: "my/open_requests/request_item",
            locals: { item: build_signup_item(show, person, instance, nil, declined: true) }
          )
        end
        format.json { render json: { status: "declined" } }
        format.html { redirect_to my_requests_path, notice: "You've declined this sign-up." }
      end
    end

    private

    def load_shows_data(selected_person_ids, selected_group_ids, people_by_id, groups_by_id)
      # Get all shows for selected entities from talent pools
      all_shows_with_source = []

      if selected_person_ids.any?
        # Person shows from direct talent pools (within 90 days)
        person_shows = Show.joins(production: { talent_pools: :people })
                           .select("shows.*, people.id as source_person_id")
                           .where(people: { id: selected_person_ids })
                           .where.not(canceled: true)
                           .where("date_and_time > ?", Time.current)
                           .where("date_and_time <= ?", 90.days.from_now)
                           .includes(:production, :location, :event_linkage, sign_up_form_instances: :sign_up_form)
                           .distinct
                           .to_a
        person_shows.each do |s|
          person_id = s.read_attribute(:source_person_id)
          person = people_by_id[person_id]
          all_shows_with_source << { show: s, entity_key: "person_#{person_id}", entity: person, entity_type: "Person" } if person
        end

        # Person shows from shared talent pools (within 90 days)
        shared_person_shows = Show.joins(production: { talent_pool_shares: { talent_pool: :people } })
                                  .select("shows.*, people.id as source_person_id")
                                  .where(people: { id: selected_person_ids })
                                  .where.not(canceled: true)
                                  .where("date_and_time > ?", Time.current)
                                  .where("date_and_time <= ?", 90.days.from_now)
                                  .includes(:production, :location, :event_linkage, sign_up_form_instances: :sign_up_form)
                                  .distinct
                                  .to_a
        shared_person_shows.each do |s|
          person_id = s.read_attribute(:source_person_id)
          person = people_by_id[person_id]
          unless all_shows_with_source.any? { |item| item[:show].id == s.id && item[:entity_key] == "person_#{person_id}" }
            all_shows_with_source << { show: s, entity_key: "person_#{person_id}", entity: person, entity_type: "Person" } if person
          end
        end
      end

      if selected_group_ids.any?
        # Group shows from direct talent pools (within 90 days)
        group_shows = Show.select("shows.*, groups.id as source_group_id")
                          .joins(production: { talent_pools: :groups })
                          .where(groups: { id: selected_group_ids })
                          .where.not(canceled: true)
                          .where("date_and_time > ?", Time.current)
                          .where("date_and_time <= ?", 90.days.from_now)
                          .includes(:production, :location, :event_linkage, sign_up_form_instances: :sign_up_form)
                          .distinct
                          .to_a

        group_shows.each do |show|
          group_id = show.read_attribute(:source_group_id)
          group = groups_by_id[group_id]
          all_shows_with_source << { show: show, entity_key: "group_#{group_id}", entity: group, entity_type: "Group" }
        end

        # Group shows from shared talent pools (within 90 days)
        shared_group_shows = Show.select("shows.*, groups.id as source_group_id")
                                 .joins(production: { talent_pool_shares: { talent_pool: :groups } })
                                 .where(groups: { id: selected_group_ids })
                                 .where.not(canceled: true)
                                 .where("date_and_time > ?", Time.current)
                                 .where("date_and_time <= ?", 90.days.from_now)
                                 .includes(:production, :location, :event_linkage, sign_up_form_instances: :sign_up_form)
                                 .distinct
                                 .to_a

        shared_group_shows.each do |show|
          group_id = show.read_attribute(:source_group_id)
          group = groups_by_id[group_id]
          unless all_shows_with_source.any? { |item| item[:show].id == show.id && item[:entity_key] == "group_#{group_id}" }
            all_shows_with_source << { show: show, entity_key: "group_#{group_id}", entity: group, entity_type: "Group" }
          end
        end
      end

      # Get unique shows
      show_ids = all_shows_with_source.map { |item| item[:show].id }.uniq

      # Get shows with active sign-up forms (exclude archived forms)
      shows_with_signup = SignUpFormInstance.joins(:sign_up_form)
                                            .where(show_id: show_ids)
                                            .where(status: %w[scheduled open])
                                            .where(sign_up_forms: { archived_at: nil })
                                            .pluck(:show_id)
                                            .to_set

      # Batch fetch ALL availabilities
      all_availabilities = fetch_availabilities(show_ids, selected_person_ids, selected_group_ids)

      # Batch fetch registrations for person entities
      # Join through slot -> instance -> show since some registrations have nil sign_up_form_instance_id
      all_registrations = if selected_person_ids.any?
                            SignUpRegistration.joins(sign_up_slot: { sign_up_form_instance: :show })
                                              .where(shows: { id: show_ids })
                                              .where(person_id: selected_person_ids)
                                              .where.not(status: "cancelled")
                                              .includes(sign_up_slot: :sign_up_form_instance)
                                              .index_by { |r| [ r.sign_up_slot.sign_up_form_instance.show_id, r.person_id ] }
      else
                            {}
      end

      # Separate into availability items vs signup items
      @availability_items = []
      @signup_items = []

      all_shows_with_source.each do |item|
        show = item[:show]
        entity = item[:entity]
        entity_key = item[:entity_key]
        entity_type = item[:entity_type]

        if shows_with_signup.include?(show.id)
          # This is a sign-up show (only for people, not groups)
          next unless entity_type == "Person"

          instance = show.sign_up_form_instances.find { |i|
            %w[scheduled open].include?(i.status) && i.sign_up_form&.archived_at.nil?
          }
          next unless instance

          # Check if talent can see this signup form
          form = instance.sign_up_form
          if instance.status == "scheduled"
            # Form not yet open - only show if talent self pre-registration is allowed
            # and within the pre-registration window
            next unless form.allows_talent_self_pre_registration? && form.pre_registration_open_for?(show)
          end

          registration = all_registrations[[ show.id, entity.id ]]

          @signup_items << build_signup_item(show, entity, instance, registration)
        else
          # This is an availability show
          availability = all_availabilities[[ show.id, entity_type, entity.id ]]
          @availability_items << build_availability_item(show, entity, availability, entity_type:, entity_key:)
        end
      end

      # Apply filter
      if @filter == "awaiting"
        @availability_items = @availability_items.select { |i| i[:availability].nil? }
        @signup_items = @signup_items.select { |i| i[:registration].nil? && !i[:declined] }
      end

      # Sort by date
      @availability_items.sort_by! { |i| i[:show].date_and_time }
      @signup_items.sort_by! { |i| i[:show].date_and_time }
    end

    def load_non_event_signups(selected_person_ids, people_by_id)
      @non_event_signups = []

      return unless selected_person_ids.any?

      # We only show non-event sign-ups when filter is "all"
      return if @filter == "awaiting"

      # Get sign-up registrations from shared_pool forms (not tied to specific events)
      registrations = SignUpRegistration
        .eager_load(sign_up_slot: { sign_up_form_instance: :show, sign_up_form: :production })
        .where(person_id: selected_person_ids)
        .where.not(status: "cancelled")
        .to_a
        .select do |reg|
          form = reg.sign_up_slot&.sign_up_form
          next false unless form&.shared_pool? && !form.archived? && form.active?
          # Only include if form is still accepting or has active registrations
          form.status_service&.accepting_registrations? || reg.status == "confirmed"
        end

      # Group by form
      registrations_by_form = registrations.group_by { |r| r.sign_up_slot&.sign_up_form }

      registrations_by_form.each do |form, regs|
        next unless form

        @non_event_signups << {
          form: form,
          production: form.production,
          registrations: regs,
          people: regs.map { |r| people_by_id[r.person_id] }.compact.uniq
        }
      end

      # Sort by form name
      @non_event_signups.sort_by! { |item| item[:form].name.downcase }
    end

    def load_questionnaires_data(selected_person_ids, people_by_id)
      @questionnaire_items = []

      return unless selected_person_ids.any?

      # Get questionnaires for selected profiles
      questionnaire_ids = QuestionnaireInvitation.where(invitee_type: "Person", invitee_id: selected_person_ids)
                                                 .pluck(:questionnaire_id)
                                                 .uniq

      questionnaires = Questionnaire.where(id: questionnaire_ids)
                                    .includes(:production, :questionnaire_invitations, :questionnaire_responses)

      questionnaires.each do |questionnaire|
        selected_person_ids.each do |person_id|
          person = people_by_id[person_id]
          next unless questionnaire.questionnaire_invitations.any? { |i| i.invitee_id == person_id && i.invitee_type == "Person" }

          responded = questionnaire.questionnaire_responses.any? { |r| r.respondent_id == person_id && r.respondent_type == "Person" }

          # Only include if awaiting filter is off OR not responded
          next if @filter == "awaiting" && responded
          next if questionnaire.archived_at.present?
          next unless questionnaire.accepting_responses

          @questionnaire_items << {
            questionnaire: questionnaire,
            entity: person,
            entity_key: "person_#{person_id}",
            responded: responded
          }
        end
      end

      @questionnaire_items.sort_by! { |i| i[:questionnaire].created_at }.reverse!
    end

    def fetch_availabilities(show_ids, selected_person_ids, selected_group_ids)
      conditions = []
      params = []

      selected_person_ids.each do |pid|
        conditions << "(available_entity_type = 'Person' AND available_entity_id = ?)"
        params << pid
      end

      selected_group_ids.each do |gid|
        conditions << "(available_entity_type = 'Group' AND available_entity_id = ?)"
        params << gid
      end

      return {} if conditions.empty?

      ShowAvailability.where(show_id: show_ids)
                      .where(conditions.join(" OR "), *params)
                      .index_by { |a| [ a.show_id, a.available_entity_type, a.available_entity_id ] }
    end

    def build_availability_item(show, entity, availability, entity_type: nil, entity_key: nil)
      entity_type ||= entity.is_a?(Person) ? "Person" : "Group"
      entity_key ||= "#{entity_type.downcase}_#{entity.id}"

      {
        type: :availability,
        show: show,
        entity: entity,
        entity_type: entity_type,
        entity_key: entity_key,
        availability: availability
      }
    end

    def build_signup_item(show, person, instance, registration, declined: false)
      # Check if they declined via availability OR cancelled signup registration
      unless declined
        declined = ShowAvailability.exists?(
          show_id: show.id,
          available_entity_type: "Person",
          available_entity_id: person.id,
          status: "no"
        ) || SignUpRegistration.joins(sign_up_slot: { sign_up_form_instance: :show })
                               .where(shows: { id: show.id })
                               .where(person_id: person.id)
                               .where(status: "cancelled")
                               .exists?
      end

      {
        type: :signup,
        show: show,
        entity: person,
        entity_type: "Person",
        entity_key: "person_#{person.id}",
        instance: instance,
        registration: registration,
        declined: declined
      }
    end
  end
end
