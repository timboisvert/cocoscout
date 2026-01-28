# frozen_string_literal: true

module Manage
  class OrgTalentPoolsController < Manage::ManageController
    before_action :ensure_organization

    def index
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
    def switch_to_single_confirm
      @organization = Current.organization
      @productions = @organization.productions.type_in_house.order(:name)
      @all_members = @organization.all_talent_pool_members

      render :switch_to_single_confirm
    end

    # Execute switch to single talent pool mode
    def switch_to_single
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
    def switch_to_per_production_confirm
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

      render :switch_to_per_production_confirm
    end

    # Execute switch to per-production mode
    def switch_to_per_production
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
  end
end
