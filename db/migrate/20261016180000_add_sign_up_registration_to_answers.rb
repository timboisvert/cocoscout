# frozen_string_literal: true

# Answers to a sign-up form's questions belong to the registration they came
# with (after-V1 #1). An answer now belongs to an audition request or a
# sign-up registration, exactly one of the two.
class AddSignUpRegistrationToAnswers < ActiveRecord::Migration[8.1]
  def change
    change_column_null :answers, :audition_request_id, true
    add_reference :answers, :sign_up_registration, foreign_key: true, index: true
    add_check_constraint :answers, "num_nonnulls(audition_request_id, sign_up_registration_id) = 1", name: "answers_one_owner"
  end
end
