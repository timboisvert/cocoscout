class MessageRegard < ApplicationRecord
  belongs_to :message
  belongs_to :regardable, polymorphic: true

  validates :message_id, uniqueness: { scope: [ :regardable_type, :regardable_id ] }
end
