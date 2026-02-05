class AddPhoneVerificationToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :phone_verification_code, :string
    add_column :users, :phone_verification_sent_at, :datetime
    add_column :users, :phone_verified_at, :datetime
    add_column :users, :phone_pending_verification, :string
  end
end
