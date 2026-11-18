# frozen_string_literal: true

# The words of the notifications about a contractor's request on a contract
# date (ContractDateRequestTemplates), seeded so they exist wherever the
# table does.
class SeedContractDateRequestTemplates < ActiveRecord::Migration[8.1]
  def up
    ContractDateRequestTemplates.ensure!
  end

  def down
    ContentTemplate.where(key: ContractDateRequestTemplates::TEMPLATES.map { |spec| spec[:key] }).delete_all
  end
end
