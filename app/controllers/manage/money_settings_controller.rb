# frozen_string_literal: true

module Manage
  # Org-level money settings. Built as a routed-section page (like ContractSettings)
  # so it can grow more topics later; for now the only section is the offline
  # payment methods an org uses to pay people outside CocoScout's Stripe rail.
  class MoneySettingsController < Manage::ManageController
    SECTIONS = %w[offline_methods].freeze
    DEFAULT_SECTION = "offline_methods"

    before_action :set_section, only: %i[show]

    def show
      case @section
      when "offline_methods"
        @enabled_offline_payout_methods = Current.organization.enabled_offline_payout_methods
      end
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
        { key: key, label: key.titleize, path: section_path(key) }
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
  end
end
