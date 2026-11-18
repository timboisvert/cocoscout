# frozen_string_literal: true

# The email telling everyone CocoScout has an app takes Andie and Tim's own
# words, with the App Store and Google Play badges as its download buttons
# (Tim, 2026-11-13). Nobody has been sent it yet.
class AppAnnouncementNewWords < ActiveRecord::Migration[8.1]
  def up
    PlatformTemplates.ensure!(keys: %w[get_the_app_announcement], overwrite: true)
  end

  def down; end
end
