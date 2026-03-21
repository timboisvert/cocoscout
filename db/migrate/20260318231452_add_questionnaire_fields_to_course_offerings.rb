class AddQuestionnaireFieldsToCourseOfferings < ActiveRecord::Migration[8.1]
  def change
    add_reference :course_offerings, :questionnaire, null: true, foreign_key: true
    add_column :course_offerings, :delivery_mode, :string
    add_column :course_offerings, :delivery_delay_minutes, :integer
    add_column :course_offerings, :delivery_scheduled_at, :datetime
  end
end
