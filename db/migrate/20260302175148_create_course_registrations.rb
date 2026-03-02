class CreateCourseRegistrations < ActiveRecord::Migration[8.1]
  def change
    create_table :course_registrations do |t|
      t.references :course_offering, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "usd"
      t.string :stripe_checkout_session_id
      t.string :stripe_payment_intent_id
      t.datetime :paid_at
      t.datetime :cancelled_at
      t.datetime :refunded_at
      t.datetime :registered_at, null: false

      t.timestamps
    end

    add_index :course_registrations, :status
    add_index :course_registrations, :stripe_checkout_session_id, unique: true
    add_index :course_registrations, [ :course_offering_id, :person_id ],
              unique: true,
              where: "status NOT IN ('cancelled', 'refunded')",
              name: "idx_course_registrations_active_unique"
  end
end
