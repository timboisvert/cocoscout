# frozen_string_literal: true

class AddProducutionReferencesToRole < ActiveRecord::Migration[8.0]
  def change
    add_reference :roles, :production, null: false, foreign_key: true
  end
end
