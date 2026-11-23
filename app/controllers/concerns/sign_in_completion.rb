# frozen_string_literal: true

# The last step of every way in (the email screen, Apple, Google): make sure
# the account has a profile, start the session, and go where they were
# headed. One place, so each way in lands the same.
module SignInCompletion
  extend ActiveSupport::Concern

  private

  def finish_sign_in(user, method:)
    if user.person.nil?
      person = Person.find_by(email: user.email_address, user_id: nil)
      if person
        person.update!(user: user)
      else
        user.people.create(email: user.email_address, name: user.email_address.split("@").first)
      end
    end

    # The backfill only guessed who chose a password; a password that just
    # worked was chosen.
    user.update_column(:password_set_at, Time.current) if method == "password" && user.password_set_at.nil?

    session.delete(:sign_in)
    session.delete(:provider_pending)
    start_new_session_for user, sign_in_method: method
    redirect_to post_authentication_landing_path(user)
  end
end
