class ChangeShowIdNullableOnSignUpFormInstances < ActiveRecord::Migration[8.1]
  def change
    change_column_null :sign_up_form_instances, :show_id, true
  end
end
