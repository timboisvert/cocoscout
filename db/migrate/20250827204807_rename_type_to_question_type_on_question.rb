# frozen_string_literal: true

class RenameTypeToQuestionTypeOnQuestion < ActiveRecord::Migration[8.0]
  def change
    rename_column :questions, :type, :question_type
  end
end
