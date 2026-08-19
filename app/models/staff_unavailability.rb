# frozen_string_literal: true

# A date on which a person has marked themselves unavailable to work house
# shifts. Person-level (applies across every org they staff). The mark covers
# the whole day, or one work time region by key — "evening", "late_morning" —
# from the catalog each organization picks its regions from
# (StaffingDayParts). A region an org hasn't turned on is simply a mark that
# never blocks a shift there.
#
# "Available" everywhere in the Staffing module simply means *not* covered by
# one of these records.
class StaffUnavailability < ApplicationRecord
  # The old fixed enum (all_day / day_shifts / evening_shifts); the data moved
  # to day_part_key. Dropped in a follow-up migration once no running code
  # reads it.
  self.ignored_columns += [ "scope" ]

  belongs_to :person

  ALL_DAY = "all_day"

  validates :date, presence: true
  validates :person_id, uniqueness: { scope: :date }

  # The mark as the client speaks of it: "all_day" or the region key.
  def scope
    day_part_key.presence || ALL_DAY
  end

  def scope=(value)
    self.day_part_key = value.to_s == ALL_DAY ? nil : value.presence
  end

  def all_day?
    day_part_key.blank?
  end

  # Is this person unavailable at `time` for `organization`? Ruby twin of the
  # mode-aware check in shift_assign_controller.js. Takes the person's
  # availability_mode and their preloaded entries (rather than a person) so
  # callers can batch a whole week's people without N+1s. In "available" mode
  # the marks are the only workable slots, so an unmarked time means unavailable.
  def self.unavailable_for?(mode:, entries:, time:, organization:)
    covers = entries.any? { |e| e.date == time.to_date && e.covers_time?(time, organization) }
    mode == "available" ? !covers : covers
  end

  # Does this record cover a shift starting at `time`, read against the
  # organization's regions? All day covers everything; a region mark covers
  # a start time that falls in that region (regions overlap, so a Late
  # morning shift is also a Morning shift).
  def covers_time?(time, organization)
    all_day? || organization.staffing_day_part_keys_for(time).include?(day_part_key)
  end

  def covers_shift?(shift)
    covers_time?(shift.starts_at, shift.organization)
  end

  # Short human label — "All day", or the region's name as the organization
  # calls it (its key, titleized, when no organization is at hand).
  def scope_label(organization = nil)
    return "All day" if all_day?

    organization ? organization.staffing_day_part_name(day_part_key) : day_part_key.to_s.titleize
  end
end
