# frozen_string_literal: true

# One link per production to the folder where it keeps its files on Google
# Drive, Dropbox, or OneDrive, shown next to its documents (Tim, 2026-11-19).
class ProductionsLinkASharedFolder < ActiveRecord::Migration[8.1]
  def change
    add_column :productions, :documents_link_url, :string
    add_column :productions, :documents_link_name, :string
  end
end
