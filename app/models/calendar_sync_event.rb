# frozen_string_literal: true

# One event the Google Calendar integration keeps on the organization's
# calendar: the show or rental it stands for, Google's id for it, and a digest
# of what was last written there.
class CalendarSyncEvent < ApplicationRecord
  SYNCABLES = %w[Show SpaceRental].freeze

  belongs_to :integration

  validates :syncable_type, inclusion: { in: SYNCABLES }
  validates :syncable_id, uniqueness: { scope: %i[integration_id syncable_type] }

  def syncable
    syncable_type.constantize.find_by(id: syncable_id) if SYNCABLES.include?(syncable_type)
  end
end
