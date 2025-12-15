class CreateAuditionReviewers < ActiveRecord::Migration[8.1]
  def change
    create_table :audition_reviewers do |t|
      t.references :audition_cycle, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true

      t.timestamps
    end
  end
end
