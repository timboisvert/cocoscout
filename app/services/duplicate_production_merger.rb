# frozen_string_literal: true

# Merges duplicate Production records into a single canonical "keeper".
#
# Re-points every child row that references a losing production (any model with
# a production_id column) onto the keeper, de-duplicating rows that would
# otherwise violate a unique index, scrubs the org's included_production_ids
# array and the denormalized contracts.production_name snapshot, then deletes
# the emptied losers — all in one transaction. Safe to re-run: already-moved
# rows simply aren't found again.
#
# Usage (console):
#   DuplicateProductionMerger.call(keeper_id: 152, loser_ids: [166])
#
# It refuses to merge productions from different organizations, and aborts
# (rolling back) if a loser still has references after the move — it never
# cascade-deletes real data.
class DuplicateProductionMerger
  Result = Struct.new(:keeper_id, :merged_loser_ids, :moved, :deduped, :dry_run, keyword_init: true) do
    def to_s
      "#{dry_run ? '[DRY RUN] would merge' : 'merged'} #{merged_loser_ids.inspect} into ##{keeper_id} | " \
        "moved=#{moved.sort.to_h.inspect} deduped=#{deduped.sort.to_h.inspect}"
    end
  end

  # Pass dry_run: true to run the entire merge in a transaction that is rolled
  # back at the end — the returned Result reports exactly what WOULD move/dedupe,
  # while the database is left untouched.
  # Tables where a unique-index collision means the loser's row is genuinely
  # REDUNDANT (a link/permission/config duplicate) and is safe to drop. Any table
  # NOT listed here that collides makes the merge RAISE and roll back rather than
  # risk deleting real content, registrations, or money.
  DEDUPABLE_TABLES = %w[
    production_permissions
    production_notification_settings
    agreement_requests
    agreement_signatures
    audition_wizard_states
    casting_table_productions
    document_productions
    talent_pool_shares
    posters
    payout_scheme_defaults
  ].freeze

  def self.call(keeper_id:, loser_ids:, dry_run: false)
    new(keeper_id: keeper_id, loser_ids: loser_ids).call(dry_run: dry_run)
  end

  def initialize(keeper_id:, loser_ids:)
    @keeper = Production.find(keeper_id)
    @loser_ids = Array(loser_ids).map(&:to_i).uniq - [ @keeper.id ]
    @losers = Production.where(id: @loser_ids).to_a
  end

  def call(dry_run: false)
    Rails.application.eager_load! # ensure every model with a production_id column is loaded

    missing = @loser_ids - @losers.map(&:id)
    raise ArgumentError, "loser productions not found: #{missing.inspect}" if missing.any?

    cross_org = @losers.reject { |l| l.organization_id == @keeper.organization_id }
    raise ArgumentError, "refusing to merge across orgs: #{cross_org.map(&:id).inspect}" if cross_org.any?

    moved = Hash.new(0)
    deduped = Hash.new(0)

    Production.transaction do
      @losers.each do |loser|
        child_models.each { |model| move_model(model, loser, moved, deduped) }
        scrub_user_arrays!(loser)
        assert_detached!(loser)
        loser.destroy!
      end
      raise ActiveRecord::Rollback if dry_run # undo everything; Result still reports the tallies
    end

    Result.new(keeper_id: @keeper.id, merged_loser_ids: @losers.map(&:id), moved: moved, deduped: deduped, dry_run: dry_run)
  end

  private

  # Every model backed by a table with a production_id column (one per table).
  def child_models
    @child_models ||= ApplicationRecord.descendants
                                       .select { |m| m != Production && m.table_exists? && m.column_names.include?("production_id") }
                                       .uniq(&:table_name)
  end

  # Re-point one model's rows from loser to keeper, row by row inside a savepoint
  # so a unique-index collision (a twin already on the keeper) drops the now
  # redundant loser row instead of aborting the whole merge.
  def move_model(model, loser, moved, deduped)
    sets_name = model.column_names.include?("production_name")

    model.where(production_id: loser.id).find_each do |row|
      begin
        model.transaction(requires_new: true) do
          attrs = { production_id: @keeper.id }
          attrs[:production_name] = @keeper.name if sets_name # refresh the denormalized snapshot
          row.update_columns(attrs)
        end
        moved[model.table_name] += 1
      rescue ActiveRecord::RecordNotUnique => e
        unless DEDUPABLE_TABLES.include?(model.table_name)
          raise "unexpected unique collision moving #{model.table_name} ##{row.id} " \
                "(production ##{loser.id} → ##{@keeper.id}) — refusing to delete real data. " \
                "Investigate manually. (#{e.message})"
        end
        row.destroy # a genuinely redundant link/permission row already exists on the keeper
        deduped[model.table_name] += 1
      end
    end
  end

  # users.included_production_ids is a per-user array of production ids. Swap the
  # loser id for the keeper in every user that references it, so no array is left
  # pointing at a deleted production.
  def scrub_user_arrays!(loser)
    return unless User.column_names.include?("included_production_ids")

    User.where("? = ANY(included_production_ids)", loser.id).find_each do |user|
      arr = Array(user.included_production_ids) - [ loser.id ]
      arr << @keeper.id unless arr.include?(@keeper.id)
      user.update_column(:included_production_ids, arr)
    end
  end

  # Safety net: never delete a loser that still owns rows. If anything remains,
  # raise so the transaction rolls back rather than cascade-deleting real data.
  def assert_detached!(loser)
    remaining = child_models.select { |m| m.where(production_id: loser.id).exists? }
    return if remaining.empty?

    raise "loser ##{loser.id} still referenced by #{remaining.map(&:table_name).inspect} — aborting merge"
  end
end
