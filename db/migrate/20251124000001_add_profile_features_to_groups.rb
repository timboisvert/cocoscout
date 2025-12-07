# frozen_string_literal: true

class AddProfileFeaturesToGroups < ActiveRecord::Migration[8.0]
  def change
    add_column :groups, :headshots_visible, :boolean, default: true, null: false
    add_column :groups, :resumes_visible, :boolean, default: true, null: false
    add_column :groups, :social_media_visible, :boolean, default: true, null: false
  end
end
