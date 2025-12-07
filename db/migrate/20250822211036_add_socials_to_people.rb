# frozen_string_literal: true

class AddSocialsToPeople < ActiveRecord::Migration[8.0]
  def change
    add_column :people, :socials, :string
  end
end
