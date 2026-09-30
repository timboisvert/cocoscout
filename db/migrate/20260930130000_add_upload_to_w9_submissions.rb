# frozen_string_literal: true

# A W-9 a manager already has (signed on paper, or through another system) can
# be uploaded instead of filled in online: the file, plus the fields a 1099
# needs, typed in by the manager. It has no online signature, so
# signature_name is only required for online W-9s (enforced in the model).
class AddUploadToW9Submissions < ActiveRecord::Migration[8.1]
  def change
    add_column :w9_submissions, :source, :string, null: false, default: "online"
    add_reference :w9_submissions, :uploaded_by, foreign_key: { to_table: :users }, null: true
    change_column_null :w9_submissions, :signature_name, true
  end
end
