# frozen_string_literal: true

module My
  class GroupsController < ApplicationController
    before_action :set_group, only: %i[edit update archive unarchive]
    before_action :check_group_access, only: %i[edit update]
    before_action :check_owner_access, only: %i[archive unarchive]

    def index
      @groups = Current.user.person.groups.where(archived_at: nil).order(:name)
    end

    def new
      @group = Group.new
    end

    def create
      @group = Group.new(group_params)

      if @group.save
        # Add creator as owner with notifications enabled
        membership = @group.group_memberships.create!(
          person: Current.user.person,
          permission_level: :owner
        )
        membership.enable_notifications!

        redirect_to my_edit_group_path(@group), notice: "Group created successfully!"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @show_group_sidebar = true
      @membership = @group.group_memberships.find_by(person: Current.user.person)
    end

    def update
      if @group.update(group_params)
        redirect_to my_edit_group_path(@group), notice: "Group updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def archive
      if @group.update(archived_at: Time.current)
        redirect_to my_groups_path, notice: "Group archived successfully."
      else
        redirect_to my_edit_group_path(@group), alert: "Could not archive group."
      end
    end

    def unarchive
      if @group.update(archived_at: nil)
        redirect_to my_edit_group_path(@group), notice: "Group unarchived successfully."
      else
        redirect_to my_edit_group_path(@group), alert: "Could not unarchive group."
      end
    end

    private

    def set_group
      @group = Current.user.person.groups.find(params[:id])
    end

    def check_group_access
      membership = @group.group_memberships.find_by(person: Current.user.person)
      return if membership && (membership.owner? || membership.write?)

      redirect_to my_groups_path, alert: "You don't have permission to edit this group."
    end

    def check_owner_access
      membership = @group.group_memberships.find_by(person: Current.user.person)
      return if membership&.owner?

      redirect_to my_groups_path, alert: "Only group owners can archive or unarchive groups."
    end

    def group_params
      params.require(:group).permit(:name, :bio, :email, :phone, :website, :public_key, :public_profile_enabled, :headshot, :resume,
                                    socials_attributes: %i[id platform url _destroy])
    end
  end
end
