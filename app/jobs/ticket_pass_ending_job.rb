# frozen_string_literal: true

# Every morning, for credit passes (punch cards, season passes): a holder
# whose pass ends within a week with credits left gets one reminder, and a
# pass past its end date ends (TicketPassCredits.end!): what's unused becomes
# the organization's, and its held money theirs to spend.
class TicketPassEndingJob < ApplicationJob
  queue_as :default

  REMIND_DAYS = 7

  def perform(today = Date.current)
    TicketPassHolding.active.where(reminded_at: nil, ends_on: today..(today + REMIND_DAYS)).find_each do |holding|
      next if holding.credits_left.zero? || holding.holder_email.blank?

      TicketOrderMailer.pass_ending(holding).deliver_now
      holding.update_columns(reminded_at: Time.current)
    end
    TicketPassHolding.active.where(ends_on: ...today).find_each { |holding| TicketPassCredits.end!(holding) }
  end
end
