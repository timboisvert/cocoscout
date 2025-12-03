class Manage::CastingController < Manage::ManageController
  before_action :set_production
  before_action :check_production_access
  before_action :set_show, only: [ :show_cast, :contact_cast, :send_cast_email, :assign_person_to_role, :remove_person_from_role ]

  def index
    @upcoming_shows = @production.shows
      .where("date_and_time >= ?", Time.current)
      .where(casting_enabled: true)
      .includes(:location, show_person_role_assignments: :role)
      .order(:date_and_time)
      .limit(10)

    # Eager load roles for the production (used in cast_card partial)
    @roles = @production.roles.order(:position).to_a
    @roles_count = @roles.size

    # Preload assignables (people and groups) with their headshots
    all_assignments = @upcoming_shows.flat_map(&:show_person_role_assignments)

    person_ids = all_assignments.select { |a| a.assignable_type == "Person" }.map(&:assignable_id).uniq
    group_ids = all_assignments.select { |a| a.assignable_type == "Group" }.map(&:assignable_id).uniq

    @people_by_id = Person
      .where(id: person_ids)
      .includes(profile_headshots: { image_attachment: :blob })
      .index_by(&:id)

    @groups_by_id = Group
      .where(id: group_ids)
      .includes(profile_headshots: { image_attachment: :blob })
      .index_by(&:id)
  end

  def show_cast
    @availability = build_availability_hash(@show)
  end

  def contact_cast
    # Get all entities (people and groups) assigned to roles in this show
    # Note: Can't use .includes(:assignable) on polymorphic associations
    assignments = @show.show_person_role_assignments.includes(:role)

    # Preload people and groups separately
    person_ids = assignments.select { |a| a.assignable_type == "Person" }.map(&:assignable_id)
    group_ids = assignments.select { |a| a.assignable_type == "Group" }.map(&:assignable_id)

    people_by_id = Person.where(id: person_ids).index_by(&:id)
    groups_by_id = Group.includes(:members).where(id: group_ids).index_by(&:id)

    # Store people and groups for display
    @cast_people = []
    @cast_groups = []

    # Collect individual people and groups
    people_for_email = []
    assignments.each do |assignment|
      if assignment.assignable_type == "Person"
        person = people_by_id[assignment.assignable_id]
        if person
          @cast_people << person
          people_for_email << person
        end
      elsif assignment.assignable_type == "Group"
        group = groups_by_id[assignment.assignable_id]
        if group
          @cast_groups << group
          people_for_email.concat(group.members.to_a)
        end
      end
    end

    @cast_people.uniq!
    @cast_groups.uniq!
    @cast_members = people_for_email.uniq.sort_by(&:name)

    # Create a new draft for the form
    @email_draft = EmailDraft.new(emailable: @show)
  end

  def send_cast_email
    @email_draft = EmailDraft.new(email_draft_params.merge(emailable: @show))

    if @email_draft.title.blank? || @email_draft.body.blank?
      redirect_to manage_production_show_contact_cast_path(@production, @show), alert: "Title and message are required"
      return
    end

    # Get all entities (people and groups) assigned to roles in this show
    assignments = @show.show_person_role_assignments

    # Preload people and groups separately
    person_ids = assignments.select { |a| a.assignable_type == "Person" }.map(&:assignable_id).uniq
    group_ids = assignments.select { |a| a.assignable_type == "Group" }.map(&:assignable_id).uniq

    people_by_id = Person.where(id: person_ids).index_by(&:id)
    groups_by_id = Group.includes(group_memberships: :person).where(id: group_ids).index_by(&:id)

    # Count unique cast members (people and groups as entities)
    cast_member_count = person_ids.count + group_ids.count

    # Expand to individual people for email sending (direct assignments + group members with notifications enabled)
    people_to_email = []
    assignments.each do |assignment|
      if assignment.assignable_type == "Person"
        person = people_by_id[assignment.assignable_id]
        people_to_email << person if person
      elsif assignment.assignable_type == "Group"
        group = groups_by_id[assignment.assignable_id]
        if group
          # Add group members who have notifications enabled
          members_with_notifications = group.group_memberships.select(&:notifications_enabled?).map(&:person)
          people_to_email.concat(members_with_notifications)
        end
      end
    end

    people_to_email.uniq!

    # Convert rich text to HTML string for serialization in background jobs
    body_html = @email_draft.body.to_s

    # Send email to each person
    people_to_email.each do |person|
      Manage::CastingMailer.cast_email(person, @show, @email_draft.title, body_html, Current.user).deliver_later
    end

    redirect_to manage_production_show_path(@production, @show), notice: "Email sent to #{cast_member_count} cast #{'member'.pluralize(cast_member_count)}"
  end

  def assign_person_to_role
    # Get the assignable entity (person or group) and the role
    if params[:person_id].present?
      assignable = Current.organization.people.find(params[:person_id])
    elsif params[:group_id].present?
      assignable = Current.organization.groups.find(params[:group_id])
    else
      render json: { error: "Must provide person_id or group_id" }, status: :unprocessable_entity
      return
    end

    role = Role.find(params[:role_id])

    # If this role already has someone in it for this show, remove the assignment
    existing_assignments = @show.show_person_role_assignments.where(role: role)
    existing_assignments.destroy_all if existing_assignments.any?

    # Make the assignment
    assignment = @show.show_person_role_assignments.find_or_initialize_by(assignable: assignable, role: role)
    assignment.save!

    # Generate the HTML to return - pass availability data
    @availability = build_availability_hash(@show)
    cast_members_html = render_to_string(partial: "manage/casting/cast_members_list", locals: { show: @show, availability: @availability })
    roles_html = render_to_string(partial: "manage/casting/roles_list", locals: { show: @show })

    # Calculate progress for the progress bar
    assignment_count = @show.show_person_role_assignments.count
    role_count = @show.production.roles.count
    percentage = role_count > 0 ? (assignment_count.to_f / role_count * 100).round : 0

    render json: {
      cast_members_html: cast_members_html,
      roles_html: roles_html,
      progress: {
        assignment_count: assignment_count,
        role_count: role_count,
        percentage: percentage
      }
    }
  end

  def remove_person_from_role
    # Support both assignment_id and role_id for removal
    removed_assignable_type = nil
    removed_assignable_id = nil

    if params[:assignment_id]
      assignment = @show.show_person_role_assignments.find(params[:assignment_id])
      if assignment
        removed_assignable_type = assignment.assignable_type
        removed_assignable_id = assignment.assignable_id
      end
      assignment.destroy! if assignment
    elsif params[:role_id]
      # Get the assignable before removing (there should only be one per role)
      assignment = @show.show_person_role_assignments.where(role_id: params[:role_id]).first
      if assignment
        removed_assignable_type = assignment.assignable_type
        removed_assignable_id = assignment.assignable_id
      end
      # Remove all assignments for this role
      @show.show_person_role_assignments.where(role_id: params[:role_id]).destroy_all
    end

    # Generate the HTML to return - pass availability data
    @availability = build_availability_hash(@show)
    cast_members_html = render_to_string(partial: "manage/casting/cast_members_list", locals: { show: @show, availability: @availability })
    roles_html = render_to_string(partial: "manage/casting/roles_list", locals: { show: @show })

    # Calculate progress for the progress bar
    assignment_count = @show.show_person_role_assignments.count
    role_count = @show.production.roles.count
    percentage = role_count > 0 ? (assignment_count.to_f / role_count * 100).round : 0

    render json: {
      cast_members_html: cast_members_html,
      roles_html: roles_html,
      assignable_type: removed_assignable_type,
      assignable_id: removed_assignable_id,
      person_id: removed_assignable_id, # Backward compatibility
      progress: {
        assignment_count: assignment_count,
        role_count: role_count,
        percentage: percentage
      }
    }
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
      ShowAvailability.where(show_id: show.id).each do |show_availability|
        key = "#{show_availability.available_entity_type}_#{show_availability.available_entity_id}"
        availability[key] = show_availability
        # Also store by ID for backward compatibility (assumes Person if no type prefix)
        if show_availability.available_entity_type == "Person"
          availability[show_availability.available_entity_id] = show_availability
        end
      end
      availability
    end

    def email_draft_params
      params.require(:email_draft).permit(:title, :body)
    end
end
