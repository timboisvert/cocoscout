# frozen_string_literal: true

# Producer-set status for a specific date on a self-described mic. For
# production-linked mics we use Show.mic_status as the source of truth;
# this table is the parallel surface so the public detail view renders
# the same status chips for both cases.
class MicOccurrenceStatus < ApplicationRecord
  belongs_to :mic

  enum :status, {
    scheduled: 0,
    running_as_planned: 1,
    cancelled: 2,
    online_only: 3,
    extra_spots: 4
  }, prefix: :status

  validates :occurs_on, presence: true,
                        uniqueness: { scope: :mic_id }
end
