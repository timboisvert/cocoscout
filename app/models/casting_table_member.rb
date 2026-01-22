# frozen_string_literal: true

class CastingTableMember < ApplicationRecord
  belongs_to :casting_table
  belongs_to :memberable, polymorphic: true

  validates :memberable_id, uniqueness: { scope: [ :casting_table_id, :memberable_type ] }
end
