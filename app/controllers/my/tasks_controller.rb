# frozen_string_literal: true

module My
  # My Tasks: the one place a talent user sees everything waiting on them —
  # availability requests, sign-ups, questionnaires — plus the availability
  # they've already given (so they can change it). All list/count logic
  # lives in TaskListService, shared with the nav badge and dashboard card.
  class TasksController < ApplicationController
    def index
      @person = Current.user.person
      service = build_service
      @people = service.people
      @groups = service.groups

      @open_availability_items = service.open_availability_items
      @answered_availability_items = service.answered_availability_items
      @open_signup_items = service.open_signup_items
      @answered_signup_items = service.answered_signup_items
      @non_event_signups = service.non_event_signups
      @open_questionnaire_items = service.open_questionnaire_items
      @completed_questionnaire_items = service.completed_questionnaire_items

      @counts = service.counts
      @has_any_productions = service.any_productions?
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
        return redirect_to my_tasks_path, alert: "Sign-up is not currently open for this event."
      end

      # Check if sign-up is allowed
      form = instance.sign_up_form
      if instance.status == "scheduled"
        # Pre-registration - check if talent can self pre-register and we're within the window
        unless form.allows_talent_self_pre_registration? && form.pre_registration_open_for?(show)
          return redirect_to my_tasks_path, alert: "Sign-up is not currently open for this event."
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
        return redirect_to my_tasks_path, alert: "No spots available for this event."
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
            partial: "my/tasks/signup_item",
            locals: { item: TaskListService.build_signup_item(show, person, instance, registration) }
          )
        end
        format.json { render json: { status: "signed_up" } }
        format.html { redirect_to my_tasks_path, notice: "You've been signed up!" }
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

      # Create or update a declined availability record to track they said no
      availability = ShowAvailability.find_or_initialize_by(
        show: show,
        available_entity_type: "Person",
        available_entity_id: person.id
      )
      availability.status = "unavailable"
      availability.save!

      respond_to do |format|
        format.turbo_stream do
          instance = SignUpFormInstance.joins(:sign_up_form)
                                       .where(show_id: show.id)
                                       .first
          render turbo_stream: turbo_stream.replace(
            "request-item-#{show.id}-person_#{person.id}",
            partial: "my/tasks/signup_item",
            locals: { item: TaskListService.build_signup_item(show, person, instance, nil, declined: true) }
          )
        end
        format.json { render json: { status: "declined" } }
        format.html { redirect_to my_tasks_path, notice: "You've declined this sign-up." }
      end
    end

    private

    def build_service
      people = Current.user.people.active.order(:created_at).to_a
      groups = Group.active
                    .joins(:group_memberships)
                    .where(group_memberships: { person_id: people.map(&:id) })
                    .distinct
                    .order(:name)
                    .to_a

      default_entities = people.map { |p| "person_#{p.id}" } + groups.map { |g| "group_#{g.id}" }
      @entity_filter = params[:entity] ? params[:entity].split(",") : default_entities

      TaskListService.new(
        Current.user,
        selected_person_ids: people.select { |p| @entity_filter.include?("person_#{p.id}") }.map(&:id),
        selected_group_ids: groups.select { |g| @entity_filter.include?("group_#{g.id}") }.map(&:id)
      )
    end
  end
end
