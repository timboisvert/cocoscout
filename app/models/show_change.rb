# frozen_string_literal: true

# A show canceled, taken away or moved, and the people it touched, read when
# it happened: the cast ([{ "person_id", "roles" }]) and the staff on its
# shifts ([{ "person_id", "shift_id", "role", "starts_at", "ends_at" }]). Each
# person told about it is a ShowChangeNotice, so "were they told?" has an
# answer whatever channel the message went by. Changes made in one request
# share a batch. docs/show_change_notices_plan.md (Tim, 2026-10-30).
class ShowChange < ApplicationRecord
  KINDS = %w[canceled removed moved].freeze

  belongs_to :organization
  belongs_to :production, optional: true
  belongs_to :show, optional: true
  belongs_to :contract, optional: true
  belongs_to :changed_by_user, class_name: "User", optional: true
  has_many :notices, class_name: "ShowChangeNotice", dependent: :destroy

  validates :kind, inclusion: { in: KINDS }
  validates :batch, :show_label, presence: true

  scope :open, -> { where(closed_at: nil) }

  # Canceled or taken away: the date is off.
  def off? = kind.in?(%w[canceled removed])
  def moved? = kind == "moved"

  def cast_person_ids = cast.map { |c| c["person_id"] }.uniq
  def staff_person_ids = staff.map { |s| s["person_id"] }.uniq
  def shift_ids = staff.map { |s| s["shift_id"] }.uniq

  def told_ids(audience)
    notices.select { |n| n.audience == audience }.map(&:person_id).to_set
  end

  def untold_cast_ids = cast_person_ids.reject { |id| told_ids("cast").include?(id) }
  def untold_staff_ids = staff_person_ids.reject { |id| told_ids("staff").include?(id) }

  # Someone still to tell, and nobody said it's done.
  def waiting? = closed_at.nil? && (untold_cast_ids.any? || untold_staff_ids.any?)
end
