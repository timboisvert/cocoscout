# frozen_string_literal: true

module Manage
  # Org-level contract settings — the catalog of services the org can offer on
  # contracts (technical services, booth tech, etc.) with default prices. Reached
  # from the top of the Contracts section.
  class ContractSettingsController < Manage::ManageController
    before_action :set_service, only: %i[update_service destroy_service]

    def show
      @services = Current.organization.contract_service_options.ordered
      @service = Current.organization.contract_service_options.new(unit: "hourly", default_direction: "incoming")
      @offline_payment_methods = Current.organization.default_offline_payment_methods
    end

    # The org's default policy for how contractors may pay us. Online is always
    # available, so only the offline methods are stored.
    def update_payment_methods
      offline = Array(params[:offline_payment_methods]) & Contract::OFFLINE_PAYMENT_METHODS
      Current.organization.update!(default_contract_payment_methods: [ "online" ] + offline)
      redirect_to manage_contract_settings_path, notice: "Payment methods updated."
    end

    def create_service
      service = Current.organization.contract_service_options.new(service_params)
      if service.save
        redirect_to manage_contract_settings_path, notice: "Service added."
      else
        redirect_to manage_contract_settings_path, alert: service.errors.full_messages.join(", ")
      end
    end

    def update_service
      if @service.update(service_params)
        redirect_to manage_contract_settings_path, notice: "Service updated."
      else
        redirect_to manage_contract_settings_path, alert: @service.errors.full_messages.join(", ")
      end
    end

    def destroy_service
      @service.destroy
      redirect_to manage_contract_settings_path, notice: "Service removed."
    end

    private

    def set_service
      @service = Current.organization.contract_service_options.find(params[:id])
    end

    def service_params
      permitted = params.require(:contract_service_option).permit(:name, :unit, :default_direction, :default_price)
      price = permitted.delete(:default_price)
      permitted[:default_price_cents] = (price.to_f * 100).round if price.present?
      permitted
    end
  end
end
