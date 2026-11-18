# frozen_string_literal: true

# The one email telling everyone CocoScout has an app (AppAnnouncement):
# when each person was sent it, so nobody is sent it twice; and its words.
class AddAppAnnouncedAtToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :app_announced_at, :datetime
    PlatformTemplates.ensure!(keys: %w[get_the_app_announcement])
  end

  def down
    remove_column :users, :app_announced_at
    ContentTemplate.where(key: "get_the_app_announcement").delete_all
  end
end
