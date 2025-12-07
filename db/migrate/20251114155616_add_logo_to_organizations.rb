# frozen_string_literal: true

class AddLogoToOrganizations < ActiveRecord::Migration[8.1]
  def change
    # Active Storage attachments are handled through the active_storage_attachments table
    # No need to add columns to organizations table
  end
end
