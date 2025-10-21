class Question < ApplicationRecord
  belongs_to :questionable, polymorphic: true
  has_many :question_options, dependent: :destroy
  has_many :answers, dependent: :destroy
  accepts_nested_attributes_for :question_options, reject_if: :all_blank, allow_destroy: true

  validates :text, presence: true
  validates :question_type, presence: true
end
