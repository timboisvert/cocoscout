# frozen_string_literal: true

# Indexes for the columns the money and staffing pages actually filter on.
#
# The headline is `shows.date_and_time`, which had no index in any form despite
# being filtered nearly everywhere in the app — every "shows in this period"
# query was a sequential scan or a production_id scan plus a filter.
#
# Built CONCURRENTLY so none of this locks a table on a live database. That
# means no DDL transaction, which in turn means a failure part-way leaves the
# earlier indexes in place and, worse, can leave an INVALID index behind for the
# one that died. Each create is therefore preceded by a concurrent DROP of the
# same name, so re-running the migration is safe. Do NOT switch these to
# `if_not_exists: true` — that would silently keep an invalid index and mark the
# migration done.
#
# After deploying, check for anything that failed to build:
#   SELECT c.relname FROM pg_index i
#   JOIN pg_class c ON c.oid = i.indexrelid WHERE NOT i.indisvalid;
class AddHotPathIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEXES = [
    # The spine FinancialSummaryService and MoneyTodoService walk: a
    # production's revenue shows that have already happened.
    [ :shows, %i[production_id event_type canceled date_and_time], "idx_shows_prod_type_canceled_date" ],
    # Org-wide date ranges that don't start from a production — the staffing
    # week grid, calendars, org activity.
    [ :shows, %i[date_and_time], "idx_shows_date_and_time" ],

    # `.active` scoped to an org is the most common query in the app. archived_at
    # is indexed alone, which doesn't help once organization_id leads.
    [ :productions, %i[organization_id archived_at], "idx_productions_org_archived" ],
    [ :organization_staff_members, %i[organization_id archived_at], "idx_org_staff_members_org_archived" ],

    # Timesheets: entries for an org in a date window, and the approval queue.
    [ :staff_time_entries, %i[organization_id started_at], "idx_staff_time_entries_org_started" ],
    # Partial, matching the unpaid/pending/approved scopes exactly — the paid
    # history is the bulk of the table and never appears in those queries.
    [ :staff_time_entries, %i[organization_id approved_at], "idx_staff_time_entries_org_unpaid",
      { where: "payout_batch_id IS NULL AND offline_paid_at IS NULL" } ],

    # Every payouts page asks for one org's runs in a given state.
    [ :payout_batches, %i[organization_id status], "idx_payout_batches_org_status" ],
    [ :payout_batch_items, %i[payout_batch_id status], "idx_payout_batch_items_batch_status" ]
  ].freeze

  def up
    INDEXES.each do |table, columns, name, options|
      remove_index table, name: name, algorithm: :concurrently if index_name_exists?(table, name)
      add_index table, columns, **(options || {}), name: name, algorithm: :concurrently
    end
  end

  def down
    INDEXES.each do |table, _columns, name, _options|
      remove_index table, name: name, algorithm: :concurrently if index_name_exists?(table, name)
    end
  end
end
