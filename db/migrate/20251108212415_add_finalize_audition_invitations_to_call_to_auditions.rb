# frozen_string_literal: true

class AddFinalizeAuditionInvitationsToCallToAuditions < ActiveRecord::Migration[8.1]
  def change
    add_column :call_to_auditions, :finalize_audition_invitations, :boolean, default: false
  end
end
