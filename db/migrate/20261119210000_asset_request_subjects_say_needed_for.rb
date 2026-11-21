# frozen_string_literal: true

# Requests saved before the default subject changed keep the new words too
# (Tim, 2026-11-19: "Images and details needed for ..."). Only a subject that
# is still exactly the old default is touched; one a manager wrote stays.
class AssetRequestSubjectsSayNeededFor < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE asset_requests
      SET subject = 'Images and details needed for ' || productions.name
      FROM productions
      WHERE productions.id = asset_requests.production_id
        AND asset_requests.subject = 'Images and details we need for ' || productions.name
    SQL
  end

  def down; end
end
