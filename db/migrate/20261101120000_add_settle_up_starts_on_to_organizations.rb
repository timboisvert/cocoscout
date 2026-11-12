# frozen_string_literal: true

# Settle up's start date (Tim, 2026-11-01): days before it are history. An
# organization made after 1.3 has no start date: it has no history to hide.
#
# This only adds the column. Setting every existing organization's start
# (SettleUpStart.convert_all!) happens in a later migration,
# SettleUpStartsForExistingOrganizations, because that code reads tables
# (tip rules, registers) that migrations after this one create: run here, it
# stopped the rehearsal on a fresh production copy (2026-11-11).
class AddSettleUpStartsOnToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :settle_up_starts_on, :date
  end
end
