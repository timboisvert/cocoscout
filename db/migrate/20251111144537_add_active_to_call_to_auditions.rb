# frozen_string_literal: true

class AddActiveToCallToAuditions < ActiveRecord::Migration[8.1]
  def change
    add_column :call_to_auditions, :active, :boolean, default: true, null: false
    add_index :call_to_auditions, %i[production_id active], unique: true, where: 'active = true',
                                                            name: 'index_call_to_auditions_on_production_id_and_active'
  end
end
