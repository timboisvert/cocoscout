# frozen_string_literal: true

class AddRequireAllAvailabilityToCallToAuditions < ActiveRecord::Migration[8.1]
  def change
    add_column :call_to_auditions, :require_all_availability, :boolean, default: false
  end
end
