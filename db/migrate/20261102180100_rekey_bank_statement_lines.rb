# frozen_string_literal: true

# Description keys built again with the better key (a payee's name with
# digits in it keeps its letters; DESC and DATE are noise). Production has
# no statement lines yet; the dev copy has a few thousand.
class RekeyBankStatementLines < ActiveRecord::Migration[8.1]
  def up
    BankStatementLine.find_each do |line|
      key = BankStatementLine.description_key_for(line.description)
      line.update_column(:description_key, key) if key != line.description_key
    end
  end

  def down; end
end
