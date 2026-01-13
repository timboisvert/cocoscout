class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      t.references :production, null: false, foreign_key: true
      t.references :author, polymorphic: true, null: false
      t.references :parent, foreign_key: { to_table: :posts }
      t.text :body

      t.timestamps
    end

    add_index :posts, [ :production_id, :created_at ]
    add_index :posts, [ :parent_id, :created_at ]
  end
end
