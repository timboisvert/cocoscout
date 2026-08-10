# frozen_string_literal: true

# The one way to create a User account with its Person, used by every
# self-serve entry point (signup form, public org-join link, invitation
# accept). Finds and adopts a pre-existing Person with the same email —
# that's how manager-created people get claimed — and always sets
# user.default_person, which ad-hoc call sites used to forget.
#
# Returns a Result; check result.user.persisted? — validation errors stay on
# result.user for the caller's own form rendering.
class AccountCreator
  Result = Struct.new(:user, :person, keyword_init: true)

  def self.call(email:, password:)
    user = User.new(email_address: email, password: password)
    return Result.new(user: user, person: nil) unless user.save

    person = Person.find_by(email: user.email_address)
    if person
      person.user = user
      person.save!
    else
      person = Person.create!(
        email: user.email_address,
        name: user.email_address.split("@").first.titleize,
        user: user
      )
    end

    user.update!(default_person: person)
    Result.new(user: user, person: person)
  end
end
