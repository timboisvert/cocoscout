class Manage::CastsController < Manage::ManageController
  before_action :set_production
  before_action :set_cast, only: %i[ show edit update destroy ]

  def index
    @casts = @production.casts.all
  end

  def show
  end

  def new
    @cast = @production.casts.new
  end

  def edit
  end

  def create
    @cast = @production.casts.new(cast_params)
    @cast.production = @production

    if @cast.save
      redirect_to manage_production_casts_path(@production), notice: "Cast was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @cast.update(cast_params)
      redirect_to manage_production_casts_path(@production), notice: "Cast was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @cast.destroy!
    redirect_to manage_production_casts_path(@production), notice: "Cast was successfully deleted.", status: :see_other
  end

   def add_person
    @cast = @production.casts.find(params[:id])
    person = Person.find(params[:person_id])
    @cast.people << person unless @cast.people.exists?(person.id)
    render partial: "manage/casts/cast_members_list", locals: { cast: @cast }
  end

  def remove_person
    @cast = @production.casts.find(params[:id])
    person = Person.find(params[:person_id])
    @cast.people.delete(person)
    render partial: "manage/casts/cast_members_list", locals: { cast: @cast }
  end


  private
    def set_production
      @production = Current.production_company.productions.find(params.require(:production_id))
    end

    def set_cast
      @cast = @production.casts.find(params.require(:id))
    end

    def cast_params
      params.require(:cast).permit(:production_id, :name)
    end
end
