# frozen_string_literal: true

# The onboarding invite lists what the new hire will do; add the W-9 now that
# it's one of the steps. Only touches the stock wording — an org-edited
# template is left alone.
class MentionW9InStaffOnboardingInvite < ActiveRecord::Migration[8.1]
  OLD = "you'll accept your spot, set up how you get paid, and add your availability."
  NEW = "you'll accept your spot, share your tax info (Form W-9), set up how you get paid, and add your availability."

  def up
    swap(OLD, NEW)
  end

  def down
    swap(NEW, OLD)
  end

  private

  def swap(from, to)
    template = ContentTemplate.find_by(key: "staff_onboarding_invite")
    return unless template&.body&.include?(from)

    template.update!(body: template.body.sub(from, to))
  end
end
