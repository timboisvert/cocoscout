class Audition < ApplicationRecord
  belongs_to :person
  belongs_to :audition_request
  belongs_to :audition_session
end
