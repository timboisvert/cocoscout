# frozen_string_literal: true

# Each share now carries a read/write permission. Also drop the "cast" audience
# (we keep team / talent_pool / person) — fold any existing cast shares into team.
class AddPermissionToDocumentShares < ActiveRecord::Migration[8.1]
  def up
    add_column :document_shares, :permission, :integer, default: 0, null: false # 0 = read, 1 = write

    # Existing shares were created without a permission concept; team/cast were
    # effectively "can see + (team) manage", so make them write; pools/people read.
    execute "UPDATE document_shares SET permission = 1 WHERE audience_type IN ('team', 'cast')"
    execute "UPDATE document_shares SET audience_type = 'team' WHERE audience_type = 'cast'"

    # De-dupe any docs that now have two team rows.
    execute <<~SQL.squish
      DELETE FROM document_shares a USING document_shares b
      WHERE a.audience_type = 'team' AND b.audience_type = 'team'
        AND a.production_document_id = b.production_document_id
        AND a.id > b.id
    SQL
  end

  def down
    remove_column :document_shares, :permission
  end
end
