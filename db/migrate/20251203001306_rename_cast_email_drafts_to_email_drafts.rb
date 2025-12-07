# frozen_string_literal: true

class RenameCastEmailDraftsToEmailDrafts < ActiveRecord::Migration[8.1]
  def change
    rename_table :cast_email_drafts, :email_drafts

    # Make show_id optional since this will be used in other contexts
    change_column_null :email_drafts, :show_id, true

    # Add a polymorphic association for flexibility
    add_reference :email_drafts, :emailable, polymorphic: true, index: true
  end
end
