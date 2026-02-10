class AddArchivedAtToAuditionRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :audition_requests, :archived_at, :datetime
  end
end
