class Manage::PeopleController < Manage::ManageController
  before_action :set_person, only: %i[ show edit update destroy ]
  before_action :ensure_user_is_global_manager, except: %i[index show search remove_from_production_company]

  def index
    # Store the order
    @order = (params[:order] || session[:people_order] || "alphabetical")
    session[:people_order] = @order

    # Store the show
    @show = (params[:show] || session[:people_show] || "tiles")
    @show = "tiles" unless %w[tiles list].include?(@show)
    session[:people_show] = @show

    # Store the filter
    @filter = (params[:filter] || session[:people_filter] || "everyone")
    session[:people_filter] = @filter

    # Process the filter - scope to current production company
    @people = Current.production_company&.people || Person.none

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

    limit_per_page = @show == "list" ? 12 : 24
    @pagy, @people = pagy(@people, limit: limit_per_page, params: { order: @order, show: @show, filter: @filter })
  end

  def show
    # Get all future shows for productions this person is a cast member of
    production_ids = @person.casts.pluck(:production_id).uniq
    @shows = Show.where(production_id: production_ids, canceled: false)
                 .where("date_and_time >= ?", Time.current)
                 .order(:date_and_time)

    # Build a hash of availabilities: { show_id => show_availability }
    @availabilities = {}
    @person.show_availabilities.where(show: @shows).each do |availability|
      @availabilities[availability.show_id] = availability
    end
  end

  def new
    @person = Person.new
  end

  def edit
  end

  def create
    # Check if a user with this email already exists
    existing_user = User.find_by(email_address: person_params[:email])

    # Check if a person with this email already exists
    existing_person = Person.find_by(email: person_params[:email])

    if existing_user && existing_user.person
      # User and person both exist - just add to production company if not already
      existing_person = existing_user.person
      unless existing_person.production_companies.include?(Current.production_company)
        existing_person.production_companies << Current.production_company
      end

      redirect_to [ :manage, existing_person ], notice: "#{existing_person.name} has been added to #{Current.production_company.name}"
    elsif existing_person
      # Person exists but no user - create user and link them
      unless existing_person.production_companies.include?(Current.production_company)
        existing_person.production_companies << Current.production_company
      end

      user = User.create!(
        email_address: existing_person.email,
        password: SecureRandom.hex(16)
      )
      user.generate_invitation_token
      existing_person.update!(user: user)

      # Send invitation email
      AuthMailer.invitation(user).deliver_later

      redirect_to [ :manage, existing_person ], notice: "User account created and invitation sent to #{existing_person.name}"
    else
      # Create both person and user
      @person = Person.new(person_params)
      if @person.save
        # Associate with current production company
        @person.production_companies << Current.production_company

        user = User.create!(
          email_address: @person.email,
          password: SecureRandom.hex(16)
        )
        user.generate_invitation_token
        @person.update!(user: user)

        # Send invitation email
        AuthMailer.invitation(user).deliver_later

        redirect_to [ :manage, @person ], notice: "Person was successfully created and invitation sent"
      else
        render :new, status: :unprocessable_entity
      end
    end
  end

  def update
    if @person.update(person_params)
      redirect_to [ :manage, @person ], notice: "Person was successfully updated", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @person.destroy!
    redirect_to manage_people_path, notice: "Person was successfully deleted", status: :see_other
  end

  # GET /people?q=searchterm
  def search
    q = params[:q].to_s.strip
    @people = if q.present?
      Current.production_company.people.where("name LIKE :q OR email LIKE :q", q: "%#{q}%")
    else
      Person.none
    end
    result_partial = params[:result_partial].presence || "people/person_grid_item"
    result_locals = params[:result_locals] || {}

    render partial: "shared/people_search_results", locals: { people: @people, result_partial: result_partial, result_locals: result_locals }
  end

  def add_to_cast
    @cast = Cast.find(params[:cast_id])
    @person = Current.production_company.people.find(params[:person_id])
    @cast.people << @person if !@cast.people.include?(@person)
    render partial: "manage/casts/cast_membership_card", locals: { person: @person, production: @cast.production }
  end

  def remove_from_cast
    @cast = Cast.find(params[:cast_id])
    @person = Current.production_company.people.find(params[:person_id])
    @cast.people.delete(@person) if @cast.people.include?(@person)
    render partial: "manage/casts/cast_membership_card", locals: { person: @person, production: @cast.production }
  end

  def remove_from_production_company
    @person = Current.production_company.people.find(params[:id])

    # Remove the person from the production company
    Current.production_company.people.delete(@person)

    # If the person has a user account, clean up their roles and permissions
    if @person.user
      # Remove user_role for this production company
      @person.user.user_roles.where(production_company: Current.production_company).destroy_all

      # Remove production_permissions for all productions in this production company
      production_ids = Current.production_company.productions.pluck(:id)
      @person.user.production_permissions.where(production_id: production_ids).destroy_all
    end

    redirect_to manage_people_path, notice: "#{@person.name} was removed from #{Current.production_company.name}", status: :see_other
  end


  private
    # Use callbacks to share common setup or constraints between actions.
    def set_person
      @person = Current.production_company.people.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def person_params
      params.require(:person).permit(
        :name, :email, :pronouns, :resume, :headshot,
        socials_attributes: [ :id, :platform, :handle, :_destroy ]
      )
    end
end
