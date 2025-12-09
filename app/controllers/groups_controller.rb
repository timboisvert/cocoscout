# frozen_string_literal: true

class GroupsController < ApplicationController
  layout "profile", except: %i[new index]

  before_action :set_group,
                only: %i[edit settings update archive unarchive set_primary_headshot check_url_availability update_url
                         update_visibility update_member_role remove_member update_member_notifications]
  before_action :check_group_access,
                only: %i[edit settings update check_url_availability update_url update_visibility]
  before_action :check_owner_access,
                only: %i[archive unarchive update_member_role remove_member update_member_notifications]
  skip_before_action :track_my_dashboard
  skip_before_action :show_my_sidebar

  def index
    @show_my_sidebar = false
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

  def settings
    @show_group_sidebar = true
    @membership = @group.group_memberships.find_by(person: Current.user.person)
    @entity = @group  # For profile partials compatibility
  end

  def update
    # Handle virtual attribute conversion
    @group.show_contact_info = group_params[:show_contact_info] if group_params[:show_contact_info].present?

    if @group.update(group_params.except(:show_contact_info))
      respond_to do |format|
        format.turbo_stream do
          # Reload associations to ensure newly saved items are included
          @group.reload

          # Only reload sections that were actually updated
          streams = []

          if group_params[:profile_headshots_attributes].present?
            streams << turbo_stream.replace("headshots", partial: "shared/profiles/headshots",
                                                         locals: { entity: @group })
          end

          if group_params[:profile_resumes_attributes].present?
            streams << turbo_stream.replace("resumes", partial: "shared/profiles/resumes", locals: { entity: @group })
          end

          if group_params[:profile_videos_attributes].present?
            streams << turbo_stream.replace("videos", partial: "shared/profiles/videos", locals: { entity: @group })
          end

          if group_params[:performance_sections_attributes].present?
            streams << turbo_stream.replace("performance-history", partial: "shared/profiles/performance_credits",
                                                                   locals: { entity: @group })
          end

          if group_params[:socials_attributes].present?
            streams << turbo_stream.replace("social-media", partial: "shared/profiles/social_media",
                                                            locals: { entity: @group })
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
      redirect_to profile_path, notice: "Group archived successfully."
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

  def update_visibility
    field = params[:field]
    value = params[:value] == "1"

    # Whitelist of allowed visibility fields
    allowed_fields = %w[
      bio_visible headshots_visible resumes_visible social_media_visible
      videos_visible performance_credits_visible profile_skills_visible
    ]

    unless allowed_fields.include?(field)
      head :unprocessable_entity
      return
    end

    # Update the specific visibility field
    if @group.update(field => value)
      head :ok
    else
      head :unprocessable_entity
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
    proposed_key = params[:public_key]
    result = PublicKeyService.validate(proposed_key, entity_type: :group, exclude_entity: @group)

    status = result[:available] ? :ok : :unprocessable_entity
    render json: result, status: status
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

  def update_member_role
    membership = @group.group_memberships.find(params[:membership_id])

    if membership.update(permission_level: params[:role])
      render json: { notice: "Member role updated successfully" }
    else
      head :unprocessable_entity
    end
  end

  def remove_member
    membership = @group.group_memberships.find(params[:membership_id])

    # Prevent removing the last owner
    if membership.owner? && @group.group_memberships.where(permission_level: :owner).count == 1
      head :unprocessable_entity
      return
    end

    membership.destroy
    render json: { notice: "Member removed successfully" }
  end

  def update_member_notifications
    membership = @group.group_memberships.find(params[:membership_id])

    if params[:receives_notifications]
      membership.enable_notifications!
    else
      membership.disable_notifications!
    end

    render json: { notice: "Notification settings updated" }
  end

  private

  def set_group
    @group = Group.find(params[:group_id] || params[:id])
    # Check if user is a member of this group
    return if @group.group_memberships.exists?(person: Current.user.person)

    redirect_to root_path, alert: "You don't have access to this group."
  end

  def check_group_access
    membership = @group.group_memberships.find_by(person: Current.user.person)
    return if membership && (membership.owner? || membership.write?)

    redirect_to groups_path, alert: "You don't have permission to edit this group."
  end

  def check_owner_access
    membership = @group.group_memberships.find_by(person: Current.user.person)
    return if membership&.owner?

    redirect_to groups_path, alert: "Only group owners can archive or unarchive groups."
  end

  def group_params
    params.require(:group).permit(
      :name, :bio, :email, :phone, :public_key, :headshot, :resume,
      :hide_contact_info, :show_contact_info, :headshots_visible, :resumes_visible, :social_media_visible,
      :public_profile_enabled,
      socials_attributes: %i[id platform handle name _destroy],
      profile_headshots_attributes: %i[id image category is_primary position _destroy],
      profile_videos_attributes: %i[id title url position _destroy],
      performance_sections_attributes: [
        :id, :name, :position, :_destroy,
        { performance_credits_attributes: %i[
          id section_name title location role
          year_start year_end ongoing notes link_url position _destroy
        ] }
      ],
      profile_resumes_attributes: %i[id name position file _destroy]
    )
  end
end
