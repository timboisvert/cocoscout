# frozen_string_literal: true

# == Schema Information
#
# Table name: casting_tables
#
#  id             :integer          not null, primary key
#  organization_id :integer          not null
#  created_by_id  :integer
#  name           :string           not null
#  status         :string           not null, default: "draft"
#  finalized_at   :datetime
#  finalized_by_id :integer
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
class CastingTable < ApplicationRecord
  belongs_to :organization
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :finalized_by, class_name: "User", optional: true

  has_many :casting_table_productions, dependent: :destroy
  has_many :productions, through: :casting_table_productions

  has_many :casting_table_events, dependent: :destroy
  has_many :shows, through: :casting_table_events

  has_many :casting_table_members, dependent: :destroy
  has_many :casting_table_draft_assignments, dependent: :destroy

  validates :name, presence: true
  validates :status, presence: true, inclusion: { in: %w[draft finalized] }

  scope :draft, -> { where(status: "draft") }
  scope :finalized, -> { where(status: "finalized") }

  def draft?
    status == "draft"
  end

  def finalized?
    status == "finalized"
  end

  def finalize!
    return false unless draft?

    transaction do
      # Create actual ShowPersonRoleAssignment records from draft assignments
      casting_table_draft_assignments.includes(:show, :role, :assignable).find_each do |draft|
        ShowPersonRoleAssignment.find_or_create_by!(
          show: draft.show,
          role: draft.role,
          assignable: draft.assignable
        )
      end

      # Mark shows as casting finalized if they're fully cast
      shows.each do |show|
        if show.fully_cast?
          show.finalize_casting!
        end
      end

      update!(
        status: "finalized",
        finalized_at: Time.current
      )
    end

    true
  end

  # Revert a finalized casting table back to draft status
  # Removes the ShowPersonRoleAssignment records that were created
  def unfinalize!
    return false unless finalized?

    transaction do
      # Remove the ShowPersonRoleAssignment records that match our draft assignments
      casting_table_draft_assignments.includes(:show, :role, :assignable).find_each do |draft|
        ShowPersonRoleAssignment.where(
          show: draft.show,
          role: draft.role,
          assignable: draft.assignable
        ).destroy_all
      end

      # Unfinalize show casting status for affected shows
      shows.each do |show|
        show.update!(casting_finalized: false) if show.respond_to?(:casting_finalized)
      end

      update!(
        status: "draft",
        finalized_at: nil,
        finalized_by_id: nil
      )
    end

    true
  end

  # Record that notifications were sent for all draft assignments
  # Called after sending emails
  def record_notifications!(email_body: nil)
    casting_table_draft_assignments.includes(:show, :role, :assignable).find_each do |draft|
      next if draft.assignable_type == "Group" # Groups don't get individual notifications

      draft.show.show_cast_notifications.find_or_initialize_by(
        assignable: draft.assignable,
        role: draft.role
      ).update!(
        notification_type: :cast,
        notified_at: Time.current,
        email_body: email_body
      )
    end
  end

  # Get people/groups from talent pools of included productions
  def talent_pool_members
    person_ids = Set.new
    group_ids = Set.new

    productions.each do |production|
      production.talent_pool_members.each do |member|
        case member.memberable_type
        when "Person"
          person_ids << member.memberable_id
        when "Group"
          group_ids << member.memberable_id
        end
      end
    end

    { person_ids: person_ids.to_a, group_ids: group_ids.to_a }
  end

  # Check if any shows are already used in a finalized casting table
  def self.shows_already_finalized(show_ids)
    CastingTableEvent.joins(:casting_table)
                     .where(show_id: show_ids)
                     .where(casting_tables: { status: "finalized" })
                     .pluck(:show_id)
                     .uniq
  end
end
