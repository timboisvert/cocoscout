class ShowPersonRoleAssignment < ApplicationRecord
  belongs_to :show
  belongs_to :assignable, polymorphic: true
  belongs_to :role

  # Keep person association for backward compatibility during transition
  def person
    assignable if assignable_type == "Person"
  end

  def person=(value)
    self.assignable = value
  end
end
