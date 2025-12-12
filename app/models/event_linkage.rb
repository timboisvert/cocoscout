# frozen_string_literal: true

class EventLinkage < ApplicationRecord
  belongs_to :production
  belongs_to :primary_show, class_name: "Show", optional: true

  has_many :shows, dependent: :nullify

  # Scoped associations for sibling vs child shows
  has_many :sibling_shows, -> { where(linkage_role: "sibling") }, class_name: "Show"
  has_many :child_shows, -> { where(linkage_role: "child") }, class_name: "Show"

  validates :production, presence: true

  # Get all shows in chronological order
  def all_shows_chronological
    shows.order(:date_and_time)
  end

  # Get the primary show - use explicit primary_show_id if set, otherwise fall back to first sibling by date
  def resolved_primary_show
    primary_show || sibling_shows.order(:date_and_time).first
  end

  # Get the poster from the primary show
  def poster
    resolved_primary_show&.poster
  end

  # Finalize casting for all linked shows
  def finalize_casting!
    shows.update_all(casting_finalized_at: Time.current)
  end

  # Reopen casting for all linked shows
  def reopen_casting!
    shows.update_all(casting_finalized_at: nil)
  end

  # Check if all shows have finalized casting
  def casting_finalized?
    shows.where(casting_finalized_at: nil).none?
  end

  # Generate a display name (either explicit name or auto-generated from dates)
  def display_name
    return name if name.present?

    siblings = sibling_shows.order(:date_and_time)
    return "Linked Events" if siblings.empty?

    if siblings.count == 1
      siblings.first.date_and_time.strftime("%b %-d")
    else
      first_date = siblings.first.date_and_time
      last_date = siblings.last.date_and_time

      if first_date.month == last_date.month
        "#{first_date.strftime('%b %-d')}-#{last_date.strftime('%-d')}"
      else
        "#{first_date.strftime('%b %-d')} - #{last_date.strftime('%b %-d')}"
      end
    end
  end
end
