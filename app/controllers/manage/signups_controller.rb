# frozen_string_literal: true

module Manage
  class SignupsController < Manage::ManageController
    before_action :set_production, except: [ :org_index ]
    before_action :check_production_access, except: [ :org_index ]
    before_action :check_not_third_party, except: [ :org_index ]

    # GET /signups (org-wide)
    def org_index
      # Get in-house productions the user has access to (exclude third-party)
      @productions = Current.user.accessible_productions.castable
                            .includes(posters: { image_attachment: :blob })
                            .order(:name)

      # What's waiting on this user first, then one row per sign-up form or
      # audition (Tim, 2026-11-20). Filters: ?show=forms|auditions,
      # ?production=<id>, ?closed=1.
      @to_review = AuditionsToReview.for(user: Current.user, productions: @productions)
      overview = SignupsOverview.new(productions: @productions, to_review: @to_review, path_for: lambda { |kind, production, record|
        kind == :form ? manage_signups_form_path(production, record) : manage_signups_auditions_cycle_path(production, record)
      })

      @show = %w[forms auditions].include?(params[:show]) ? params[:show] : "all"
      @include_closed = params[:closed] == "1"
      @row_productions = overview.rows.map(&:production).uniq.sort_by { |p| p.name.downcase }
      @production_id = params[:production].presence&.to_i
      @production_id = nil unless @row_productions.any? { |p| p.id == @production_id }

      in_view = lambda do |rows|
        rows = rows.select(&:form?) if @show == "forms"
        rows = rows.select(&:audition?) if @show == "auditions"
        rows = rows.select { |r| r.production.id == @production_id } if @production_id
        rows
      end
      by_production = @production_id ? overview.rows.select { |r| r.production.id == @production_id } : overview.rows
      @kind_counts = { "all" => by_production.size, "forms" => by_production.count(&:form?), "auditions" => by_production.count(&:audition?) }
      @current_rows = in_view.call(overview.current)
      @closed_rows = in_view.call(overview.closed)
      @any_rows = overview.rows.any?
    end

    # GET /signups/:production_id (production-level)
    def index
      # Sign-up forms stats
      @sign_up_forms = @production.sign_up_forms.not_archived
      @active_sign_up_forms = @sign_up_forms.select { |f| f.current_status[:accepting_registrations] }
      @sign_up_forms_count = @sign_up_forms.count

      # Audition stats - only count active (non-archived) sign-ups
      @active_audition_cycle = @production.active_audition_cycle
      @audition_requests_count = @active_audition_cycle&.audition_requests&.active&.count || 0
      @past_audition_cycles_count = @production.audition_cycles.where(active: false).count

      # Sign-up form wizard in progress?
      @sign_up_wizard_in_progress = Rails.cache.read("sign_up_wizard:#{Current.user.id}:#{@production.id}").present?

      # Audition wizard in progress?
      @audition_wizard_in_progress = session[:audition_wizard].present? && session[:audition_wizard][@production.id.to_s].present?
    end

    private

    def set_production
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
      @production = Current.organization.productions.find(params.require(:production_id))
      sync_current_production(@production)
    end

    def check_not_third_party
      if @production.type_third_party?
        redirect_to manage_shows_path(@production), alert: "Sign-ups are not available for third-party productions"
      end
    end
  end
end
