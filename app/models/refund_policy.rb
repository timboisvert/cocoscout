# frozen_string_literal: true

# A box office's refund policy (Tim, 2026-10-07), the way Eventbrite and the
# rest offer it: refunds up to a window before the show (24 hours by
# default), no refunds, or case by case; whether the fees the buyer paid come
# back (not by default); and a note in the organization's own words. A show
# the organization cancels is always refunded in full, whatever this says.
#
# The box office sets it (TicketingProfile); a production can set its own
# (ProductionTicketing, blank fields follow the box office), and its dates
# follow it. Each order keeps the policy it was sold under (to_snapshot);
# TicketOrderRefund.policy_check holds a refund to the more generous of that
# and today's.
class RefundPolicy
  KINDS = %w[window none case_by_case].freeze
  # The windows offered as cards, in hours before the show; any whole number
  # of days (1–365) is allowed too.
  WINDOWS = [ 0, 24, 48, 168, 720 ].freeze
  MAX_HOURS = 365 * 24
  NOTE_LIMIT = 500

  # The settings form's cards: [value, title, hint].
  CHOICES = [
    [ "window_0", "Until the show starts", "Any time before showtime." ],
    [ "window_24", "Up to 24 hours before", "A common window for theaters." ],
    [ "window_48", "Up to 48 hours before", nil ],
    [ "window_168", "Up to 7 days before", nil ],
    [ "window_720", "Up to 30 days before", nil ],
    [ "custom", "Up to a number of days you choose", nil ],
    [ "none", "No refunds", "All sales final. A show you cancel is still refunded in full." ],
    [ "case_by_case", "Case by case", "No window: buyers are told to ask you, and every refund is your call." ]
  ].freeze

  # The card a stored policy shows as.
  def self.choice_for(kind, hours)
    return kind if %w[none case_by_case].include?(kind.to_s)

    WINDOWS.include?(hours.to_i) ? "window_#{hours.to_i}" : "custom"
  end

  # The columns a card (and, for custom, its day count) saves as; nil for
  # anything else.
  def self.attributes_for(choice, days = nil)
    case choice.to_s
    when "none", "case_by_case" then { refund_policy: choice.to_s }
    when "custom" then { refund_policy: "window", refund_window_hours: days.to_i.clamp(1, 365) * 24 }
    when /\Awindow_(\d+)\z/
      hours = Regexp.last_match(1).to_i
      { refund_policy: "window", refund_window_hours: hours } if WINDOWS.include?(hours)
    end
  end

  attr_reader :kind, :hours, :fees, :note, :contact

  def initialize(kind:, hours: 24, fees: false, note: nil, contact: nil)
    @kind = KINDS.include?(kind.to_s) ? kind.to_s : "window"
    @hours = hours.to_i.clamp(0, MAX_HOURS)
    @fees = fees ? true : false
    @note = note.to_s.strip.presence
    @contact = contact
  end

  # The policy a date sells under: its production's, else the box office's.
  def self.for(listing)
    of_setup(listing.production_ticketing, TicketingProfile.for(listing.organization))
  end

  # A production's own policy when it has one (blank fields follow the box
  # office), else the box office's.
  def self.of_setup(setup, profile)
    return of_profile(profile) unless setup&.refund_policy.present?

    new(kind: setup.refund_policy, hours: setup.refund_window_hours || profile.refund_window_hours,
        fees: setup.refund_fees.nil? ? profile.refund_fees : setup.refund_fees, note: setup.refund_policy_note,
        contact: profile.support_email.presence || profile.organization.name)
  end

  def self.of_profile(profile, contact: nil)
    new(kind: profile.refund_policy, hours: profile.refund_window_hours, fees: profile.refund_fees,
        note: profile.refund_policy_note, contact: contact || profile.support_email.presence || profile.organization.name)
  end

  # The policy an order was sold under, or nil for one sold before policies.
  def self.from_snapshot(hash)
    return nil if hash.blank?

    new(kind: hash["kind"], hours: hash["hours"], fees: hash["fees"], note: hash["note"], contact: hash["contact"])
  end

  def to_snapshot
    { "kind" => kind, "hours" => hours, "fees" => fees, "note" => note, "contact" => contact, "words" => words }
  end

  def window?
    kind == "window"
  end

  # The last moment a refund is within the policy, for a window policy.
  def deadline(show)
    show.date_and_time - hours.hours if window?
  end

  # "24 hours", "7 days"; nil for until the show starts.
  def window_phrase
    return nil if hours.zero?

    hours < 72 ? "#{hours} hours" : ActionController::Base.helpers.pluralize(hours / 24, "day")
  end

  # One line, for the ticket page and the manager's lists.
  def short_words
    case kind
    when "none" then "No refunds"
    when "case_by_case" then "Refunds case by case"
    else hours.zero? ? "Refunds until the show starts" : "Refunds up to #{window_phrase} before the show"
    end
  end

  # What buyers are told, whole.
  def words
    lines = case kind
    when "none" then [ "All sales are final: no refunds." ]
    when "case_by_case" then [ "Refunds are case by case#{": ask #{contact}" if contact.present?}." ]
    else [ "#{short_words}." ]
    end
    lines << (fees ? "Fees are refunded too." : "Fees aren't refunded.") unless kind == "none"
    lines << "If a show is canceled, you get everything back."
    lines << note if note
    lines.join(" ")
  end

  # Which of two policies treats a buyer better (an order's snapshot and
  # today's): case by case leaves every refund open; a window that ends
  # later beats one that ends sooner; no refunds is the strictest. Fees come
  # back if either says so.
  def self.more_generous(one, other)
    return one || other if one.nil? || other.nil?

    rank = ->(p) { p.kind == "case_by_case" ? [ 2, 0 ] : (p.window? ? [ 1, -p.hours ] : [ 0, 0 ]) }
    best = (rank.call(one) <=> rank.call(other)) >= 0 ? one : other
    return best if best.fees || !(one.fees || other.fees)

    new(kind: best.kind, hours: best.hours, fees: true, note: best.note, contact: best.contact)
  end
end
