class AddOrganizationToEmailLogs < ActiveRecord::Migration[8.1]
  def change
    add_reference :email_logs, :organization, null: true, foreign_key: true

    # Backfill organization_id from the user's person's organization
    reversible do |dir|
      dir.up do
        # Get organization from the user who sent the email
        # Person has user_id (not the other way around), so join through people table
        execute <<-SQL
          UPDATE email_logs
          SET organization_id = (
            SELECT op.organization_id
            FROM people
            INNER JOIN organizations_people op ON op.person_id = people.id
            WHERE people.user_id = email_logs.user_id
            LIMIT 1
          )
          WHERE email_logs.user_id IS NOT NULL
            AND email_logs.organization_id IS NULL
        SQL

        # Also try to backfill from recipient_entity for Group recipients
        execute <<-SQL
          UPDATE email_logs
          SET organization_id = (
            SELECT og.organization_id
            FROM organizations_groups og
            WHERE og.group_id = email_logs.recipient_entity_id
            LIMIT 1
          )
          WHERE email_logs.recipient_entity_type = 'Group'
            AND email_logs.recipient_entity_id IS NOT NULL
            AND email_logs.organization_id IS NULL
        SQL

        # Also try to backfill from recipient_entity for Person recipients
        execute <<-SQL
          UPDATE email_logs
          SET organization_id = (
            SELECT op.organization_id
            FROM organizations_people op
            WHERE op.person_id = email_logs.recipient_entity_id
            LIMIT 1
          )
          WHERE email_logs.recipient_entity_type = 'Person'
            AND email_logs.recipient_entity_id IS NOT NULL
            AND email_logs.organization_id IS NULL
        SQL
      end
    end
  end
end
