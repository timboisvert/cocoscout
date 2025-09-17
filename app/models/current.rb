class Current < ActiveSupport::CurrentAttributes
  attribute :session, :production_company
  delegate :user, to: :session, allow_nil: true
end
