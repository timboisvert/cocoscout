# frozen_string_literal: true

# A contractor's request about one date on their contract: move it, cancel
# it, add one, or a plain question (Tim, 2026-11-16). One request, about one
# date, with one answer. It changes nothing by itself: only an amendment
# changes the contract. The organization answers by amending the contract
# (the request then closes itself when the change lands) or by keeping the
# date, with a note.
#
#   open       waiting for the organization
#   amending   they amended through Change the deal, and the change waits
#              for a signature (back to open if that amendment is discarded)
#   done       the contract now says what was asked
#   kept       they answered no, with their reason
#   withdrawn  the asker took it back
#   void       it no longer applies: the date passed or changed another way,
#              or the contract ended
class ContractDateRequest < ApplicationRecord
  KINDS = %w[move cancel add question].freeze
  STATUSES = %w[open amending done kept withdrawn void].freeze
  WAITING = %w[open amending].freeze
  # How long an answer stays on the asker's page by itself.
  DONE_SHOWS_FOR = 1.day
  # How long "no longer applies" stays there, when the date changed some
  # other way while the request waited.
  VOID_SHOWS_FOR = 7.days
  REMIND_AFTER = 3.days

  belongs_to :organization
  belongs_to :contract
  belongs_to :show, optional: true
  belongs_to :requested_by, class_name: "User"
  belongs_to :answered_by, class_name: "User", optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :note, :answer_note, length: { maximum: 2000 }
  validate :asks_something_answerable, on: :create

  scope :waiting, -> { where(status: WAITING) }
  scope :answered, -> { where(status: %w[done kept]) }
  # What the asker still sees on a date: a request that waits, and an answer
  # until it's dismissed (a "done" clears itself after a day).
  scope :showing_to_asker, lambda {
    where(dismissed_at: nil).where(
      "status IN ('open', 'amending', 'kept') OR (status = 'done' AND closed_at > :done) OR (status = 'void' AND closed_at > :void)",
      done: DONE_SHOWS_FOR.ago, void: VOID_SHOWS_FOR.ago
    )
  }

  def waiting? = status.in?(WAITING)
  def open? = status == "open"

  def proposed_local = proposed_at&.in_time_zone(time_zone)
  def original_local = original_at&.in_time_zone(time_zone)

  def time_zone = organization.time_zone.presence || Time.zone.name

  # "move Fri Dec 18 to 7:30 PM", "cancel Fri Dec 18, 8:00 PM", "add Sun Dec 13,
  # 3:00 PM", "about Fri Dec 18, 8:00 PM": the request in a few words, to
  # follow "requests to" (or "a question" for a question).
  def words
    case kind
    when "move" then "move #{day_words(original_local)} to #{move_target_words}"
    when "cancel" then "cancel #{moment_words(original_local)}"
    when "add" then "add #{moment_words(proposed_local)}"
    else "about #{moment_words(original_local)}"
    end
  end

  # "requests to move Fri Dec 18 to 7:30 PM" / "has a question about Fri Dec
  # 18, 8:00 PM": what the contractor wants, to follow their name.
  def requests_words = kind == "question" ? "has a question #{words}" : "requests to #{words}"

  # "You requested to move Fri Dec 18 to 7:30 PM": the request read back to
  # whoever made it, where the date isn't otherwise on the page.
  def requested_words = kind == "question" ? "Your question #{words}" : "You requested to #{words}"

  # "the request to move Fri Dec 18 to 7:30 PM" / "the question about Fri Dec 18, 8:00 PM".
  def request_phrase = kind == "question" ? "the question #{words}" : "the request to #{words}"

  # What the organization did, once the contract says what was asked:
  # "moved Fri Dec 18 to 7:30 PM", "canceled Fri Dec 18, 8:00 PM", "added Sun Dec 13, 3:00 PM".
  def outcome_words
    case kind
    when "move" then "moved #{day_words(original_local)} to #{move_target_words}"
    when "cancel" then "canceled #{moment_words(original_local)}"
    when "add" then "added #{moment_words(proposed_local)}"
    else "answered your question #{words}"
    end
  end

  # What the organization's "no" comes to: "kept Fri Dec 18 at 8:00 PM",
  # "didn't cancel Fri Dec 18, 8:00 PM", "didn't add Sun Dec 13, 3:00 PM".
  def kept_words
    case kind
    when "move" then original_local ? "kept #{day_words(original_local)} at #{clock_words(original_local)}" : "kept the date as it is"
    when "cancel" then "didn't cancel #{moment_words(original_local)}"
    when "add" then "didn't add #{moment_words(proposed_local)}"
    else "answered your question #{words}"
    end
  end

  # "Your request to move Fri Dec 18 to 7:30 PM" / "Your question about Fri Dec 18, 8:00 PM".
  def your_request_words = kind == "question" ? "Your question #{words}" : "Your request to #{words}"

  # Why a request stopped applying, when the date changed some other way
  # while it waited: "that date is now Sun Nov 29, 9:00 PM", "that date was
  # canceled", "that date is no longer on the contract". Nil when it simply
  # ran out (the date passed, the contract ended): nothing to say then.
  def superseded_words
    return nil if kind == "add" || contract.status.in?(%w[cancelled completed])
    return "that date is no longer on the contract" if show.nil?
    return "that date was canceled" if show.canceled
    return nil if show.date_and_time < Time.current

    "that date is now #{moment_words(show.date_and_time.in_time_zone(time_zone))}" if original_at && show.date_and_time != original_at
  end

  # The organization's "no", as a button and as its question:
  # "Keep 8:00 PM" / "Keep Fri Dec 18 at 8:00 PM?".
  def keep_button_words
    case kind
    when "move" then original_local ? "Keep #{clock_words(original_local)}" : "Keep it as it is"
    when "cancel" then "Keep the date"
    when "add" then "Don't add it"
    else "Reply"
    end
  end

  def keep_title_words(asker_name)
    case kind
    when "move" then original_local ? "Keep #{day_words(original_local)} at #{clock_words(original_local)}?" : "Keep the date as it is?"
    when "cancel" then "Keep #{moment_words(original_local)} on the contract?"
    when "add" then "Not adding #{moment_words(proposed_local)}?"
    else "Reply to #{asker_name}"
    end
  end

  def moment_words(time) = time ? "#{day_words(time)}, #{clock_words(time)}" : "this date"
  def day_words(time) = time ? time.strftime("%a %b %-d") : "this date"
  def clock_words(time) = time.strftime("%-l:%M %p")

  # Has the contract come to say what was asked? Read from the show as it
  # stands now, so it's true however the change was made.
  def satisfied?
    case kind
    when "move" then show.present? && !show.canceled && show.date_and_time == proposed_at
    when "cancel" then show.nil? || show.canceled
    when "add" then contract.contract_shows.where(canceled: false, date_and_time: proposed_at).exists?
    else false
    end
  end

  # No longer something the organization can act on.
  def lapsed?
    return true if contract.status.in?(%w[cancelled completed])
    return (proposed_at || created_at) < Time.current if kind == "add"
    return true if show.nil? || show.canceled
    return true if show.date_and_time < Time.current

    # The date moved somewhere other than where they asked.
    kind != "question" && original_at.present? && show.date_and_time != original_at
  end

  private

  # The same day reads as a time alone; another day needs both.
  def move_target_words
    return "another time" unless proposed_local

    same_day = original_local && original_local.to_date == proposed_local.to_date
    same_day ? clock_words(proposed_local) : moment_words(proposed_local)
  end

  # Said in whole sentences, on the base: these are read back to the asker
  # as they are.
  def asks_something_answerable
    errors.add(:base, "That date isn't on this contract any more.") if kind != "add" && show.nil?
    if kind.in?(%w[move add])
      if proposed_at.nil?
        errors.add(:base, "Choose the day and time you're requesting.")
      elsif proposed_at < Time.current
        errors.add(:base, "That day and time has already passed.")
      elsif kind == "move" && show && show.date_and_time == proposed_at
        errors.add(:base, "That's when the date already is.")
      elsif kind == "add" && contract&.contract_shows&.where(canceled: false, date_and_time: proposed_at)&.exists?
        errors.add(:base, "That day and time is already on the contract.")
      end
    end
    errors.add(:base, "Write your question.") if kind == "question" && note.blank?
  end
end
