class ChangeHideContactInfoDefaultToTrue < ActiveRecord::Migration[8.1]
  def change
    # Change default for new Person records to hide contact info by default
    change_column_default :people, :hide_contact_info, from: false, to: true

    # Change default for new Group records to hide contact info by default
    change_column_default :groups, :hide_contact_info, from: false, to: true
  end
end
