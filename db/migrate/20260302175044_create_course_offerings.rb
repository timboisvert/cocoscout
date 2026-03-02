class CreateCourseOfferings < ActiveRecord::Migration[8.1]
  def change
    create_table :course_offerings do |t|
      t.references :production, null: false, foreign_key: true
      t.string :short_code, null: false
      t.string :status, null: false, default: "draft"
      t.string :title, null: false
      t.text :description
      t.string :instructor_name
      t.text :instructor_bio
      t.integer :price_cents, null: false
      t.integer :early_bird_price_cents
      t.datetime :early_bird_deadline
      t.string :currency, null: false, default: "usd"
      t.integer :capacity
      t.string :stripe_product_id
      t.string :stripe_price_id
      t.string :stripe_early_bird_price_id
      t.datetime :opens_at
      t.datetime :closes_at
      t.text :instruction_text
      t.text :success_text

      t.timestamps
    end

    add_index :course_offerings, :short_code, unique: true
    add_index :course_offerings, :status
  end
end
