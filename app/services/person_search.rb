# frozen_string_literal: true

# Finding people across CocoScout from a manager's picker (Tim, 2026-10-12).
# People already connected to the organization match by name or any part of
# their email, and their email shows. Everyone else matches by name, profile
# key, or their exact email, and their email stays hidden (unless it's what
# was typed), so a picker can't be used to fish addresses out of CocoScout.
module PersonSearch
  module_function

  # People outside the organization (the caller excludes its own).
  def outside(query, scope = Person.all)
    exact, like = terms(query)
    scope.where("people.name ILIKE :like OR people.public_key ILIKE :like OR LOWER(people.email) = :exact", like: like, exact: exact)
  end

  # Users outside the organization; the scope must join people.
  def outside_users(query, scope)
    exact, like = terms(query)
    scope.where("people.name ILIKE :like OR LOWER(users.email_address) = :exact", like: like, exact: exact)
  end

  # Anyone on CocoScout: the organization's own people by any part of their
  # email too, everyone else as outside.
  def anyone(query, organization, scope = Person.all)
    exact, like = terms(query)
    scope.where("people.name ILIKE :like OR LOWER(people.email) = :exact", like: like, exact: exact)
         .or(scope.where(id: organization.people.select(:id)).where("people.email ILIKE :like", like: like))
  end

  # Which of these people are the organization's own (their email shows).
  def connected_ids(organization, people)
    ids = people.map(&:id)
    return Set.new if ids.empty?

    organization.people.where(id: ids).pluck(:id).to_set
  end

  def terms(query)
    q = query.to_s.strip
    [ q.downcase, "%#{Person.sanitize_sql_like(q)}%" ]
  end
end
