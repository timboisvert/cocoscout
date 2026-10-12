# frozen_string_literal: true

# Delete my account, asked for from Account Settings (Apple requires the app
# to offer it). Superadmins finish it within 30 days; the person can take it
# back until then. Seeds the superadmins' email about it.
class AddDeletionRequestedAtToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :deletion_requested_at, :datetime
    PlatformTemplates.ensure!(keys: %w[account_deletion_requested])
  end

  def down
    ContentTemplate.where(key: "account_deletion_requested").destroy_all
    remove_column :users, :deletion_requested_at
  end
end
