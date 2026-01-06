# frozen_string_literal: true

class SignUpFormShow < ApplicationRecord
  belongs_to :sign_up_form
  belongs_to :show

  validates :show_id, uniqueness: { scope: :sign_up_form_id, message: "is already selected for this form" }
end
