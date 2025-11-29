class AddMissingVisibilityColumnsToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :headshots_visible, :boolean, default: true, null: false
    add_column :people, :resumes_visible, :boolean, default: true, null: false
    add_column :people, :social_media_visible, :boolean, default: true, null: false
    add_column :people, :videos_visible, :boolean, default: true, null: false
    add_column :people, :performance_credits_visible, :boolean, default: true, null: false
    add_column :people, :training_credits_visible, :boolean, default: true, null: false
    add_column :people, :profile_skills_visible, :boolean, default: true, null: false
  end
end
