# frozen_string_literal: true

# A Pro organization's list of followers (Mailing lists, V1.1). Each
# organization has one main list, named after it; groups are lists for a
# producer or a production ("Dan Feltey's shows"), which can collect from
# productions at checkout and be shared with people, who see them in My
# Followers.
class MailingList < ApplicationRecord
  KINDS = %w[main group].freeze

  belongs_to :organization
  # A list for a contractor (Tim, 2026-11-17): it collects from every
  # production that contractor has under a live contract, and is shared
  # with everyone on those contracts (SharedFollowers).
  belongs_to :contractor, optional: true
  # In the organization a list was shared with, on Pro: the list it came
  # from. Its followers are that organization's own (SharedFollowers.sync!).
  belongs_to :source_list, class_name: "MailingList", optional: true
  has_many :mailing_list_memberships, dependent: :destroy
  has_many :followers, through: :mailing_list_memberships
  has_many :mailing_list_productions, dependent: :destroy
  has_many :productions, through: :mailing_list_productions
  has_many :follower_sources, dependent: :nullify

  normalizes :name, with: ->(name) { name.to_s.squish }

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validate :contractor_is_this_organizations

  scope :active, -> { where(archived_at: nil) }
  scope :main_first, -> { order(Arel.sql("CASE WHEN mailing_lists.kind = 'main' THEN 0 ELSE 1 END"), :name) }

  def main? = kind == "main"
  def archived? = archived_at.present?
  def for_contractor? = contractor_id.present?
  # Shared with the people on the contractor's contracts, right now.
  def shared? = for_contractor? && shared_with_contractor && !archived?
  def received? = source_list_id.present?

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

  # The small line under its box, when ticking it shares the buyer's address
  # with someone outside the organization: it names who.
  def box_note
    "#{contractor.name} and #{organization.name} can both email you about them." if shared? && contractor
  end

  # The productions a contractor's list collects from by itself: every one
  # that contractor has under a live contract here.
  def self.contract_production_ids(contractor_id)
    Contract.where(contractor_id: contractor_id, status: "active").where.not(production_id: nil).distinct.pluck(:production_id)
  end

  def contract_productions
    return Production.none unless for_contractor?

    organization.productions.where(id: self.class.contract_production_ids(contractor_id)).order(:name)
  end

  # The lists whose boxes a production's checkout shows: the main list
  # first, then the production's own (Tim, 2026-11-17): a contractor's list
  # (it comes from the contract), then the lists chosen for this production.
  def self.for_checkout(production)
    organization = production.organization
    contractors = Contract.where(organization_id: organization.id, production_id: production.id, status: "active").select(:contractor_id)
    scope = organization.mailing_lists.active.where(kind: "group", source_list_id: nil)
    from_contract = scope.where(contractor_id: contractors).order(:name).to_a
    chosen = scope.where(id: MailingListProduction.where(production_id: production.id).select(:mailing_list_id))
                  .where.not(id: from_contract.map(&:id)).order(:name).to_a
    [ main_for!(organization) ] + from_contract + chosen
  end

  def subscribed_count
    followers.subscribed.count
  end

  private

  def contractor_is_this_organizations
    return if contractor.nil? || organization.nil?

    errors.add(:contractor, "isn't one of this organization's") unless contractor.organization_id == organization_id
  end
end
