class Manage::LocationsController < Manage::ManageController
  before_action :set_location, only: %i[ show edit update destroy cannot_delete ]
  before_action :ensure_user_is_global_manager, except: %i[index show]

  def index
    # Redirect to organization settings page with locations tab
    redirect_to manage_organization_path(Current.organization, anchor: "tab-2")
  end

  def show
    redirect_to manage_organization_path(Current.organization, anchor: "tab-2")
  end

  def new
    redirect_to manage_organization_path(Current.organization, anchor: "tab-2")
  end

  def edit
    redirect_to manage_organization_path(Current.organization, anchor: "tab-2")
  end

  def create
    @location = Current.organization.locations.new(location_params)

    if @location.save
      expire_locations_cache
      # Handle AJAX requests (from modal)
      if request.accept == "application/json" || request.xhr?
        render json: { id: @location.id, name: @location.name }, status: :created
      else
        redirect_to manage_organization_path(Current.organization, anchor: "tab-2"), notice: "Location was successfully created"
      end
    else
      # Handle AJAX error requests
      if request.accept == "application/json" || request.xhr?
        render json: { errors: @location.errors.messages }, status: :unprocessable_entity
      else
        redirect_to manage_organization_path(Current.organization, anchor: "tab-2"), alert: "Could not create location"
      end
    end
  end

  def update
    if @location.update(location_params)
      expire_locations_cache
      # Handle AJAX requests (from modal)
      if request.accept == "application/json" || request.xhr?
        render json: { id: @location.id, name: @location.name }, status: :ok
      else
        redirect_to manage_organization_path(Current.organization, anchor: "tab-2"), notice: "Location was successfully updated", status: :see_other
      end
    else
      # Handle AJAX error requests
      if request.accept == "application/json" || request.xhr?
        render json: { errors: @location.errors.messages }, status: :unprocessable_entity
      else
        redirect_to manage_organization_path(Current.organization, anchor: "tab-2"), alert: "Could not update location"
      end
    end
  end

  def destroy
    if @location.has_upcoming_events?
      redirect_to manage_organization_path(Current.organization, anchor: "tab-2"), alert: "Cannot delete location with upcoming events"
    else
      @location.destroy!
      expire_locations_cache
      redirect_to manage_organization_path(Current.organization, anchor: "tab-2"), notice: "Location was successfully deleted", status: :see_other
    end
  end

  def cannot_delete
    redirect_to manage_organization_path(Current.organization, anchor: "tab-2"), alert: "Cannot delete location with upcoming events"
  end

  private

    def set_location
      @location = Location.find(params.expect(:id))
    end

    def location_params
      params.expect(location: [ :name, :address1, :address2, :city, :state, :postal_code, :notes, :default ])
    end

    def fetch_locations
      Rails.cache.fetch(locations_cache_key, expires_in: 10.minutes) do
        Current.organization.locations.order(:created_at).to_a
      end
    end

    def locations_cache_key
      max_updated = Current.organization.locations.maximum(:updated_at)
      [ "locations_v1", Current.organization.id, max_updated ]
    end

    def expire_locations_cache
      Rails.cache.delete(locations_cache_key)
    end
end
