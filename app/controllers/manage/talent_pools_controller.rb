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

    private

    def set_production
      @production = Current.organization.productions.find(params.require(:production_id))
    end

    def set_talent_pool
      @talent_pool = @production.talent_pool
    end
  end
end
