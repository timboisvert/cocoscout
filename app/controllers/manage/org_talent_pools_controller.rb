# frozen_string_literal: true

module Manage
  class OrgTalentPoolsController < Manage::ManageController
    def index
      # Get all productions with their talent pools
      productions = Current.organization.productions
                           .includes(:talent_pools)
                           .order(:name)

      # Group productions by their effective talent pool to avoid duplicates
      # when talent pools are shared
      pools_seen = Set.new
      @talent_pool_groups = []

      productions.each do |production|
        pool = production.effective_talent_pool
        next if pool.nil? || pools_seen.include?(pool.id)

        pools_seen.add(pool.id)

        # Get all productions that use this pool (owner + shared)
        pool_productions = pool.all_productions.includes(:talent_pools).order(:name).to_a

        # Get all members with eager loading for headshots
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
