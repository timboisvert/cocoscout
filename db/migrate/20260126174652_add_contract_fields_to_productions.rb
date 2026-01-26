class AddContractFieldsToProductions < ActiveRecord::Migration[8.1]
  def change
    add_column :productions, :production_type, :string, default: "in_house", null: false
    add_reference :productions, :contract, null: true, foreign_key: true

    add_index :productions, :production_type
  end
end
