class AddTextToShowLinks < ActiveRecord::Migration[8.1]
  def change
    add_column :show_links, :text, :string
  end
end
