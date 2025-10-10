class AddPositionToQuestions < ActiveRecord::Migration[7.0]
  def change
    add_column :questions, :position, :integer
    add_index :questions, [ :questionable_type, :questionable_id, :position ], name: "idx_qstnbl_type_id_pos"
  end
end
