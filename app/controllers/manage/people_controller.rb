class Manage::PeopleController < Manage::ManageController
  before_action :set_person, only: %i[ show edit update destroy ]

  def index
    # Store the order
    @order = (params[:order] || session[:people_order] || "alphabetical")
    session[:people_order] = @order

    # Store the filter
    @filter = (params[:filter] || session[:people_filter] || "everyone")
    session[:people_filter] = @filter

    # Process the filter
    @people = Person.all

    case @filter
    when "cast-members"
      @people = @people.joins(:casts).distinct
    when "everyone"
      @people = @people.all
    else
      @filter = "everyone"
      @people = @people.all
    end

    # Process the order
    case @order
    when "alphabetical"
      @people = @people.order(:name)
    when "newest"
      @people = @people.order(created_at: :desc)
    when "oldest"
      @people = @people.order(created_at: :asc)
    else
      @filter = "alphabetical"
      @people = @people.order(:name)
    end
  end

  def show
  end

  def new
    @person = Person.new
  end

  def edit
  end

  def create
    if Person.exists?(email: person_params[:email])
      @person = Person.new(person_params)
      @user_exists_error = true
      render :new, status: :unprocessable_entity
    else
      @person = Person.new(person_params)
      if @person.save

        # Make sure we have a user
        user = User.find_or_create_by!(email_address: @person.email) do |user|
          user.password = SecureRandom.hex(16)
        end
        @person.update!(user: user)

        # TODO: Send an email to the person letting them know they have been added and
        # that they need to update their password

        redirect_to [ :manage, @person ], notice: "Person was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end
  end

  def update
    if @person.update(person_params)
      redirect_to [ :manage, @person ], notice: "Person was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @person.destroy!
    redirect_to manage_people_path, notice: "Person was successfully destroyed.", status: :see_other
  end

  # GET /people?q=searchterm
  def search
    q = params[:q].to_s.strip
    @people = if q.present?
      Person.where("name LIKE :q OR email LIKE :q", q: "%#{q}%")
    else
      Person.none
    end
    result_partial = params[:result_partial].presence || "people/person_grid_item"
    result_locals = params[:result_locals] || {}

    render partial: "shared/people_search_results", locals: { people: @people, result_partial: result_partial, result_locals: result_locals }
  end

  def add_to_cast
    @cast = Cast.find(params[:cast_id])
    @person = Person.find(params[:person_id])
    @cast.people << @person if !@cast.people.include?(@person)
    render partial: "manage/casts/cast_membership_card", locals: { person: @person, production: @cast.production }
  end

  def remove_from_cast
    @cast = Cast.find(params[:cast_id])
    @person = Person.find(params[:person_id])
    @cast.people.delete(@person) if @cast.people.include?(@person)
    render partial: "manage/casts/cast_membership_card", locals: { person: @person, production: @cast.production }
  end


  private
    # Use callbacks to share common setup or constraints between actions.
    def set_person
      @person = Person.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def person_params
      params.require(:person).permit(
        :name, :pronouns, :resume, :headshot,
        socials_attributes: [ :id, :platform, :handle, :_destroy ]
      )
    end
end
