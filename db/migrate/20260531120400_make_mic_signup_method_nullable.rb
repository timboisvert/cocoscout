# frozen_string_literal: true

# We'd rather leave signup_method blank on listings where we genuinely
# don't know than fake "Bucket draw" everywhere.
class MakeMicSignupMethodNullable < ActiveRecord::Migration[8.1]
  def change
    change_column_null :mics, :signup_method, true
    change_column_default :mics, :signup_method, from: 0, to: nil
  end
end
