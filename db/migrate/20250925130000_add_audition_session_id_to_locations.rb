# frozen_string_literal: true

class AddAuditionSessionIdToLocations < ActiveRecord::Migration[7.0]
  def change
    add_reference :audition_sessions, :location, foreign_key: true
  end
end
