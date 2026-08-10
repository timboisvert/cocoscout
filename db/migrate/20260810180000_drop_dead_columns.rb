# frozen_string_literal: true

# Eleven columns nothing reads. Production was measured before this: every one
# had zero non-default rows except users.password_reset_token, which held a
# single stale token predating the switch to `generates_token_for`.
#
# The models stopped naming these in an earlier deploy via ignored_columns, so
# by the time this runs no container references them. Those ignored_columns
# declarations can come out once this has shipped.
#
# Deliberately NOT dropped: productions.casting_setup_completed. It has no
# reader either, but four writers including the producer setup flow, and 45 of
# 116 rows set — maintained state, not dead weight.
class DropDeadColumns < ActiveRecord::Migration[8.0]
  def up
    remove_column :users, :password_reset_token
    remove_column :users, :password_reset_sent_at
    remove_column :people, :legal_name
    remove_column :audition_requests, :notified_status
    remove_column :mics, :recurrence_rule
    remove_column :mics, :signup_opens_offset_minutes
    remove_column :city_hubs, :featured_mic_ids
    remove_column :team_invitations, :invitation_notifications_enabled
    remove_column :contracts, :skip_event_creation
    remove_column :agreement_requests, :sent_via
    remove_column :mic_signup_alerts, :last_delivered_at
  end

  # Types, defaults and null constraints are spelled out so db:rollback restores
  # the schema exactly rather than raising IrreversibleMigration. The data in
  # them is not recoverable this way, but there was none worth keeping.
  def down
    add_column :users, :password_reset_token, :string
    add_index  :users, :password_reset_token, unique: true
    add_column :users, :password_reset_sent_at, :datetime
    add_column :people, :legal_name, :string
    add_column :audition_requests, :notified_status, :string
    add_column :mics, :recurrence_rule, :string
    add_column :mics, :signup_opens_offset_minutes, :integer
    add_column :city_hubs, :featured_mic_ids, :jsonb, default: [], null: false
    add_column :team_invitations, :invitation_notifications_enabled, :boolean, default: true
    add_column :contracts, :skip_event_creation, :boolean, default: false, null: false
    add_column :agreement_requests, :sent_via, :string, default: "manual", null: false
    add_column :mic_signup_alerts, :last_delivered_at, :datetime
  end
end
