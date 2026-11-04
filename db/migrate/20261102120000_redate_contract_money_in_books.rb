# frozen_string_literal: true

# Contract money on the books belongs to the date it's for, not the day it
# was paid (ContractMoneyRedate). Data only; nothing to undo by hand.
class RedateContractMoneyInBooks < ActiveRecord::Migration[8.0]
  def up
    moved = ContractMoneyRedate.run!
    say "Re-dated #{moved} contract postings"
  end

  def down; end
end
