# frozen_string_literal: true

# Followers through the contract (Tim, 2026-11-17). A mailing list can be
# for a contractor: it collects at checkout from every production that
# contractor has under a live contract, and is shared with everyone on
# those contracts. A list that an organization receives that way, on Pro,
# is its own list of its own followers, remembering the list it came from.
class MailingListsCanBeForAContractor < ActiveRecord::Migration[8.1]
  def change
    add_reference :mailing_lists, :contractor, foreign_key: { on_delete: :nullify }
    add_column :mailing_lists, :shared_with_contractor, :boolean, null: false, default: true
    add_reference :mailing_lists, :source_list, foreign_key: { to_table: :mailing_lists, on_delete: :nullify }
  end
end
