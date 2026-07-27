# frozen_string_literal: true

class AddSignupModeToAuditions < ActiveRecord::Migration[8.1]
  def change
    # How performers get into an audition cycle:
    #   curated – the full pipeline (apply → review → vote → schedule into sessions)
    #   open    – performers book an open session slot themselves at sign-up
    add_column :audition_cycles, :signup_mode, :string, null: false, default: "curated"

    # Open-signup auditions create an Audition directly from a performer's slot
    # pick — there is no AuditionRequest behind them, so the FK must be nullable.
    change_column_null :auditions, :audition_request_id, true
  end
end
