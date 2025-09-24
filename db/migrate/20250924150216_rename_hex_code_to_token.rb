class RenameHexCodeToToken < ActiveRecord::Migration[8.0]
  def change
    rename_column :call_to_auditions, :hex_code, :token
  end
end
