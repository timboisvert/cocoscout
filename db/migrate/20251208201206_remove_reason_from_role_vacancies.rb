class RemoveReasonFromRoleVacancies < ActiveRecord::Migration[8.1]
  def change
    remove_column :role_vacancies, :reason, :text
  end
end
