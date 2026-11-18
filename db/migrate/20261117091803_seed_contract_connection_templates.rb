# frozen_string_literal: true

# The words of the notifications about connecting a contract to the
# contractor's own organization (ContractConnectionTemplates), and the one
# added to date requests on 2026-11-17 (a request that no longer applies),
# seeded so they exist wherever the tables do.
class SeedContractConnectionTemplates < ActiveRecord::Migration[8.1]
  def up
    ContractConnectionTemplates.ensure!
    ContractDateRequestTemplates.ensure!
  end

  def down
    ContentTemplate.where(key: ContractConnectionTemplates::TEMPLATES.map { |spec| spec[:key] }).delete_all
  end
end
