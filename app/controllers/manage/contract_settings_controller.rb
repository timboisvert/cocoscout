# frozen_string_literal: true

module Manage
  # Org-level contract settings. Each topic is its own routed section rendered
  # as a tab, so only the section you're looking at loads its data and a link
  # can point straight at it.
  class ContractSettingsController < Manage::ManageController
    SECTIONS = %w[payments invoices services templates signing notifications].freeze
    DEFAULT_SECTION = "payments"

    before_action :set_section, only: %i[show]

    def show
      case @section
      when "payments"
        @offline_payment_methods = Current.organization.default_offline_payment_methods
      when "invoices"
        @invoice_defaults = Current.organization.defaults_for_invoices
        @invoice_details = Hash(Current.organization.invoice_details)
      when "services"
        @services = Current.organization.house_services.ordered.includes(:house_roles)
      when "templates"
        @contract_templates = Current.organization.contract_templates.order(:name)
      when "signing"
        @expiry_days = Current.organization.signature_expiry_days
      when "notifications"
        @notification_managers = Current.organization.contract_notification_manager_users.order(:email_address)
        @notification_selected_ids = Current.organization.contract_notification_user_ids
      end
    end

    # The org's default policy for how contractors may pay us. Online is always
    # available, so only the offline methods are stored.
    def update_payment_methods
      offline = Array(params[:offline_payment_methods]) & Contract::OFFLINE_PAYMENT_METHODS
      Current.organization.update!(default_contract_payment_methods: [ "online" ] + offline)
      redirect_to section_path("payments"), notice: "Payment methods updated."
    end

    # What the organization's invoices say about it, and how they're numbered.
    # Only what someone typed is stored: a blank field keeps following what
    # CocoScout already knows (the name, the tax address, the support email).
    def update_invoices
      details = params.fetch(:invoice_details, {}).permit(*Organization::INVOICE_DETAIL_KEYS).to_h
                      .transform_values { |value| value.to_s.strip }.compact_blank
      if Current.organization.update(invoice_prefix: params[:invoice_prefix], invoice_details: details)
        redirect_to section_path("invoices"), notice: "Invoice details saved."
      else
        redirect_to section_path("invoices"), alert: Current.organization.errors.full_messages.to_sentence
      end
    end

    # Which managers get an in-app message when a contract is signed. Store only
    # ids that are actually current managers; an empty selection means "all".
    def update_notifications
      manager_ids = Current.organization.contract_notification_manager_users.pluck(:id)
      selected = Array(params[:notification_user_ids]).map(&:to_i) & manager_ids
      Current.organization.update!(contract_notification_user_ids: selected)
      redirect_to section_path("notifications"), notice: "Notification recipients updated."
    end

    # How long a signature request stays valid before it expires.
    def update_signing
      days = params[:signature_expiry_days].to_i
      unless Organization::SIGNATURE_EXPIRY_CHOICES.include?(days)
        redirect_to section_path("signing"), alert: "Pick 7, 14 or 30 days." and return
      end

      Current.organization.update!(signature_expiry_days: days)
      redirect_to section_path("signing"), notice: "Contracts now expire #{days} days after they're sent."
    end

    # Which of the organization's services contracts offer, with each one's
    # usual terms. The services themselves (name, default price, roles) live in
    # Organization settings → Services.
    def update_services
      rows = params.fetch(:services, {})
      HouseService.transaction do
        Current.organization.house_services.each do |service|
          row = rows[service.id.to_s]
          next unless row

          service.update!(
            offered_on_contracts: row[:offered] == "1",
            contract_price_cents: HouseService.cents_from(row[:price]),
            contract_direction: row[:direction].presence_in(HouseService::DIRECTIONS) || service.contract_direction,
            contract_booking_mode: row[:booking_mode].presence_in(HouseService::BOOKING_MODES) || service.contract_booking_mode
          )
        end
      end
      redirect_to section_path("services"), notice: "Services on contracts saved."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to section_path("services"), alert: e.record.errors.full_messages.to_sentence
    end

    private

    # The tab strip. Each section is a real URL, keyed by name rather than
    # position, so adding one never moves anybody else's link.
    def sections
      SECTIONS.map do |key|
        { key: key, label: key.titleize, path: section_path(key) }
      end
    end
    helper_method :sections

    def section_path(key)
      manage_contract_settings_section_path(section: key)
    end

    def set_section
      @section = params[:section].presence || DEFAULT_SECTION
      redirect_to section_path(DEFAULT_SECTION) unless @section.in?(SECTIONS)
    end
  end
end
