# frozen_string_literal: true

module Manage
  # The organization's services, edited on Organization settings → Services
  # (after-V1 #6): what it offers productions, its default price, and the roles
  # that do it. Pro and managers only (PaidFeatureGate maps this controller to
  # :services); the list itself renders in organizations/sections/_services.
  class HouseServicesController < Manage::ManageController
    before_action :set_service, only: %i[update destroy]

    def create
      service = Current.organization.house_services.new(position: next_position)
      if save_service(service)
        redirect_to services_path, notice: "#{service.name} added."
      else
        redirect_to services_path, alert: service.errors.full_messages.to_sentence
      end
    end

    def update
      if save_service(@service)
        redirect_to services_path, notice: "#{@service.name} saved."
      else
        redirect_to services_path, alert: @service.errors.full_messages.to_sentence
      end
    end

    # Productions and shows that needed it stop needing it; contracts already
    # written keep their own line for it.
    def destroy
      @service.destroy!
      redirect_to services_path, notice: "#{@service.name} removed."
    end

    private

    def set_service
      @service = Current.organization.house_services.find(params[:id])
    end

    def services_path
      section_manage_organization_path(Current.organization, section: "services")
    end

    def next_position
      (Current.organization.house_services.maximum(:position) || -1) + 1
    end

    # Name, default price and unit, and the roles that do it (any of the
    # organization's own, or none for equipment or a fee).
    def save_service(service)
      attrs = params.require(:house_service).permit(:name, :default_price, :unit, house_role_ids: [])
      service.name = attrs[:name].to_s.strip
      service.default_price_cents = HouseService.cents_from(attrs[:default_price]) || 0
      service.unit = attrs[:unit].presence || service.unit
      role_ids = Array(attrs[:house_role_ids]).compact_blank.map(&:to_i)

      HouseService.transaction do
        service.save!
        service.house_roles = Current.organization.house_roles.where(id: role_ids).to_a
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end
  end
end
