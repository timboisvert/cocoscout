# frozen_string_literal: true

class Role < ApplicationRecord
  belongs_to :production

  has_many :show_person_role_assignments, dependent: :destroy
  has_many :shows, through: :show_person_role_assignments

  validates :name, presence: true, uniqueness: { scope: :production_id, message: "already exists for this production" }

  default_scope { order(position: :asc, created_at: :asc) }
end
