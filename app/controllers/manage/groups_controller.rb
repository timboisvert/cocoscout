class Manage::GroupsController < Manage::ManageController
  before_action :set_group, only: [ :show, :edit, :update, :destroy, :add_member, :remove_member, :update_member_role, :archive, :unarchive ]

  def index
    @groups = Current.organization.groups.where(archived_at: nil).order(:name)
  end

  def show
  end

  def new
    @group = Group.new
  end

  def create
    @group = Group.new(group_params)

    if @group.save
      # Add organization association
      @group.organizations << Current.organization unless @group.organizations.include?(Current.organization)

      redirect_to manage_group_path(@group), notice: "Group created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @group.update(group_params)
      redirect_to manage_group_path(@group), notice: "Group updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @group.destroy
    redirect_to manage_groups_path, notice: "Group deleted successfully."
  end

  def search
    query = params[:query].to_s.strip

    if query.present?
      @groups = Current.organization.groups
        .where(archived_at: nil)
        .where("LOWER(name) LIKE ? OR LOWER(email) LIKE ?", "%#{query.downcase}%", "%#{query.downcase}%")
        .order(:name)
        .limit(20)
    else
      @groups = []
    end

    render json: @groups.map { |g| { id: g.id, name: g.name, email: g.email, member_count: g.members.count } }
  end

  def add_member
    person = Person.find(params[:person_id])
    permission_level = params[:role] || "view"  # Keep 'role' param name for API compatibility

    membership = @group.group_memberships.build(
      person: person,
      permission_level: permission_level
    )

    if membership.save
      membership.enable_notifications! if permission_level == "owner"
      # Add organization association if not exists
      @group.organizations << Current.organization unless @group.organizations.include?(Current.organization)

      render json: { success: true, member: { id: person.id, name: person.name } }
    else
      render json: { success: false, errors: membership.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def remove_member
    membership = @group.group_memberships.find_by(person_id: params[:person_id])

    if membership
      # Don't allow removing last owner
      if membership.owner? && @group.group_memberships.where(permission_level: :owner).count == 1
        render json: { success: false, error: "Cannot remove the last owner" }, status: :unprocessable_entity
        return
      end

      membership.destroy
      render json: { success: true }
    else
      render json: { success: false, error: "Member not found" }, status: :not_found
    end
  end

  def update_member_role
    membership = @group.group_memberships.find_by(person_id: params[:person_id])
    new_permission_level = params[:role]  # Keep 'role' param name for API compatibility

    if membership
      # Don't allow demoting last owner
      if membership.owner? && new_permission_level != "owner" && @group.group_memberships.where(permission_level: :owner).count == 1
        render json: { success: false, error: "Cannot change role of the last owner" }, status: :unprocessable_entity
        return
      end

      if membership.update(permission_level: new_permission_level)
        render json: { success: true }
      else
        render json: { success: false, errors: membership.errors.full_messages }, status: :unprocessable_entity
      end
    else
      render json: { success: false, error: "Member not found" }, status: :not_found
    end
  end

  def update_member_notifications
    membership = @group.group_memberships.find_by(person_id: params[:person_id])

    if membership
      # Owners always receive notifications
      if membership.owner?
        render json: { success: false, error: "Owners always receive notifications" }, status: :unprocessable_entity
        return
      end

      enabled = params[:receives_notifications]
      if enabled
        membership.enable_notifications!
      else
        membership.disable_notifications!
      end

      render json: { success: true }
    else
      render json: { success: false, error: "Member not found" }, status: :not_found
    end
  end

  def archive
    if @group.update(archived_at: Time.current)
      redirect_to manage_groups_path, notice: "Group archived successfully."
    else
      redirect_to manage_group_path(@group), alert: "Could not archive group."
    end
  end

  def unarchive
    if @group.update(archived_at: nil)
      redirect_to manage_group_path(@group), notice: "Group unarchived successfully."
    else
      redirect_to manage_group_path(@group), alert: "Could not unarchive group."
    end
  end

  private

  def set_group
    @group = Current.organization.groups.find(params[:id])
  end

  def group_params
    params.require(:group).permit(:name, :bio, :email, :phone, :website, :public_key, :headshot, :resume,
                                   socials_attributes: [ :id, :platform, :url, :_destroy ])
  end
end
