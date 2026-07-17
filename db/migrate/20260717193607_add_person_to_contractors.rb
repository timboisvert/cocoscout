# frozen_string_literal: true

# A Contractor is now a Person-backed container: it wraps a Person (the identity
# that logs in and gets paid) and holds that party's contracts. Backfill existing
# contractors by creating/linking a Person from their name + email.
class AddPersonToContractors < ActiveRecord::Migration[8.1]
  def up
    add_reference :contractors, :person, foreign_key: true, index: true, null: true
    Contractor.reset_column_information
    Contractor.find_each(&:ensure_person!)
  end

  def down
    remove_reference :contractors, :person, foreign_key: true
  end
end
