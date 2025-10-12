class Manage::LocationsController < Manage::ManageController
  before_action :set_location, only: %i[ show edit update destroy ]

  def index
    @locations = Location.all
  end

  def show
  end

  def new
    @location = Current.production_company.locations.new
  end

  def edit
  end

  def create
    @location = Current.production_company.locations.new(location_params)

    if @location.save
      redirect_to [ :manage, :locations ], notice: "Location was successfully created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @location.update(location_params)
      redirect_to [ :manage, :locations ], notice: "Location was successfully updated", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @location.destroy!
    redirect_to manage_locations_path, notice: "Location was successfully deleted", status: :see_other
  end

  private

    def set_location
      @location = Location.find(params.expect(:id))
    end

    def location_params
      params.expect(location: [ :name, :address1, :address2, :city, :state, :postal_code, :notes ])
    end
end
