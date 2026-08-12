# frozen_string_literal: true

module Manage
  module Staffing
    # CRUD for the org's regulars (SchedulingRule), plus the weekly bulk-apply
    # that turns approved matches into shifts. The rules page lives off the
    # Scheduling header; apply posts from the Apply-regulars modal on
    # Scheduling itself and morphs back in place.
    class SchedulingRulesController < Manage::ManageController
      include Manage::SchedulingReturn

      before_action :ensure_org_owner_or_manager
      before_action :set_rule, only: %i[update destroy]

      def index
        @rules = Current.organization.scheduling_rules.active
                        .includes(:house_role, :production, person: { profile_headshots: { image_attachment: :blob } })
                        .order(:created_at)
        @staff_members = Current.organization.organization_staff_members.active
                                .includes(:person).order("people.name").references(:person)
        @house_roles = Current.organization.house_roles.active.ordered
        @productions = Current.organization.productions.order(:name)
        @regulars_enabled = Current.organization.staffing_regulars_enabled?
      end

      def create
        @rule = Current.organization.scheduling_rules.new(scoped_rule_attrs)
        if @rule.save
          redirect_to manage_staffing_scheduling_rules_path, notice: "Added #{@rule.person.name} as a regular."
        else
          redirect_to manage_staffing_scheduling_rules_path, alert: "Couldn't add the regular: #{@rule.errors.full_messages.to_sentence}"
        end
      end

      def update
        if @rule.update(scoped_rule_attrs)
          redirect_to manage_staffing_scheduling_rules_path, notice: "Regular updated."
        else
          redirect_to manage_staffing_scheduling_rules_path, alert: "Couldn't update the regular: #{@rule.errors.full_messages.to_sentence}"
        end
      end

      def destroy
        name = @rule.person.name
        @rule.destroy!
        redirect_to manage_staffing_scheduling_rules_path, notice: "Removed #{name}'s regular slot."
      end

      # Bulk-create the checked matches for one week. The matcher re-runs
      # server-side, so the keys are only honored if they still match — a
      # stale or foreign key simply does nothing.
      def apply
        unless Current.organization.staffing_regulars_enabled?
          redirect_to scheduling_return_url, alert: "Regulars isn't turned on for this organization." and return
        end

        week_start = begin
          Date.iso8601(params[:week_start].to_s)
        rescue ArgumentError
          redirect_to scheduling_return_url, alert: "Couldn't tell which week to apply." and return
        end

        result = SchedulingRuleApplier.new(
          organization: Current.organization,
          week_start: week_start,
          match_keys: params[:match_keys]
        ).apply!

        notice =
          if result.people_assigned.zero?
            "No new shifts to add — your regulars are already scheduled."
          elsif result.shifts_created.zero?
            "Scheduled #{helpers.pluralize(result.people_assigned, 'regular')} onto existing shifts."
          else
            "Scheduled #{helpers.pluralize(result.people_assigned, 'regular')} " \
            "across #{helpers.pluralize(result.shifts_created, 'new shift')}."
          end
        redirect_to scheduling_return_url, notice: notice
      rescue ActiveRecord::RecordInvalid => e
        redirect_to scheduling_return_url, alert: "Couldn't apply your regulars: #{e.message}"
      end

      private

      def set_rule
        @rule = Current.organization.scheduling_rules.find(params[:id])
      end

      # Resolve every pointed-at record through the org's own scopes — raw ids
      # from the form are never trusted. Fields for the other rule type are
      # cleared so switching a rule's type never leaves ghost data behind.
      def scoped_rule_attrs
        permitted = params.require(:scheduling_rule)
                          .permit(:person_id, :rule_type, :house_role_id, :production_id,
                                  :day_of_week, :starts_local_time, :ends_local_time)

        attrs = {
          rule_type: permitted[:rule_type],
          person: Current.organization.people.find_by(id: permitted[:person_id]),
          house_role: Current.organization.house_roles.active.find_by(id: permitted[:house_role_id])
        }
        if permitted[:rule_type] == "weekday"
          attrs.merge(production: nil,
                      day_of_week: permitted[:day_of_week].presence&.to_i,
                      starts_local_time: permitted[:starts_local_time].presence,
                      ends_local_time: permitted[:ends_local_time].presence)
        else
          attrs.merge(production: Current.organization.productions.find_by(id: permitted[:production_id]),
                      day_of_week: nil, starts_local_time: nil, ends_local_time: nil)
        end
      end
    end
  end
end
