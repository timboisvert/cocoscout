class ConsolidateTalentPoolsToOnePerProduction < ActiveRecord::Migration[8.1]
  def up
    # For each production with multiple talent pools, consolidate into one
    # Keep the first talent pool, move all memberships to it, delete the rest

    # Get all productions with talent pools
    execute <<-SQL
      -- First, for each production, identify the "keeper" pool (first one by id)
      -- and move all memberships from other pools to it

      -- Create temp table of keeper pools (first pool per production)
      CREATE TEMPORARY TABLE keeper_pools AS
      SELECT production_id, MIN(id) as keeper_id
      FROM talent_pools
      GROUP BY production_id;

      -- Update all talent_pool_memberships to point to the keeper pool
      -- Only for memberships that aren't already in the keeper pool
      UPDATE talent_pool_memberships
      SET talent_pool_id = (
        SELECT keeper_id FROM keeper_pools
        WHERE keeper_pools.production_id = (
          SELECT production_id FROM talent_pools WHERE talent_pools.id = talent_pool_memberships.talent_pool_id
        )
      )
      WHERE talent_pool_id NOT IN (SELECT keeper_id FROM keeper_pools);

      -- Remove any duplicate memberships that resulted from the merge
      -- (same member in same pool)
      DELETE FROM talent_pool_memberships
      WHERE id NOT IN (
        SELECT MIN(id)
        FROM talent_pool_memberships
        GROUP BY talent_pool_id, member_type, member_id
      );

      -- Update cast_assignment_stages to point to keeper pools
      UPDATE cast_assignment_stages
      SET talent_pool_id = (
        SELECT keeper_id FROM keeper_pools
        WHERE keeper_pools.production_id = (
          SELECT production_id FROM talent_pools WHERE talent_pools.id = cast_assignment_stages.talent_pool_id
        )
      )
      WHERE talent_pool_id NOT IN (SELECT keeper_id FROM keeper_pools);

      -- Delete non-keeper talent pools
      DELETE FROM talent_pools
      WHERE id NOT IN (SELECT keeper_id FROM keeper_pools);

      -- Clean up temp table
      DROP TABLE keeper_pools;
    SQL

    # Rename all remaining talent pools to "Talent Pool" for consistency
    TalentPool.update_all(name: "Talent Pool")

    # Create talent pools for any productions that don't have one
    Production.left_joins(:talent_pools)
              .where(talent_pools: { id: nil })
              .find_each do |production|
      TalentPool.create!(production: production, name: "Talent Pool")
    end
  end

  def down
    # This migration is not reversible in a meaningful way
    # The data consolidation cannot be undone
    raise ActiveRecord::IrreversibleMigration
  end
end
