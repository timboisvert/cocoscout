# frozen_string_literal: true

# The email and notification sent when a passkey is added (sign-in plan
# phase 4). Rendering a missing key raises, so it's seeded here, after the
# passkeys table (the 1.3 lesson: app code runs after every table it reads).
class SeedPasskeyAddedTemplate < ActiveRecord::Migration[8.1]
  def up
    PlatformTemplates.ensure!(keys: %w[auth_passkey_added])
  end

  def down
    ContentTemplate.where(key: "auth_passkey_added").delete_all
  end
end
