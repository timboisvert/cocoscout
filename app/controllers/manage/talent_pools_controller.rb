# frozen_string_literal: true

module Manage
  class TalentPoolsController < Manage::ManageController
    before_action :set_production, except: [ :org_index, :org_switch_to_single_confirm, :org_switch_to_single, :org_switch_to_per_production_confirm, :org_switch_to_per_production ]
    before_action :check_production_access, except: [ :org_index, :org_switch_to_single_confirm, :org_switch_to_single, :org_switch_to_per_production_confirm, :org_switch_to_per_production ]
    before_action :set_talent_pool, except: [ :org_index, :org_switch_to_single_confirm, :org_switch_to_single, :org_switch_to_per_production_confirm, :org_switch_to_per_production ]
    before_action :ensure_user_is_manager, except: %i[org_index show]
    before_action :ensure_organization, only: [ :org_index, :org_switch_to_single_confirm, :org_switch_to_single, :org_switch_to_per_production_confirm, :org_switch_to_per_production ]

    # GET /casting/talent-pools (org-wide)
    def org_index
      @organization = Current.organization
      @is_single_mode = @organization.talent_pool_single?

      if @is_single_mode
        # Single mode: show the one org-level talent pool
        @org_talent_pool = @organization.organization_talent_pool
        @memberships = @org_talent_pool&.talent_pool_memberships
                                        &.includes(member: { headshot_attachment: :blob }) || []
      else
        # Per-production mode: show grouped talent pools
        load_per_production_pools
      end

      # For the switch modal previews
      @productions = @organization.productions.type_in_house.order(:name)
    end

    # Show confirmation modal for switching to single mode
    def org_switch_to_single_confirm
      @organization = Current.organization
      @productions = @organization.productions.type_in_house.order(:name)
      @all_members = @organization.all_talent_pool_members

      render :org_switch_to_single_confirm
    end

    # Execute switch to single talent pool mode
    def org_switch_to_single
      @organization = Current.organization
      strategy = params[:strategy] # 'merge_all', 'from_production', 'fresh'
      source_production_id = params[:source_production_id]

      ActiveRecord::Base.transaction do
        # Create or get the org-level talent pool
        org_pool = @organization.find_or_create_talent_pool!

        case strategy
        when "merge_all"
          # Merge all members from all production pools
          @organization.productions.type_in_house.each do |prod|
            prod.talent_pool.people.each do |person|
              org_pool.people << person unless org_pool.people.exists?(person.id)
            end
            prod.talent_pool.groups.each do |group|
              org_pool.groups << group unless org_pool.groups.exists?(group.id)
            end
          end

        when "from_production"
          # Copy members from one production's pool
          source_prod = @organization.productions.find(source_production_id)
          source_prod.talent_pool.people.each do |person|
            org_pool.people << person unless org_pool.people.exists?(person.id)
          end
          source_prod.talent_pool.groups.each do |group|
            org_pool.groups << group unless org_pool.groups.exists?(group.id)
          end

        when "fresh"
          # Start with empty pool - nothing to do
        end

        # Switch the mode
        @organization.update!(talent_pool_mode: :single)
      end

      redirect_to manage_casting_talent_pools_path, notice: "Switched to single talent pool mode."
    end

    # Show confirmation modal for switching to per-production mode
    def org_switch_to_per_production_confirm
      @organization = Current.organization
      @productions = @organization.productions.type_in_house.order(:name)
      @org_pool = @organization.organization_talent_pool

      # Calculate what each production's pool currently has
      @production_pool_stats = @productions.map do |prod|
        pool = prod.talent_pool
        {
          production: prod,
          people_count: pool.people.count,
          groups_count: pool.groups.count
        }
      end

      render :org_switch_to_per_production_confirm
    end

    # Execute switch to per-production mode
    def org_switch_to_per_production
      @organization = Current.organization
      strategy = params[:strategy] # 'restore', 'copy_all', 'copy_to_one'
      target_production_id = params[:target_production_id]

      ActiveRecord::Base.transaction do
        org_pool = @organization.organization_talent_pool

        case strategy
        when "restore"
          # Just switch mode - each production keeps its existing pool
          # Members in org pool become orphaned (harmless)

        when "copy_all"
          # Copy org pool members to all production pools
          if org_pool
            @organization.productions.type_in_house.each do |prod|
              pool = prod.talent_pool
              org_pool.people.each do |person|
                pool.people << person unless pool.people.exists?(person.id)
              end
              org_pool.groups.each do |group|
                pool.groups << group unless pool.groups.exists?(group.id)
              end
            end
          end

        when "copy_to_one"
          # Copy org pool to one production, leave others as-is
          if org_pool && target_production_id.present?
            target_prod = @organization.productions.find(target_production_id)
            pool = target_prod.talent_pool
            org_pool.people.each do |person|
              pool.people << person unless pool.people.exists?(person.id)
            end
            org_pool.groups.each do |group|
              pool.groups << group unless pool.groups.exists?(group.id)
            end
          end
        end

        # Switch the mode
        @organization.update!(talent_pool_mode: :per_production)
      end

      redirect_to manage_casting_talent_pools_path, notice: "Switched to per-production talent pools."
    end

    # Each production has exactly one talent pool
    # This controller manages membership in that pool (no index view - managed via casting settings tab)

    def show
      # Full page view for direct navigation to a production's talent pool
      # If XHR request, just return the members partial for refresh
      if request.xhr?
        render partial: "manage/casting_settings/talent_pool_members", locals: { talent_pool: @talent_pool }
      end
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

    # Add a person from CocoScout who's not in our org yet
    def add_global_person
      person = Person.find(params[:person_id])

      # Add person to organization if not already
      unless person.organizations.include?(Current.organization)
        person.organizations << Current.organization
      end

      # Add to talent pool
      @talent_pool.people << person unless @talent_pool.people.exists?(person.id)

      if request.xhr?
        render json: { success: true, message: "#{person.name} added to organization and talent pool" }
      else
        redirect_to manage_casting_talent_pool_path(@production),
                    notice: "#{person.name} added to organization and talent pool"
      end
    end

    # Invite a new person (not on CocoScout) directly to the talent pool
    def invite_to_pool
      email = params[:email]&.strip&.downcase
      name = params[:name]&.strip

      if email.blank? || name.blank?
        render json: { success: false, error: "Name and email are required" }, status: :unprocessable_entity
        return
      end

      # Check if person with this email already exists
      existing_person = Person.find_by(email: email)

      if existing_person
        # Person exists - add them to org and pool
        unless existing_person.organizations.include?(Current.organization)
          existing_person.organizations << Current.organization
        end
        @talent_pool.people << existing_person unless @talent_pool.people.exists?(existing_person.id)

        render json: { success: true, message: "#{existing_person.name} added to talent pool" }
      else
        # Create new person and send invitation
        person = Person.create!(name: name, email: email)
        person.organizations << Current.organization

        # Create user account
        user = User.create!(
          email_address: email,
          password: User.generate_secure_password
        )
        person.update!(user: user)

        # Create invitation linked to talent pool
        invitation = PersonInvitation.create!(
          email: email,
          organization: Current.organization,
          talent_pool: @talent_pool
        )

        # Send invitation email using the standard invitation template
        invitation_subject = EmailTemplateService.render_subject("person_invitation", {
          organization_name: Current.organization.name
        })
        invitation_message = EmailTemplateService.render_body("person_invitation", {
          organization_name: Current.organization.name,
          setup_url: "[setup link will be included]"
        })

        Manage::PersonMailer.person_invitation(invitation, invitation_subject, invitation_message).deliver_later

        render json: {
          success: true,
          message: "Invitation sent to #{name}. They'll be added to the talent pool when they accept.",
          pending: true
        }
      end
    end

    def revoke_invitation
      invitation = @talent_pool.person_invitations.pending.find(params[:invitation_id])
      email = invitation.email

      invitation.destroy!

      if request.xhr?
        render json: { success: true, message: "Invitation to #{email} revoked" }
      else
        redirect_to manage_casting_talent_pool_path(@production),
                    notice: "Invitation to #{email} revoked"
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
        render json: { success: true, message: "#{person.name} removed from talent pool" }
      else
        redirect_to manage_casting_talent_pool_path(@production),
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
        render json: { success: true, message: "#{group.name} removed from talent pool" }
      else
        redirect_to manage_casting_talent_pool_path(@production),
                    notice: "#{group.name} removed from talent pool"
      end
    end

    def search_people
      q = (params[:q] || params[:query]).to_s.strip

      if q.blank? || q.length < 2
        render partial: "manage/talent_pools/search_results_enhanced",
               locals: {
                 org_members: [],
                 global_people: [],
                 query: q,
                 talent_pool_id: @talent_pool.id,
                 show_invite: false
               }
        return
      end

      # Search within organization (people and groups)
      org_people = Current.organization.people.where(
        "LOWER(name) LIKE LOWER(:q) OR LOWER(email) LIKE LOWER(:q) OR LOWER(public_key) LIKE LOWER(:q)",
        q: "%#{q}%"
      )
      org_groups = Current.organization.groups.where("LOWER(name) LIKE LOWER(:q)", q: "%#{q}%")

      # Exclude people and groups already in the talent pool
      org_people = org_people.where.not(id: @talent_pool.people.pluck(:id))
      org_groups = org_groups.where.not(id: @talent_pool.groups.pluck(:id))

      org_members = (org_people.to_a + org_groups.to_a).sort_by { |m| m.name.downcase }

      # Search globally in CocoScout (people not in this org)
      org_person_ids = Current.organization.people.pluck(:id)
      global_people = Person.where(
        "LOWER(name) LIKE LOWER(:q) OR LOWER(email) LIKE LOWER(:q) OR LOWER(public_key) LIKE LOWER(:q)",
        q: "%#{q}%"
      ).where.not(id: org_person_ids).limit(10).to_a

      # Determine if we should show invite option
      # Show invite if query looks like an email and we didn't find exact matches
      show_invite = q.include?("@") && org_members.none? { |m| m.try(:email)&.downcase == q.downcase } &&
                   global_people.none? { |p| p.email&.downcase == q.downcase }

      render partial: "manage/talent_pools/search_results_enhanced",
             locals: {
               org_members: org_members,
               global_people: global_people,
               query: q,
               talent_pool_id: @talent_pool.id,
               show_invite: show_invite
             }
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
            show_name: a.show.display_name,
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

      redirect_to manage_casting_talent_pools_path,
                  notice: "You are now using a separate talent pool for this production."
    end

    private

    def ensure_organization
      redirect_to select_organization_path, alert: "Please select an organization first." unless Current.organization
    end

    def load_per_production_pools
      productions = Current.organization.productions.type_in_house
                           .includes(:talent_pools)
                           .order(:name)

      pools_seen = Set.new
      @talent_pool_groups = []

      productions.each do |production|
        pool = production.effective_talent_pool
        next if pool.nil? || pools_seen.include?(pool.id)

        pools_seen.add(pool.id)

        pool_productions = pool.all_productions.includes(:talent_pools).order(:name).to_a
        memberships = pool.talent_pool_memberships
                          .includes(member: { headshot_attachment: :blob })

        @talent_pool_groups << {
          pool: pool,
          productions: pool_productions,
          memberships: memberships
        }
      end
    end

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
      redirect_to manage_casting_talent_pools_path, status: :see_other
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
