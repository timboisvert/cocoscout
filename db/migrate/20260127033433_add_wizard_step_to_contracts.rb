class AddWizardStepToContracts < ActiveRecord::Migration[8.1]
  def change
    add_column :contracts, :wizard_step, :integer, default: 1, null: false
  end
end
