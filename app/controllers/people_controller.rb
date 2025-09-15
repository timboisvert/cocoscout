class PeopleController < ApplicationController
  before_action :set_person, only: %i[ show edit update destroy ]

  def index
    @people = Person.all
  end

  def show
  end

  def new
    @person = Person.new
  end

  def edit
  end

  def create
    @person = Person.new(person_params)

    if @person.save
      redirect_to @person, notice: "Person was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @person.update(person_params)
      redirect_to @person, notice: "Person was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @person.destroy!
    redirect_to people_path, notice: "Person was successfully destroyed.", status: :see_other
  end

  # GET /people?q=searchterm
  def search
    q = params[:q].to_s.strip
    @people = if q.present?
      Person.where("stage_name LIKE :q OR email LIKE :q", q: "%#{q}%")
    else
      Person.none
    end
    result_partial = params[:result_partial].presence || "people/person_grid_item"
    result_locals = params[:result_locals] || {}

    render partial: "shared/people_search_results", locals: { people: @people, result_partial: result_partial, result_locals: result_locals }
  end



  private
    # Use callbacks to share common setup or constraints between actions.
    def set_person
      @person = Person.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def person_params
      params.expect(person: [ :stage_name, :email, :pronouns, :socials, :resume, :headshot ])
    end
end
