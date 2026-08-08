# frozen_string_literal: true

module Manage
  module Staffing
    # Org-level staffing settings, built as a routed-section page (like
    # ContractSettings / MoneySettings): each topic is its own tab with a real
    # URL. Sections: the employee agreements staff sign during onboarding (the
    # agreement-template CRUD lives in AgreementTemplatesController and
    # redirects back here), and who's hidden from the Pay People grid.
    class SettingsController < Manage::ManageController
      SECTIONS = %w[agreements pay_people role_call notifications].freeze
      SECTION_LABELS = { "agreements" => "Staff agreements", "pay_people" => "Pay People list",
                         "role_call" => "Role Call", "notifications" => "Notifications" }.freeze
      DEFAULT_SECTION = "agreements"

      before_action :set_section, only: %i[show]

      def show
        case @section
        when "agreements"
          @agreement_templates = Current.organization.staff_agreement_templates.order(:name)
        when "pay_people"
          # Only active members are pickable — inactive ones are hidden from
          # the pay grid automatically.
          @active_staff_members = Current.organization.organization_staff_members.active
                                         .includes(:person).order("people.name").references(:person)
        when "role_call"
          # Every per-show role, in or out — the same set the roles page edits
          # one at a time, gathered here so the whole roster reads at a glance.
          @role_call_roles = Current.organization.house_roles.active
                                    .where(role_type: ::HouseRole.role_types[:show_specific]).ordered.to_a
        when "notifications"
          @notification_managers = Current.organization.contract_notification_manager_users.order(:email_address)
          @notification_selected_ids = Current.organization.staffing_notification_user_ids
        end
      end

      # Independent settings post here: the required staff agreement, the Pay
      # People exclusions, and the show-coverage assistant toggle. Each form
      # submits only its own params, so we branch on what arrived.
      def update
        if params.key?(:excluded_staff_member_ids) || params[:excluding_from_pay].present?
          update_pay_exclusions
        elsif params[:updating_coverage].present?
          update_coverage_alerts
        elsif params[:updating_role_call_roles].present?
          update_role_call_roles
        elsif params[:updating_notifications].present?
          update_notification_recipients
        else
          update_required_agreement
        end
      end

      private

      # The tab strip — one real URL per section, keyed by name so adding a
      # section never moves anybody else's link.
      def sections
        SECTIONS.map do |key|
          { key: key, label: SECTION_LABELS.fetch(key, key.titleize), path: section_path(key) }
        end
      end
      helper_method :sections

      def section_path(key)
        manage_staffing_settings_section_path(section: key)
      end

      def set_section
        @section = params[:section].presence || DEFAULT_SECTION
        redirect_to section_path(DEFAULT_SECTION) unless @section.in?(SECTIONS)
      end

      # Declare whether staff must sign an agreement — and which one. Blank clears
      # the requirement. We only accept a template that belongs to this org.
      def update_required_agreement
        template_id = params[:required_staff_agreement_template_id].presence
        template = template_id && Current.organization.staff_agreement_templates.find_by(id: template_id)

        Current.organization.update!(required_staff_agreement_template: template)
        redirect_to section_path("agreements"),
                    notice: if template
                              "Staff are now required to sign “#{template.name}.”"
                            else
                              "Staff are no longer required to sign an agreement."
                            end
      end

      # The submitted checkbox set is the full excluded list — anyone active and
      # unchecked is re-included. (excluding_from_pay is a marker param so an
      # all-unchecked submit still routes here.)
      def update_pay_exclusions
        excluded_ids = Array(params[:excluded_staff_member_ids]).map(&:to_i).reject(&:zero?)
        scope = Current.organization.organization_staff_members.active
        now = Time.current
        scope.where(id: excluded_ids).update_all(excluded_from_pay: true, updated_at: now)
        scope.where.not(id: excluded_ids).where(excluded_from_pay: true).update_all(excluded_from_pay: false, updated_at: now)

        count = scope.where(excluded_from_pay: true).count
        redirect_to section_path("pay_people"),
                    notice: count.positive? ? "#{helpers.pluralize(count, 'person')} hidden from the Pay People list." : "Everyone shows on the Pay People list."
      end

      # Role Call: when on, the scheduling page checks every show against the
      # show-specific roles and flags the ones still missing coverage.
      # (updating_coverage is a marker param so an unchecked box still routes
      # here and turns it off.)
      def update_coverage_alerts
        enabled = params[:alert_uncovered_show_roles].present?
        Current.organization.update!(alert_uncovered_show_roles: enabled)
        redirect_to section_path("role_call"),
                    notice: enabled ? "Role Call is on — scheduling now checks every show for its roles." : "Role Call turned off."
      end

      # Which per-show roles Role Call actually checks. The submitted set is the
      # full included list — any per-show role left unchecked sits it out. Scoped
      # to this org's per-show roles, so a stray id can't reach anyone else's
      # roles or quietly flip a house role. (updating_role_call_roles is a marker
      # param so an all-unchecked submit still routes here.)
      def update_role_call_roles
        scope = Current.organization.house_roles.active.where(role_type: ::HouseRole.role_types[:show_specific])
        included_ids = Array(params[:role_call_role_ids]).map(&:to_i).reject(&:zero?)
        now = Time.current
        scope.where(id: included_ids).where(include_in_role_call: false)
             .update_all(include_in_role_call: true, updated_at: now)
        scope.where.not(id: included_ids).where(include_in_role_call: true)
             .update_all(include_in_role_call: false, updated_at: now)

        left_out = scope.where(include_in_role_call: false).count
        redirect_to section_path("role_call"),
                    notice: if left_out.zero?
                              "Role Call is checking every per-show role."
                            else
                              "#{helpers.pluralize(left_out, 'role')} now sitting Role Call out."
                            end
      end

      # Which managers get an in-app message when a staff member can't make a
      # shift. Store only ids that are actually current managers; empty means
      # nobody is notified. (updating_notifications is a marker param so an
      # all-unchecked submit still routes here.)
      def update_notification_recipients
        manager_ids = Current.organization.contract_notification_manager_users.pluck(:id)
        selected = Array(params[:notification_user_ids]).map(&:to_i) & manager_ids
        Current.organization.update!(staffing_notification_user_ids: selected)
        redirect_to section_path("notifications"), notice: "Notification recipients updated."
      end
    end
  end
end
