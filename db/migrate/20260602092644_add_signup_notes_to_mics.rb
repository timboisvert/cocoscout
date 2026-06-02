# frozen_string_literal: true

class AddSignupNotesToMics < ActiveRecord::Migration[8.1]
  def change
    add_column :mics, :signup_notes, :text
  end
end
