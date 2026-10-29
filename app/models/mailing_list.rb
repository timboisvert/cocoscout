# frozen_string_literal: true

# A Pro organization's list of followers (Mailing lists, V1.1). Each
# organization has one main list, named after it; groups are lists for a
# producer or a production ("Dan Feltey's shows"), which can collect from
# productions at checkout and be shared with people, who see them in My
# Followers.
class MailingList < ApplicationRecord
  KINDS = %w[main group].freeze

  belongs_to :organization
  has_many :mailing_list_memberships, dependent: :destroy
  has_many :followers, through: :mailing_list_memberships
  has_many :mailing_list_productions, dependent: :destroy
  has_many :productions, through: :mailing_list_productions
  has_many :follower_sources, dependent: :nullify

  normalizes :name, with: ->(name) { name.to_s.squish }

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }

  scope :active, -> { where(archived_at: nil) }
  scope :main_first, -> { order(Arel.sql("CASE WHEN mailing_lists.kind = 'main' THEN 0 ELSE 1 END"), :name) }

  def main? = kind == "main"
  def archived? = archived_at.present?

  # The organization's main list, made the first time it's needed.
  def self.main_for!(organization)
    organization.mailing_lists.find_by(kind: "main") || organization.mailing_lists.create!(kind: "main", name: organization.name)
  rescue ActiveRecord::RecordNotUnique
    organization.mailing_lists.find_by!(kind: "main")
  end

  # The words on its box at checkout.
  def box_words
    return checkout_words if checkout_words.present?
    return organization.ticketing_profile&.follow_main_words.presence || "Send me news from #{organization.name}" if main?

    "Send me news about #{name}"
  end

  # The lists whose boxes a production's checkout shows: its own groups
  # first, then the main list.
  def self.for_checkout(production)
    organization = production.organization
    groups = organization.mailing_lists.active.where(kind: "group")
                         .where(id: MailingListProduction.where(production_id: production.id).select(:mailing_list_id))
                         .order(:name).to_a
    groups + [ main_for!(organization) ]
  end

  def subscribed_count
    followers.subscribed.count
  end
end
