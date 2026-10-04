# frozen_string_literal: true

# Who may watch a show's ticket sales without being a manager: a producer or
# performer the theater shares a show (or a whole production) with. Kept
# like door grants: revocations stay, invites wait on a token.
class CreateTicketSalesViewers < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_sales_viewers do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :invited_email
      t.string :invited_name
      t.string :invitation_token
      t.datetime :invited_at
      t.datetime :accepted_at
      # One show (TicketListing) or every date of a production (Production).
      t.references :scope, polymorphic: true, null: false
      t.references :granted_by, foreign_key: { to_table: :users }
      t.datetime :revoked_at
      t.references :revoked_by, foreign_key: { to_table: :users }
      # A morning note on how their shows are selling.
      t.boolean :daily_email, null: false, default: false
      t.timestamps
      t.index :invitation_token, unique: true
      t.index %i[organization_id user_id scope_type scope_id], unique: true, where: "revoked_at IS NULL AND user_id IS NOT NULL",
              name: "idx_ticket_sales_viewers_one_active"
    end
    # A contract's contractor sees their shows' sales unless the theater says not.
    add_column :contracts, :shares_ticket_sales, :boolean, null: false, default: true
    # The theater can stop producers' daily sales emails altogether.
    add_column :ticketing_profiles, :producer_daily_emails, :boolean, null: false, default: true
  end
end
