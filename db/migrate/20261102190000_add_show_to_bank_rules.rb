# frozen_string_literal: true

# A bank rule can record to one of a production's dates as well as the
# production (Tim, 2026-11-02: the rule form takes the production and date
# the way Record money does, each behind a switch).
class AddShowToBankRules < ActiveRecord::Migration[8.1]
  def change
    add_reference :bank_rules, :show, foreign_key: true
  end
end
