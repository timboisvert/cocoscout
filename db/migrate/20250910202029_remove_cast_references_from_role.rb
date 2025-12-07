# frozen_string_literal: true

class RemoveCastReferencesFromRole < ActiveRecord::Migration[8.0]
  def change
    remove_reference :roles, :cast, foreign_key: true
  end
end
