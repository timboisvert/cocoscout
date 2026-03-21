class DropCocobaseTables < ActiveRecord::Migration[8.1]
  def up
    drop_table :cocobase_answers, if_exists: true
    drop_table :cocobase_submissions, if_exists: true
    drop_table :cocobase_fields, if_exists: true
    drop_table :cocobases, if_exists: true
    drop_table :cocobase_template_fields, if_exists: true
    drop_table :cocobase_templates, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
