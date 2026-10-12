# frozen_string_literal: true

# Emails in people pickers: shown for the organization's own people, and for
# anyone else only when it's exactly what the manager typed (PersonSearch).
module PersonSearchHelper
  def searched_email(email, query, connected: false)
    return email if connected
    return email if email.present? && email.casecmp?(query.to_s.strip)

    nil
  end

  # The second line under a name in a picker: the email when it may show,
  # otherwise their public profile address, so two people with one name can
  # still be told apart.
  def searched_detail(person, query, connected: false)
    searched_email(person.email, query, connected: connected) ||
      (person.public_key.present? ? "cocoscout.com/#{person.public_key}" : nil)
  end
end
