class Audition < ApplicationRecord
  belongs_to :auditionable, polymorphic: true
  belongs_to :audition_request
  belongs_to :audition_session

  # Alias for backward compatibility
  def person
    auditionable if auditionable_type == "Person"
  end
end
