# frozen_string_literal: true

class AddInvitationTokenToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :invitation_token, :string
    add_column :users, :invitation_sent_at, :datetime
    add_index :users, :invitation_token, unique: true
  end
end
