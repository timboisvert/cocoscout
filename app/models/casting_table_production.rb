# frozen_string_literal: true

class CastingTableProduction < ApplicationRecord
  belongs_to :casting_table
  belongs_to :production

  validates :production_id, uniqueness: { scope: :casting_table_id }
end
