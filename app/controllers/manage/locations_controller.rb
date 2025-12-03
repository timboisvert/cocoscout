class Manage::LocationsController < Manage::ManageController
  before_action :set_location, only: %i[ show edit update destroy cannot_delete ]
  before_action :ensure_user_is_global_manager, except: %i[index show]

  def index
    @locations = fetch_locations
  end

  def show
  end

  def new
    @location = Current.organization.locations.new
  end

  def edit
  end

  def create
    @location = Current.organization.locations.new(location_params)

    if @location.save
      expire_locations_cache
      # Handle AJAX requests (from modal)
      if request.accept == "application/json" || request.xhr?
        render json: { id: @location.id, name: @location.name }, status: :created
      else
        # Handle standard form submissions
        redirect_to [ :manage, :locations ], notice: "Location was successfully created"
      end
    else
      # Handle AJAX error requests
      if request.accept == "application/json" || request.xhr?
        render json: { errors: @location.errors.messages }, status: :unprocessable_entity
      else
        # Handle standard form submission errors
        render :new, status: :unprocessable_entity
      end
    end
  end

  def update
    if @location.update(location_params)
      expire_locations_cache
      redirect_to [ :manage, :locations ], notice: "Location was successfully updated", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @location.has_upcoming_events?
      redirect_to cannot_delete_manage_location_path(@location), status: :see_other
    else
      @location.destroy!
      expire_locations_cache
      redirect_to manage_locations_path, notice: "Location was successfully deleted", status: :see_other
    end
  end

  def cannot_delete
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
        Current.organization.locations.order(:name).to_a
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
