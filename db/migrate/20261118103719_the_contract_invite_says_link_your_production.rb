# frozen_string_literal: true

# The notice an organization sends a contractor from its contract page read
# "would like you to know you can see these dates in an organization of your
# own". Tim, 2026-11-18: it says "invites you to link your production to
# their contract". The seeded words are replaced, and the notices already
# sent say the same, so one nobody has opened yet reads properly.
# ContentTemplate, notifications and organizations are the tables this reads.
class TheContractInviteSaysLinkYourProduction < ActiveRecord::Migration[8.1]
  def up
    ContractConnectionTemplates.ensure!(keys: %w[contract_connection_told], overwrite: true)
    execute <<~SQL.squish
      UPDATE notifications
         SET title = LEFT(organizations.name || ' invites you to link your production to their contract', 240),
             updated_at = NOW()
        FROM organizations
       WHERE organizations.id = notifications.organization_id
         AND notifications.kind = 'contract_connection_told'
    SQL
  end

  def down; end
end
