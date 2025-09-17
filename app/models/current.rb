class Current < ActiveSupport::CurrentAttributes
  attribute :session, :production_company, :production
  delegate :user, to: :session, allow_nil: true
end
