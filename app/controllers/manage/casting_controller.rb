class Manage::CastingController < Manage::ManageController
  before_action :set_production
  before_action :check_production_access
  before_action :set_show, only: [ :show_cast, :contact_cast, :send_cast_email, :assign_person_to_role, :remove_person_from_role ]

  def index
    @upcoming_shows = @production.shows
      .where("date_and_time >= ?", Time.current)
      .where(casting_enabled: true)
      .includes(show_person_role_assignments: [ :person, :role ])
      .order(:date_and_time)
      .limit(10)
  end

  def show_cast
    @availability = build_availability_hash(@show)
  end

  def contact_cast
    # Get all people assigned to roles in this show
    @cast_members = @show.show_person_role_assignments
      .includes(:person, :role)
      .map(&:person)
      .uniq
      .sort_by(&:name)
  end

  def send_cast_email
    title = params[:title]
    message = params[:message]

    if title.blank? || message.blank?
      redirect_to manage_production_show_contact_cast_path(@production, @show), alert: "Title and message are required"
      return
    end

    # Get all cast members
    cast_members = @show.show_person_role_assignments
      .includes(:person)
      .map(&:person)
      .uniq

    # Send email to each cast member
    cast_members.each do |person|
      Manage::CastingMailer.cast_email(person, @show, title, message, Current.user).deliver_later
    end

    redirect_to manage_production_show_path(@production, @show), notice: "Email sent to #{cast_members.count} cast #{'member'.pluralize(cast_members.count)}"
  end

  def assign_person_to_role
    # Get the person and the role
    person = Current.organization.people.find(params[:person_id])
    role = Role.find(params[:role_id])

    # If this role already has someone in it for this show, remove the assignment
    existing_assignments = @show.show_person_role_assignments.where(role: role)
    existing_assignments.destroy_all if existing_assignments.any?

    # Make the assignment
    assignment = @show.show_person_role_assignments.find_or_initialize_by(person: person, role: role)
    assignment.save!

    # Generate the HTML to return - pass availability data
    @availability = build_availability_hash(@show)
    cast_members_html = render_to_string(partial: "manage/casting/cast_members_list", locals: { show: @show, availability: @availability })
    roles_html = render_to_string(partial: "manage/casting/roles_list", locals: { show: @show })
    render json: { cast_members_html: cast_members_html, roles_html: roles_html }
  end

  def remove_person_from_role
    # Support both assignment_id and role_id for removal
    removed_person_id = nil

    if params[:assignment_id]
      assignment = @show.show_person_role_assignments.find(params[:assignment_id])
      removed_person_id = assignment&.person_id
      assignment.destroy! if assignment
    elsif params[:role_id]
      # Get the person before removing (there should only be one per role)
      assignment = @show.show_person_role_assignments.where(role_id: params[:role_id]).first
      removed_person_id = assignment&.person_id
      # Remove all assignments for this role
      @show.show_person_role_assignments.where(role_id: params[:role_id]).destroy_all
    end

    # Generate the HTML to return - pass availability data
    @availability = build_availability_hash(@show)
    cast_members_html = render_to_string(partial: "manage/casting/cast_members_list", locals: { show: @show, availability: @availability })
    roles_html = render_to_string(partial: "manage/casting/roles_list", locals: { show: @show })
    render json: { cast_members_html: cast_members_html, roles_html: roles_html, person_id: removed_person_id }
  end

  private
    def set_production
      @production = Current.organization.productions.find(params.require(:production_id))
    end

    def set_show
      @show = @production.shows.find(params[:show_id])
    end

    def build_availability_hash(show)
      availability = {}
      ShowAvailability.where(show_id: show.id, available_entity_type: "Person").each do |show_availability|
        availability["#{show_availability.available_entity_id}"] = show_availability.status.to_s
      end
      availability
    end
end
