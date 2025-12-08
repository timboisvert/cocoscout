# frozen_string_literal: true

module Manage
  class TalentPoolsController < Manage::ManageController
    before_action :set_production
    before_action :check_production_access
    before_action :set_talent_pool, only: %i[edit update destroy]
    before_action :ensure_user_is_manager, except: %i[index]

    def index
      @talent_pools = @production.talent_pools.all
    end

    def new
      @talent_pool = @production.talent_pools.new
    end

    def edit; end

    def create
      @talent_pool = @production.talent_pools.new(talent_pool_params)
      @talent_pool.production = @production

      if @talent_pool.save
        redirect_to manage_production_talent_pools_path(@production), notice: "Talent pool was successfully created"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @talent_pool.update(talent_pool_params)
        redirect_to manage_production_talent_pools_path(@production), notice: "Talent pool was successfully updated",
                                                                      status: :see_other
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @talent_pool.destroy!
      redirect_to manage_production_talent_pools_path(@production), notice: "Talent pool was successfully deleted",
                                                                    status: :see_other
    end

    def add_person
      @talent_pool = @production.talent_pools.find(params[:id])
      person = Current.organization.people.find(params[:person_id])
      @talent_pool.people << person unless @talent_pool.people.exists?(person.id)
      render partial: "manage/talent_pools/talent_pool_members_list", locals: { talent_pool: @talent_pool }
    end

    def confirm_remove_person
      @talent_pool = @production.talent_pools.find(params[:id])
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
      @talent_pool = @production.talent_pools.find(params[:id])
      person = Current.organization.people.find(params[:person_id])

      # Delete upcoming show assignments for this person in this production
      ShowPersonRoleAssignment.joins(:show)
                              .where(shows: { production_id: @production.id })
                              .where(assignable_type: "Person", assignable_id: person.id)
                              .where("shows.date_and_time >= ?", Time.current)
                              .destroy_all

      @talent_pool.people.delete(person)

      # If it's an AJAX request, render the partial; otherwise redirect
      if request.xhr?
        render partial: "manage/talent_pools/talent_pool_members_list", locals: { talent_pool: @talent_pool }
      else
        redirect_to manage_production_talent_pools_path(@production),
                    notice: "#{person.name} removed from #{@talent_pool.name}"
      end
    end

    def add_group
      @talent_pool = @production.talent_pools.find(params[:id])
      group = Current.organization.groups.find(params[:group_id])
      @talent_pool.groups << group unless @talent_pool.groups.exists?(group.id)
      render partial: "manage/talent_pools/talent_pool_members_list", locals: { talent_pool: @talent_pool }
    end

    def confirm_remove_group
      @talent_pool = @production.talent_pools.find(params[:id])
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
      @talent_pool = @production.talent_pools.find(params[:id])
      group = Current.organization.groups.find(params[:group_id])

      # Delete upcoming show assignments for this group in this production
      ShowPersonRoleAssignment.joins(:show)
                              .where(shows: { production_id: @production.id })
                              .where(assignable_type: "Group", assignable_id: group.id)
                              .where("shows.date_and_time >= ?", Time.current)
                              .destroy_all

      @talent_pool.groups.delete(group)

      # If it's an AJAX request, render the partial; otherwise redirect
      if request.xhr?
        render partial: "manage/talent_pools/talent_pool_members_list", locals: { talent_pool: @talent_pool }
      else
        redirect_to manage_production_talent_pools_path(@production),
                    notice: "#{group.name} removed from #{@talent_pool.name}"
      end
    end

    def search_people
      q = params[:q].to_s.strip
      talent_pool_id = params[:talent_pool_id].to_s.strip

      if q.present?
        @people = Current.organization.people.where("name LIKE :q OR email LIKE :q", q: "%#{q}%")
        @groups = Current.organization.groups.where("name LIKE :q", q: "%#{q}%")
      else
        @people = Person.none
        @groups = Group.none
      end

      # Exclude people and groups already in the selected talent pool
      if talent_pool_id.present?
        talent_pool = @production.talent_pools.find(talent_pool_id)
        @people = @people.where.not(id: talent_pool.people.pluck(:id))
        @groups = @groups.where.not(id: talent_pool.groups.pluck(:id))
      end

      @members = (@people.to_a + @groups.to_a).sort_by(&:name)

      render partial: "manage/talent_pools/search_results",
             locals: { members: @members, talent_pool_id: talent_pool_id }
    end

    private

    def set_production
      @production = Current.organization.productions.find(params.require(:production_id))
    end

    def set_talent_pool
      @talent_pool = @production.talent_pools.find(params.require(:id))
    end

    def talent_pool_params
      params.require(:talent_pool).permit(:production_id, :name)
    end
  end
end
