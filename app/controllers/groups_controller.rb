class GroupsController < ApplicationController
  layout "profile", except: [ :new ]

  before_action :set_group, only: [ :edit, :update, :archive, :unarchive, :set_primary_headshot, :check_url_availability, :update_url ]
  before_action :check_group_access, only: [ :edit, :update, :check_url_availability, :update_url ]
  before_action :check_owner_access, only: [ :archive, :unarchive ]

  skip_before_action :track_my_dashboard
  skip_before_action :show_my_sidebar

  def index
    @groups = Current.user.person.groups.where(archived_at: nil).order(:name)
  end

  def new
    @group = Group.new
  end

  def create
    @group = Group.new(group_params)

    if @group.save
      membership = @group.group_memberships.create!(
        person: Current.user.person,
        permission_level: :owner
      )
      membership.enable_notifications!

      redirect_to edit_group_path(@group), notice: "Group created successfully!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @show_group_sidebar = true
    @membership = @group.group_memberships.find_by(person: Current.user.person)
    @entity = @group  # For profile partials compatibility
  end

  def update
    if @group.update(group_params)
      respond_to do |format|
        format.turbo_stream do
          # Reload associations to ensure newly saved items are included
          @group.reload

          # Only reload sections that were actually updated
          streams = []

          if group_params[:profile_headshots_attributes].present?
            streams << turbo_stream.replace("headshots", partial: "shared/profiles/headshots", locals: { entity: @group })
          end

          if group_params[:profile_resumes_attributes].present?
            streams << turbo_stream.replace("resumes", partial: "shared/profiles/resumes", locals: { entity: @group })
          end

          if group_params[:profile_videos_attributes].present?
            streams << turbo_stream.replace("videos", partial: "shared/profiles/videos", locals: { entity: @group })
          end

          if group_params[:performance_sections_attributes].present?
            streams << turbo_stream.replace("performance-history", partial: "shared/profiles/performance_credits", locals: { entity: @group })
          end

          if group_params[:socials_attributes].present?
            streams << turbo_stream.replace("social-media", partial: "shared/profiles/social_media", locals: { entity: @group })
          end

          # Always show success message using standard notice
          streams << turbo_stream.update(
            "notice-container",
            partial: "shared/notice",
            locals: { notice: "Group updated" }
          )

          render turbo_stream: streams
        end
        format.html { redirect_to edit_group_path(@group), notice: "Group updated successfully." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          error_message = @group.errors.full_messages.join(", ")
          render turbo_stream: turbo_stream.update(
            "notice-container",
            partial: "shared/notice",
            locals: { notice: error_message }
          )
        end
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def archive
    if @group.update(archived_at: Time.current)
      redirect_to groups_path, notice: "Group archived successfully."
    else
      redirect_to edit_group_path(@group), alert: "Could not archive group."
    end
  end

  def unarchive
    if @group.update(archived_at: nil)
      redirect_to edit_group_path(@group), notice: "Group unarchived successfully."
    else
      redirect_to edit_group_path(@group), alert: "Could not unarchive group."
    end
  end

  def set_primary_headshot
    headshot = @group.profile_headshots.find(params[:id])
    headshot.update(is_primary: true)

    @group.reload

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "headshots",
          partial: "shared/profiles/headshots",
          locals: { entity: @group }
        )
      end
      format.json { head :ok }
    end
  end

  def check_url_availability
    proposed_key = params[:public_key]&.strip&.downcase

    # Check cooldown period first
    settings = YAML.load_file(Rails.root.join("config", "profile_settings.yml"))
    cooldown_days = settings["url_change_cooldown_days"]

    if @group.public_key_changed_at && @group.public_key_changed_at > cooldown_days.days.ago
      render json: {
        available: false,
        message: "You changed your public URL too recently."
      }, status: :unprocessable_entity
      return
    end

    # Validate format
    unless proposed_key =~ /\A[a-z0-9][a-z0-9\-]{2,29}\z/
      render json: {
        available: false,
        message: "URL must be 3-30 characters: lowercase letters, numbers, and hyphens only"
      }, status: :unprocessable_entity
      return
    end

    # Check if it's the same as current
    if proposed_key == @group.public_key
      render json: {
        available: false,
        message: "This is already your current URL"
      }, status: :unprocessable_entity
      return
    end

    # Check if reserved
    reserved = YAML.safe_load_file(
      Rails.root.join("config", "reserved_public_keys.yml"),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: true
    )
    if reserved.include?(proposed_key)
      render json: {
        available: false,
        message: "This URL is reserved for CocoScout system pages"
      }, status: :unprocessable_entity
      return
    end

    # Check if taken by another person or group
    if Person.where(public_key: proposed_key).exists? ||
       Group.where(public_key: proposed_key).where.not(id: @group.id).exists?
      render json: {
        available: false,
        message: "This URL is already taken"
      }, status: :unprocessable_entity
      return
    end

    # Available!
    render json: {
      available: true,
      message: "This URL is available!"
    }
  end

  def update_url
    new_key = params[:group][:public_key]&.strip&.downcase

    # Check cooldown period from config
    settings = YAML.load_file(Rails.root.join("config", "profile_settings.yml"))
    cooldown_days = settings["url_change_cooldown_days"]

    if @group.public_key_changed_at && @group.public_key_changed_at > cooldown_days.days.ago
      redirect_to edit_group_path(@group), notice: "You changed your public URL too recently."
      return
    end

    if @group.update(public_key: new_key)
      redirect_to edit_group_path(@group), notice: "Your group profile URL has been updated successfully."
    else
      redirect_to edit_group_path(@group), notice: @group.errors.full_messages.join(", ")
    end
  end

  private

  def set_group
    @group = Current.user.person.groups.find(params[:group_id] || params[:id])
  end

  def check_group_access
    membership = @group.group_memberships.find_by(person: Current.user.person)
    unless membership && (membership.owner? || membership.write?)
      redirect_to groups_path, alert: "You don't have permission to edit this group."
    end
  end

  def check_owner_access
    membership = @group.group_memberships.find_by(person: Current.user.person)
    unless membership && membership.owner?
      redirect_to groups_path, alert: "Only group owners can archive or unarchive groups."
    end
  end

  def group_params
    params.require(:group).permit(
      :name, :bio, :email, :phone, :public_key, :headshot, :resume,
      :hide_contact_info, :headshots_visible, :resumes_visible, :social_media_visible,
      socials_attributes: [ :id, :platform, :handle, :_destroy ],
      profile_headshots_attributes: [ :id, :image, :category, :is_primary, :position, :_destroy ],
      profile_videos_attributes: [ :id, :title, :url, :position, :_destroy ],
      performance_sections_attributes: [
        :id, :name, :position, :_destroy,
        performance_credits_attributes: [
          :id, :section_name, :title, :location, :role,
          :year_start, :year_end, :notes, :link_url, :position, :_destroy
        ]
      ],
      profile_resumes_attributes: [ :id, :name, :position, :file, :_destroy ]
    )
  end
end
