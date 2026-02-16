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
      # Section 2: Questionnaires
      # ========================================
      load_questionnaires_data(selected_person_ids, people_by_id)

      # Check if user has any productions (for showing filter bar)
      @has_any_productions = @availability_items.any? || @signup_items.any? || @questionnaire_items.any?

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

      # Find the sign-up form instance for this show
      instance = SignUpFormInstance.joins(:sign_up_form)
                                   .where(show_id: show.id)
                                   .where(status: "open")
                                   .first

      unless instance
        return redirect_to my_requests_path, alert: "Sign-up is not currently open for this event."
      end

      # Create or find registration
      # For simple capacity forms, we register directly to the instance
      # For slot-based forms, we need to find an available slot
      slot = instance.sign_up_slots.where("current_registrations < capacity").order(:position).first

      if slot.nil? && instance.sign_up_form.slot_generation_mode != "simple_capacity"
        return redirect_to my_requests_path, alert: "No spots available for this event."
      end

      registration = SignUpRegistration.find_or_initialize_by(
        person: person,
        sign_up_slot: slot,
        sign_up_form_instance: instance
      )

      if registration.new_record?
        registration.status = slot&.has_capacity? ? "confirmed" : "waitlisted"
        registration.save!

        # Update slot count if applicable
        slot&.increment!(:current_registrations)
      end

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "request-item-#{show.id}-person_#{person.id}",
            partial: "my/open_requests/request_item",
            locals: { item: build_signup_item(show, person, instance, registration) }
          )
        end
        format.html { redirect_to my_requests_path, notice: "You've been signed up!" }
      end
    end

    def decline_signup
      show = Show.find(params[:show_id])
      person = Current.user.people.find_by(id: params[:person_id])

      unless person
        return render json: { error: "Not authorized" }, status: :forbidden
      end

      # Find any existing registration for this show
      registration = SignUpRegistration.joins(sign_up_form_instance: :show)
                                       .where(shows: { id: show.id })
                                       .where(person_id: person.id)
                                       .where.not(status: "cancelled")
                                       .first

      if registration
        # Cancel existing registration
        registration.update!(status: "cancelled")
        registration.sign_up_slot&.decrement!(:current_registrations)
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
        format.html { redirect_to my_requests_path, notice: "You've declined this sign-up." }
      end
    end

    private

    def load_shows_data(selected_person_ids, selected_group_ids, people_by_id, groups_by_id)
      # Get all shows for selected entities from talent pools
      all_shows_with_source = []

      if selected_person_ids.any?
        # Person shows from direct talent pools
        person_shows = Show.joins(production: { talent_pools: :people })
                           .select("shows.*, people.id as source_person_id")
                           .where(people: { id: selected_person_ids })
                           .where.not(canceled: true)
                           .where("date_and_time > ?", Time.current)
                           .includes(:production, :location, :event_linkage, sign_up_form_instances: :sign_up_form)
                           .distinct
                           .to_a
        person_shows.each do |s|
          person_id = s.read_attribute(:source_person_id)
          person = people_by_id[person_id]
          all_shows_with_source << { show: s, entity_key: "person_#{person_id}", entity: person, entity_type: "Person" } if person
        end

        # Person shows from shared talent pools
        shared_person_shows = Show.joins(production: { talent_pool_shares: { talent_pool: :people } })
                                  .select("shows.*, people.id as source_person_id")
                                  .where(people: { id: selected_person_ids })
                                  .where.not(canceled: true)
                                  .where("date_and_time > ?", Time.current)
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
        # Group shows from direct talent pools
        group_shows = Show.select("shows.*, groups.id as source_group_id")
                          .joins(production: { talent_pools: :groups })
                          .where(groups: { id: selected_group_ids })
                          .where.not(canceled: true)
                          .where("date_and_time > ?", Time.current)
                          .includes(:production, :location, :event_linkage, sign_up_form_instances: :sign_up_form)
                          .distinct
                          .to_a

        group_shows.each do |show|
          group_id = show.read_attribute(:source_group_id)
          group = groups_by_id[group_id]
          all_shows_with_source << { show: show, entity_key: "group_#{group_id}", entity: group, entity_type: "Group" }
        end

        # Group shows from shared talent pools
        shared_group_shows = Show.select("shows.*, groups.id as source_group_id")
                                 .joins(production: { talent_pool_shares: { talent_pool: :groups } })
                                 .where(groups: { id: selected_group_ids })
                                 .where.not(canceled: true)
                                 .where("date_and_time > ?", Time.current)
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
                                              .index_by { |r| [r.sign_up_slot.sign_up_form_instance.show_id, r.person_id] }
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

          instance = show.sign_up_form_instances.find { |i| %w[scheduled open].include?(i.status) }
          registration = all_registrations[[show.id, entity.id]]

          @signup_items << build_signup_item(show, entity, instance, registration)
        else
          # This is an availability show
          availability = all_availabilities[[show.id, entity_type, entity.id]]
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
                      .index_by { |a| [a.show_id, a.available_entity_type, a.available_entity_id] }
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
      # Check if they declined via availability
      declined ||= ShowAvailability.exists?(
        show_id: show.id,
        available_entity_type: "Person",
        available_entity_id: person.id,
        status: "no"
      )

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
