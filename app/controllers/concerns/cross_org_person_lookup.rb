# frozen_string_literal: true

# The "add someone already on CocoScout" pickers deliberately resolve a Person
# by bare id across org boundaries — that's the search-first invite flow (find
# an existing account, pull them into your org). Keep that UX, but leave an
# audit trail whenever the resolved person isn't already in the caller's org,
# so bulk id-enumeration harvesting shows up in the logs instead of being
# indistinguishable from normal invites.
module CrossOrgPersonLookup
  # Drop-in for Person.find_by(id: ...) at attach sites. Returns nil when the
  # id doesn't resolve.
  def find_person_for_attach(id)
    person = Person.find_by(id: id)
    return nil unless person

    unless Current.organization.people.exists?(person.id)
      Rails.logger.info(
        "[cross_org_person_attach] user=#{Current.user&.id} org=#{Current.organization&.id} " \
        "person=#{person.id} via=#{self.class.name}##{action_name}"
      )
    end
    person
  end
end
