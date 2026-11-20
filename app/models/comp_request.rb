# frozen_string_literal: true

# A request for more comps on one date (Tim, 2026-11-20), from a production
# team manager or from someone on the contract's side, when the comp rules
# let that side request (CompRules team_comp_requests / contract_comp_requests).
# The organization's owners and managers decide it on the date's page in
# Ticketing: approve it, approve a different number, or decline it, with an
# optional comment. An approved number is that side's on top of the rules for
# that date, whatever the caps said (TicketListing#approved_comp_extra). One
# waiting request per side per date.
#
#   waiting    sent, nobody has decided it
#   approved   approved_quantity more for that date
#   declined   no more; the side keeps what it had
#   withdrawn  someone on the side took it back
#   closed     it could no longer be decided: showtime came, or the side was
#              no longer allowed to request (closed_reason)
class CompRequest < ApplicationRecord
  SIDES = %w[team contract].freeze
  STATUSES = %w[waiting approved declined withdrawn closed].freeze
  MAX = 1_000

  class Error < StandardError; end

  belongs_to :organization
  belongs_to :ticket_listing
  belongs_to :requested_by, class_name: "User"
  belongs_to :decided_by, class_name: "User", optional: true

  validates :side, inclusion: { in: SIDES }
  validates :status, inclusion: { in: STATUSES }
  validates :quantity, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX }
  validates :note, :comment, length: { maximum: 2000 }

  scope :waiting, -> { where(status: "waiting") }
  scope :approved, -> { where(status: "approved") }
  scope :decided, -> { where(status: %w[approved declined]) }

  def waiting? = status == "waiting"
  def approved? = status == "approved"
  def declined? = status == "declined"
  def contract? = side == "contract"
  def show = ticket_listing.show

  # The request the side sees on its Comps box for this date: one waiting,
  # else the latest decided or closed one (withdrawn ones are gone).
  def self.latest_for(listing, side)
    where(ticket_listing: listing, side: side.to_s).where.not(status: "withdrawn").order(created_at: :desc, id: :desc).first
  end

  # Sent by someone who may issue comps on this side.
  def self.request!(listing, side:, by:, quantity:, note: nil)
    raise Error, "#{side.to_s == 'contract' ? 'Contractors' : 'Production team managers'} can't request more comps for this date." unless listing.comp_requests_allowed?(side)
    raise Error, "This date has already started." if listing.show.date_and_time <= Time.current
    raise Error, "There's already a request waiting for this date." if waiting.exists?(ticket_listing: listing, side: side.to_s)

    request = create!(organization: listing.organization, ticket_listing: listing, side: side.to_s, requested_by: by,
                      quantity: quantity.to_i, note: note.to_s.strip.presence)
    CompRequestNotices.requested(request)
    request
  rescue ActiveRecord::RecordInvalid => e
    raise Error, e.record.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotUnique
    raise Error, "There's already a request waiting for this date."
  end

  # The whole number, or a different one.
  def approve!(by:, quantity: nil, comment: nil)
    count = (quantity.presence || self.quantity).to_i
    raise Error, "Approve at least 1." unless count.positive?
    raise Error, "Approve #{MAX} or fewer." if count > MAX

    decide!("approved", by: by, comment: comment, approved_quantity: count)
    CompRequestNotices.approved(self)
  end

  def decline!(by:, comment: nil)
    decide!("declined", by: by, comment: comment)
    CompRequestNotices.declined(self)
  end

  def withdraw!
    raise Error, "This request was already decided." unless waiting?

    update!(status: "withdrawn")
    CompRequestNotices.retract(self)
  end

  # No decision is possible any more: showtime, or the side may no longer request.
  def close!(reason)
    return unless waiting?

    update!(status: "closed", closed_reason: reason.to_s)
    CompRequestNotices.retract(self)
    CompRequestNotices.closed(self)
  end

  # Waiting requests past their date's showtime (CompRequestExpiryJob).
  def self.close_started!
    waiting.joins(ticket_listing: :show).where(shows: { date_and_time: ..Time.current }).find_each { |request| request.close!(:showtime) }
  end

  # Waiting requests whose side may no longer request (the comp rules changed).
  def self.close_turned_off!(organization)
    waiting.where(organization: organization).includes(:ticket_listing).find_each do |request|
      request.close!(:turned_off) unless request.ticket_listing.comp_requests_allowed?(request.side)
    end
  end

  # Who the request was for: "the people on the contract" / "the production team".
  def side_words = contract? ? "the people on the contract" : "the production team"

  private

  def decide!(outcome, by:, comment:, approved_quantity: nil)
    with_lock do
      raise Error, "This request was already #{status == 'waiting' ? 'decided' : status_words}." unless waiting?

      update!(status: outcome, decided_by: by, decided_at: Time.current, comment: comment.to_s.strip.presence, approved_quantity: approved_quantity)
    end
    CompRequestNotices.retract(self)
  end

  def status_words
    { "approved" => "approved", "declined" => "declined", "withdrawn" => "withdrawn", "closed" => "closed" }.fetch(status, "decided")
  end
end
