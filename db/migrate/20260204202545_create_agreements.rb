class CreateAgreements < ActiveRecord::Migration[8.1]
  def change
    # Templates at org level - reusable across productions
    create_table :agreement_templates do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description  # Internal note: "Use for burlesque shows"
      t.text :content, null: false
      t.integer :version, default: 1, null: false
      t.boolean :active, default: true, null: false
      t.timestamps

      t.index [ :organization_id, :active ]
    end

    # Production agreement settings
    add_reference :productions, :agreement_template,
                  foreign_key: { to_table: :agreement_templates }
    add_column :productions, :agreement_required, :boolean, default: false, null: false

    # Signatures - record of who signed what
    create_table :agreement_signatures do |t|
      t.references :person, null: false, foreign_key: true
      t.references :production, null: false, foreign_key: true
      t.references :agreement_template, foreign_key: true
      t.datetime :signed_at, null: false
      t.string :ip_address
      t.text :user_agent
      t.text :content_snapshot, null: false  # Exact content they signed
      t.integer :template_version  # Version number at time of signing
      t.timestamps

      t.index [ :person_id, :production_id ], unique: true
    end
  end
end
