# frozen_string_literal: true

module Manage
  # Org-level contract settings. Each topic is its own routed section rendered
  # as a tab, so only the section you're looking at loads its data and a link
  # can point straight at it.
  class ContractSettingsController < Manage::ManageController
    SECTIONS = %w[payments services templates signing notifications].freeze
    DEFAULT_SECTION = "payments"

    before_action :set_section, only: %i[show]
    before_action :set_service, only: %i[update_service destroy_service]

    def show
      case @section
      when "payments"
        @offline_payment_methods = Current.organization.default_offline_payment_methods
      when "services"
        @services = Current.organization.contract_service_options.ordered
        @service = Current.organization.contract_service_options.new(unit: "hourly", default_direction: "incoming")
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

    def create_service
      service = Current.organization.contract_service_options.new(service_params)
      if service.save
        redirect_to section_path("services"), notice: "Service added."
      else
        redirect_to section_path("services"), alert: service.errors.full_messages.join(", ")
      end
    end

    def update_service
      if @service.update(service_params)
        redirect_to section_path("services"), notice: "Service updated."
      else
        redirect_to section_path("services"), alert: @service.errors.full_messages.join(", ")
      end
    end

    def destroy_service
      @service.destroy
      redirect_to section_path("services"), notice: "Service removed."
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

    def set_service
      @service = Current.organization.contract_service_options.find(params[:id])
    end

    def service_params
      permitted = params.require(:contract_service_option).permit(:name, :unit, :default_direction, :default_price, :booking_mode)
      price = permitted.delete(:default_price)
      permitted[:default_price_cents] = (price.to_f * 100).round if price.present?
      permitted
    end
  end
end
