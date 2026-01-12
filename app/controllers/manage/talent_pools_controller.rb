# frozen_string_literal: true

module Manage
  class TalentPoolsController < Manage::ManageController
    before_action :set_production
    before_action :check_production_access
    before_action :set_talent_pool
    before_action :ensure_user_is_manager, except: %i[index members]

    # Each production has exactly one talent pool
    # This controller manages membership in that pool

    def index
      # @talent_pool is set by before_action
    end

    def members
      render partial: "manage/casting_settings/talent_pool_members", locals: { talent_pool: @talent_pool }
    end

    def add_person
      person = Current.organization.people.find(params[:person_id])
      @talent_pool.people << person unless @talent_pool.people.exists?(person.id)

      if request.xhr?
        render partial: "manage/casting_settings/talent_pool_members", locals: { talent_pool: @talent_pool }
      else
        render partial: "manage/talent_pools/talent_pool_members_list", locals: { talent_pool: @talent_pool }
      end
    end

    def confirm_remove_person
      @person = Current.organization.people.find(params[:person_id])
      @upcoming_assignments = ShowPersonRoleAssignment.joins(:show)
                                                       .includes(:show, :role)
                                                       .where(shows: { production_id: @production.id })
                                                       .where(assignable_type: "Person", assignable_id: @person.id)
                                                       .where("shows.date_and_time >= ?", Time.current)
                                                       .order("shows.date_and_time ASC")
      @member_type = "person"
      render :confirm_remove_member
    end

    def remove_person
      person = Current.organization.people.find(params[:person_id])

      # Delete upcoming show assignments for this person in this production
      ShowPersonRoleAssignment.joins(:show)
                              .where(shows: { production_id: @production.id })
                              .where(assignable_type: "Person", assignable_id: person.id)
                              .where("shows.date_and_time >= ?", Time.current)
                              .destroy_all

      @talent_pool.people.delete(person)

      if request.xhr?
        render partial: "manage/talent_pools/talent_pool_members_list", locals: { talent_pool: @talent_pool }
      else
        redirect_to manage_production_talent_pools_path(@production),
                    notice: "#{person.name} removed from talent pool"
      end
    end

    def add_group
      group = Current.organization.groups.find(params[:group_id])
      @talent_pool.groups << group unless @talent_pool.groups.exists?(group.id)
      render partial: "manage/talent_pools/talent_pool_members_list", locals: { talent_pool: @talent_pool }
    end

    def confirm_remove_group
      @group = Current.organization.groups.find(params[:group_id])
      @upcoming_assignments = ShowPersonRoleAssignment.joins(:show)
                                                       .includes(:show, :role)
                                                       .where(shows: { production_id: @production.id })
                                                       .where(assignable_type: "Group", assignable_id: @group.id)
                                                       .where("shows.date_and_time >= ?", Time.current)
                                                       .order("shows.date_and_time ASC")
      @member_type = "group"
      render :confirm_remove_member
    end

    def remove_group
      group = Current.organization.groups.find(params[:group_id])

      # Delete upcoming show assignments for this group in this production
      ShowPersonRoleAssignment.joins(:show)
                              .where(shows: { production_id: @production.id })
                              .where(assignable_type: "Group", assignable_id: group.id)
                              .where("shows.date_and_time >= ?", Time.current)
                              .destroy_all

      @talent_pool.groups.delete(group)

      if request.xhr?
        render partial: "manage/talent_pools/talent_pool_members_list", locals: { talent_pool: @talent_pool }
      else
        redirect_to manage_production_talent_pools_path(@production),
                    notice: "#{group.name} removed from talent pool"
      end
    end

    def search_people
      q = (params[:q] || params[:query]).to_s.strip

      if q.present?
        @people = Current.organization.people.where("name LIKE :q OR email LIKE :q", q: "%#{q}%")
        @groups = Current.organization.groups.where("name LIKE :q", q: "%#{q}%")
      else
        @people = Person.none
        @groups = Group.none
      end

      # Exclude people and groups already in the talent pool
      @people = @people.where.not(id: @talent_pool.people.pluck(:id))
      @groups = @groups.where.not(id: @talent_pool.groups.pluck(:id))

      @members = (@people.to_a + @groups.to_a).sort_by(&:name)

      render partial: "manage/talent_pools/search_results",
             locals: { members: @members, talent_pool_id: @talent_pool.id }
    end

    def upcoming_assignments
      member_id = params[:id]
      member_type = params[:member_type] || "Person"

      assignments = ShowPersonRoleAssignment.joins(:show)
                                             .includes(:show, :role)
                                             .where(shows: { production_id: @production.id })
                                             .where(assignable_type: member_type, assignable_id: member_id)
                                             .where("shows.date_and_time >= ?", Time.current)
                                             .order("shows.date_and_time ASC")

      render json: {
        assignments: assignments.map do |a|
          {
            id: a.id,
            show_name: a.show.name_or_formatted_date,
            role_name: a.role&.name,
            date: a.show.date_and_time
          }
        end
      }
    end

    # Update sharing settings - add/remove productions from the shared pool
    def update_shares
      shared_production_ids = (params[:shared_production_ids] || []).reject(&:blank?).map(&:to_i)
      current_shared_ids = @production.talent_pool.shared_productions.pluck(:id)

      # Productions being added to the share
      productions_to_add = shared_production_ids - current_shared_ids
      # Productions being removed from the share
      productions_to_remove = current_shared_ids - shared_production_ids

      # If this is a confirmed submission from the merge modal, just do the update
      if params[:confirmed] == "1"
        merge_production_ids = (params[:merge_production_ids] || []).map(&:to_i)
        perform_share_update(productions_to_add, productions_to_remove, merge_production_ids: merge_production_ids)
        return
      end

      # Check if any productions being added have members that need to be merged
      members_to_merge = []
      productions_to_add.each do |prod_id|
        prod = Current.organization.productions.find(prod_id)
        next if prod.uses_shared_pool? # Skip if already using another pool

        prod_pool = prod.talent_pool
        member_count = prod_pool.cached_member_counts[:total]
        if member_count > 0
          members_to_merge << {
            production: prod,
            people: prod_pool.people.to_a,
            groups: prod_pool.groups.to_a
          }
        end
      end

      # If there are members to merge, show the confirmation modal
      if members_to_merge.any?
        @members_to_merge = members_to_merge
        @shared_production_ids = shared_production_ids
        @productions_to_remove = productions_to_remove
        render :merge_members_confirm
        return
      end

      # No merge needed, just update the shares
      perform_share_update(productions_to_add, productions_to_remove)
    end

    # Confirm leaving the shared pool
    def leave_shared_pool_confirm
      render :leave_shared_pool_confirm
    end

    # Leave the shared pool and use own pool again
    def leave_shared_pool
      TalentPoolShare.find_by(production: @production)&.destroy

      redirect_to manage_production_casting_settings_path(@production, anchor: "talent-pool"),
                  notice: "You are now using a separate talent pool for this production."
    end

    private

    def perform_share_update(productions_to_add, productions_to_remove, merge_all: false, merge_production_ids: [])
      ActiveRecord::Base.transaction do
        # Remove shares
        TalentPoolShare.where(
          talent_pool: @production.talent_pool,
          production_id: productions_to_remove
        ).destroy_all

        # Add shares
        productions_to_add.each do |prod_id|
          prod = Current.organization.productions.find(prod_id)
          next if prod.uses_shared_pool? # Skip if already using another pool

          # Merge members if requested
          if merge_all || merge_production_ids.include?(prod_id)
            prod.talent_pool.people.each do |person|
              @production.talent_pool.people << person unless @production.talent_pool.people.exists?(person.id)
            end
            prod.talent_pool.groups.each do |group|
              @production.talent_pool.groups << group unless @production.talent_pool.groups.exists?(group.id)
            end
          end

          TalentPoolShare.create!(
            talent_pool: @production.talent_pool,
            production: prod
          )
        end
      end

      flash[:notice] = "Sharing settings updated."
      redirect_to manage_production_casting_settings_path(@production, anchor: "talent-pool"), status: :see_other
    end

    def set_production
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
      @production = Current.organization.productions.find(params.require(:production_id))
      sync_current_production(@production)
    end

    def set_talent_pool
      @talent_pool = @production.effective_talent_pool
    end
  end
end
