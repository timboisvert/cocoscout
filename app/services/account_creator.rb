# frozen_string_literal: true

# The one way to create a User account with its Person, used by every
# self-serve entry point (the sign-in screen's create step, public org-join
# link, invitation accept). Finds and adopts a pre-existing Person with the
# same email that nobody has claimed (that's how manager-created people get
# claimed) and always sets user.default_person, which ad-hoc call sites used
# to forget.
#
#   password:        the password the person chose, or nil when they didn't
#                    choose one (they sign in with a code; User.new_unclaimed)
#   name:            what they entered; falls back to the email's first part
#   email_verified:  true when they just proved the address with a code
#
# Returns a Result; check result.user.persisted? — validation errors stay on
# result.user for the caller's own form rendering.
class AccountCreator
  Result = Struct.new(:user, :person, keyword_init: true)

  def self.call(email:, password: nil, name: nil, email_verified: false)
    user = password.nil? ? User.new_unclaimed(email_address: email) : User.new(email_address: email, password: password)
    user.email_verified_at = Time.current if email_verified
    return Result.new(user: user, person: nil) unless user.save

    name = name.to_s.squish.presence
    # Only a Person with no account: one that belongs to someone else (who
    # has since changed their sign-in email) is theirs, not this person's.
    person = Person.where(email: user.email_address, user_id: nil).order(:created_at).first
    if person
      person.user = user
      person.name = name if name && email_verified
      person.save!
    else
      person = Person.create!(
        email: user.email_address,
        name: name || user.email_address.split("@").first.titleize,
        user: user
      )
    end

    user.update!(default_person: person)
    Result.new(user: user, person: person)
  end
end
