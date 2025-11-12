class Current < ActiveSupport::CurrentAttributes
  attribute :session, :organization, :production
  delegate :user, to: :session, allow_nil: true
end
