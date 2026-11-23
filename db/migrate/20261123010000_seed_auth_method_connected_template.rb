# frozen_string_literal: true

# The email and notification sent when Apple or Google is connected to an
# account (sign-in plan phase 2; Tim, 2026-11-22). Rendering a missing key
# raises, so it is seeded before anything can connect.
class SeedAuthMethodConnectedTemplate < ActiveRecord::Migration[8.1]
  def up
    PlatformTemplates.ensure!(keys: %w[auth_method_connected])
  end

  def down
    ContentTemplate.where(key: "auth_method_connected").destroy_all
  end
end
