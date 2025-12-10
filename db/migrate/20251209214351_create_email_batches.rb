class CreateEmailBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :email_batches do |t|
      t.references :user, null: false, foreign_key: true
      t.string :subject
      t.string :mailer_class
      t.string :mailer_action
      t.integer :recipient_count
      t.datetime :sent_at

      t.timestamps
    end
  end
end
