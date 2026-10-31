# frozen_string_literal: true

# Once a day: warn group leaders whose seats are about to be released, and
# release the blocks that weren't paid in time (Ticketing::GroupSales).
class GroupHoldReleaseJob < ApplicationJob
  queue_as :default

  def perform
    Ticketing::GroupSales.sweep!
  end
end
