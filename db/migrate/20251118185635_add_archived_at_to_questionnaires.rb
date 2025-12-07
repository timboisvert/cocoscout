# frozen_string_literal: true

class AddArchivedAtToQuestionnaires < ActiveRecord::Migration[8.1]
  def change
    add_column :questionnaires, :archived_at, :datetime
  end
end
