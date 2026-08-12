# frozen_string_literal: true

class AddStaffingRegularsEnabledToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :staffing_regulars_enabled, :boolean, default: false, null: false
  end
end
