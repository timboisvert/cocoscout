# frozen_string_literal: true

# Two things the 1.3 review found that get slower with every entry (Tim,
# 2026-11-09):
#
# 1. An entry's source (the order, the payout, the money record behind it)
#    was only indexed for the one live entry of each kind. Every other
#    question by source (a money record's history, an entry's reversals)
#    read the whole table.
# 2. Each statement brought in sent every line still waiting through the
#    matcher again. matched_at says when an import's matching began, so the
#    next one only looks again at older lines near what the books gained
#    since. Imports already matched are stamped with when they finished.
class IndexEntriesBySourceAndStampBankMatching < ActiveRecord::Migration[8.1]
  def up
    add_index :journal_entries, %i[source_type source_id], name: "index_journal_entries_on_source", if_not_exists: true
    add_column :bank_statement_imports, :matched_at, :datetime, if_not_exists: true
    execute "UPDATE bank_statement_imports SET matched_at = updated_at WHERE status = 'ready' AND matched_at IS NULL"
  end

  def down
    remove_column :bank_statement_imports, :matched_at, if_exists: true
    remove_index :journal_entries, name: "index_journal_entries_on_source", if_exists: true
  end
end
