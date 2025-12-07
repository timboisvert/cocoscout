# frozen_string_literal: true

class AddMaximumAuditioneesToAuditionSession < ActiveRecord::Migration[8.0]
  def change
    add_column :audition_sessions, :maximum_auditionees, :integer
  end
end
