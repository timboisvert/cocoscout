# frozen_string_literal: true

module Manage
  # Org-level money settings. Built as a routed-section page (like ContractSettings)
  # so it can grow more topics: the offline payment methods an org uses to pay
  # people outside CocoScout's Stripe rail, who hears about payout runs, and
  # where the org sells tickets.
  class MoneySettingsController < Manage::ManageController
    SECTIONS = %w[offline_methods notifications ticket_sources].freeze
    SECTION_LABELS = {
      "offline_methods" => "Offline Methods",
      "notifications" => "Notifications",
      "ticket_sources" => "Ticket Sources"
    }.freeze
    DEFAULT_SECTION = "offline_methods"

    before_action :set_section, only: %i[show]
    before_action :set_ticket_source, only: %i[update_ticket_source archive_ticket_source restore_ticket_source]

    def show
      case @section
      when "offline_methods"
        @enabled_offline_payout_methods = Current.organization.enabled_offline_payout_methods
      when "notifications"
        @notification_managers = Current.organization.contract_notification_manager_users.order(:email_address)
        @notification_selected_ids = Current.organization.payout_notification_user_ids
      when "ticket_sources"
        @ticket_sources = Current.organization.ticket_sources.active.ordered.to_a
        @archived_ticket_sources = Current.organization.ticket_sources.archived.ordered.to_a
      end
    end

    # --- Ticket sources ---------------------------------------------------------
    # Where this org sells tickets. A show's financials carry one sales line per
    # source, so this list is what that picker offers.

    def create_ticket_source
      source = Current.organization.ticket_sources.new(ticket_source_params)
      source.position = (Current.organization.ticket_sources.maximum(:position) || 0) + 1

      if source.save
        redirect_to section_path("ticket_sources"), notice: "Added #{source.name}."
      else
        redirect_to section_path("ticket_sources"), alert: source.errors.full_messages.to_sentence
      end
    end

    def update_ticket_source
      if @ticket_source.update(ticket_source_params)
        redirect_to section_path("ticket_sources"), notice: "Ticket source updated."
      else
        redirect_to section_path("ticket_sources"), alert: @ticket_source.errors.full_messages.to_sentence
      end
    end

    # Archived, never destroyed: sales lines already recorded through this source
    # have to keep saying where that money came from.
    def archive_ticket_source
      @ticket_source.archive!
      redirect_to section_path("ticket_sources"),
                  notice: "#{@ticket_source.name} won't be offered on new entries. Sales already recorded through it are untouched."
    end

    def restore_ticket_source
      @ticket_source.restore!
      redirect_to section_path("ticket_sources"), notice: "#{@ticket_source.name} is back on the list."
    end

    # Which managers get an email when a payout run is submitted. Store only ids
    # that are actually current managers; empty selection means "no one".
    def update_notifications
      manager_ids = Current.organization.contract_notification_manager_users.pluck(:id)
      selected = Array(params[:notification_user_ids]).map(&:to_i) & manager_ids
      Current.organization.update!(payout_notification_user_ids: selected)
      redirect_to section_path("notifications"), notice: "Payout notification recipients updated."
    end

    # The "other ways" this org sometimes pays people (cash/check/Zelle/Venmo/other).
    # Stripe is always the default rail, so only these opt-in methods are stored.
    def update_offline_methods
      methods = Array(params[:offline_payout_methods]) & ShowPayoutLineItem::MANUAL_PAYMENT_METHODS
      Current.organization.update!(enabled_offline_payout_methods: methods)
      redirect_to section_path("offline_methods"), notice: "Money settings updated."
    end

    private

    # The tab strip — one real URL per section, keyed by name so adding a section
    # never moves anybody else's link.
    def sections
      SECTIONS.map do |key|
        { key: key, label: SECTION_LABELS.fetch(key, key.titleize), path: section_path(key) }
      end
    end
    helper_method :sections

    def section_path(key)
      manage_money_settings_section_path(section: key)
    end

    def set_section
      @section = params[:section].presence || DEFAULT_SECTION
      redirect_to section_path(DEFAULT_SECTION) unless @section.in?(SECTIONS)
    end

    # Scoped to the current org — a bare find here would reach another org's list.
    def set_ticket_source
      @ticket_source = Current.organization.ticket_sources.find(params[:id])
    end

    def ticket_source_params
      params.require(:ticket_source).permit(:name, :position)
    end
  end
end
