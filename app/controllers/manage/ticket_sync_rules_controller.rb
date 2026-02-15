# frozen_string_literal: true

module Manage
  class TicketSyncRulesController < Manage::ManageController
    before_action :set_rule, only: %i[show edit update destroy run]

    def index
      @rules = Current.organization.ticket_sync_rules.includes(:ticketing_provider).order(:name)
    end

    def show
      @listings_count = @rule.listings_to_sync.count
    end

    def new
      @rule = Current.organization.ticket_sync_rules.build(
        sync_interval_minutes: 15,
        active: true
      )
      @providers = Current.organization.ticketing_providers.status_active
      @productions = Current.user.accessible_productions.order(:name)
      @locations = Current.organization.locations.order(:name)
    end

    def create
      @rule = Current.organization.ticket_sync_rules.build(rule_params)

      if @rule.save
        redirect_to manage_ticket_sync_rule_path(@rule), notice: "Sync rule created."
      else
        @providers = Current.organization.ticketing_providers.status_active
        @productions = Current.user.accessible_productions.order(:name)
        @locations = Current.organization.locations.order(:name)
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @providers = Current.organization.ticketing_providers.status_active
      @productions = Current.user.accessible_productions.order(:name)
      @locations = Current.organization.locations.order(:name)
    end

    def update
      if @rule.update(rule_params)
        redirect_to manage_ticket_sync_rule_path(@rule), notice: "Sync rule updated."
      else
        @providers = Current.organization.ticketing_providers.status_active
        @productions = Current.user.accessible_productions.order(:name)
        @locations = Current.organization.locations.order(:name)
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @rule.destroy
      redirect_to manage_ticket_sync_rules_path, notice: "Sync rule deleted."
    end

    def run
      @rule.execute!
      redirect_to manage_ticket_sync_rule_path(@rule),
        notice: "Sync rule executed. Next sync scheduled for #{@rule.next_sync_at.strftime('%H:%M')}."
    end

    private

    def set_rule
      @rule = Current.organization.ticket_sync_rules.find(params[:id])
    end

    def rule_params
      params.require(:ticket_sync_rule).permit(
        :name,
        :ticketing_provider_id,
        :rule_type,
        :sync_interval_minutes,
        :active,
        rule_config: {}
      )
    end
  end
end
