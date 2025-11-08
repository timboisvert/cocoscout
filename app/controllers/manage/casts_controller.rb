class Manage::CastsController < Manage::ManageController
  before_action :set_production
  before_action :check_production_access
  before_action :set_cast, only: %i[ edit update destroy ]
  before_action :ensure_user_is_manager, except: %i[index]

  def index
    @casts = @production.casts.all
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
      redirect_to manage_production_casts_path(@production), notice: "Cast was successfully created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @cast.update(cast_params)
      redirect_to manage_production_casts_path(@production), notice: "Cast was successfully updated", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @cast.destroy!
    redirect_to manage_production_casts_path(@production), notice: "Cast was successfully deleted", status: :see_other
  end

  def add_person
    @cast = @production.casts.find(params[:id])
    person = Current.production_company.people.find(params[:person_id])
    @cast.people << person unless @cast.people.exists?(person.id)
    render partial: "manage/casts/cast_members_list", locals: { cast: @cast }
  end

  def remove_person
    @cast = @production.casts.find(params[:id])
    person = Current.production_company.people.find(params[:person_id])
    @cast.people.delete(person)

    # If it's an AJAX request, render the partial; otherwise redirect
    if request.xhr?
      render partial: "manage/casts/cast_members_list", locals: { cast: @cast }
    else
      redirect_to request.referrer || manage_production_auditions_casting_path(@production), notice: "Person removed from cast"
    end
  end

  def search_people
    q = params[:q].to_s.strip
    cast_id = params[:cast_id].to_s.strip

    @people = if q.present?
      Current.production_company.people.where("name LIKE :q OR email LIKE :q", q: "%#{q}%")
    else
      Person.none
    end

    # Exclude people already in the selected cast
    if cast_id.present?
      cast = @production.casts.find(cast_id)
      @people = @people.where.not(id: cast.people.pluck(:id))
    end

    render partial: "manage/casts/search_results", locals: { people: @people, cast_id: cast_id }
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
