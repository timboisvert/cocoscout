class ChangeEmailGroupToCallToAudition < ActiveRecord::Migration[8.1]
  def change
    remove_reference :email_groups, :production, foreign_key: true, index: true
    add_reference :email_groups, :call_to_audition, foreign_key: true, index: true, null: false
  end
end
