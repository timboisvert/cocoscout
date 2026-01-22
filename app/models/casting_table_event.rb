# frozen_string_literal: true

class CastingTableEvent < ApplicationRecord
  belongs_to :casting_table
  belongs_to :show

  validates :show_id, uniqueness: { scope: :casting_table_id }
end
