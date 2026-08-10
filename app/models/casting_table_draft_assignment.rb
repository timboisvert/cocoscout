# frozen_string_literal: true

class CastingTableDraftAssignment < ApplicationRecord
  belongs_to :casting_table
  belongs_to :show
  belongs_to :role
  belongs_to :assignable, polymorphic: true

  validates :assignable_id, uniqueness: { scope: [ :casting_table_id, :show_id, :role_id, :assignable_type ] }
end
