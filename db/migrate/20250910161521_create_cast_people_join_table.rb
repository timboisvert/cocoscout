# frozen_string_literal: true

class CreateCastPeopleJoinTable < ActiveRecord::Migration[8.0]
  def change
    create_table :casts_people, id: false do |t|
      t.belongs_to :cast
      t.belongs_to :person
    end
  end
end
