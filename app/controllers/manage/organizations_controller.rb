class Manage::OrganizationsController < Manage::ManageController
  before_action :set_organization, only: %i[ edit update destroy ]
  skip_before_action :show_manage_sidebar
  before_action :ensure_user_is_global_manager, except: %i[select set_current]

  def new
    @organization = Organization.new
  end

  def edit
  end

  def create
    @organization = Organization.new(organization_params)

    if @organization.save
      # Assign creator as manager
      UserRole.create!(user: Current.user, organization: @organization, role: "manager")
      session[:current_organization_id] ||= {}
      session[:current_organization_id]["#{Current.user&.id}"] = @organization.id
      redirect_to manage_path, notice: "Organization was successfully created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @organization.update(organization_params)
      redirect_to manage_path, notice: "Organization was successfully updated", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @organization.destroy!
    redirect_to organizations_path, notice: "Organization was successfully deleted", status: :see_other
  end

  def select
    @organizations = Current.user.organizations
    @organization = Organization.new
  end

  def set_current
    organization = Current.user.organizations.find(params[:id])

    # Proceed with setting the new organization
    user_id = Current.user&.id
    if user_id
      session[:current_organization_id] ||= {}
      session[:current_organization_id]["#{user_id}"] = organization.id

      # Clear organization specific session filters/settings
      session.delete(:people_order)
      session.delete(:people_show)
      session.delete(:people_filter)
    end
    redirect_to manage_path
  end


  private
    # Use callbacks to share common setup or constraints between actions.
    def set_organization
      @organization = Organization.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def organization_params
      params.expect(organization: [ :name ])
    end
end
