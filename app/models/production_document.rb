# frozen_string_literal: true

# A rich-text document attached to a production — general docs or a performer
# handbook. Edited in-app with a rich text editor. Visibility/edit rights are
# governed by document_shares (audiences with a read/write permission).
class ProductionDocument < ApplicationRecord
  belongs_to :production
  has_rich_text :body
  has_many :shares, class_name: "DocumentShare", dependent: :destroy

  validates :title, presence: true, length: { maximum: 200 }

  scope :ordered, -> { order(:position, :created_at) }

  # Documents visible to a person, given their precomputed audience context
  # (see Person#document_audience_context). One query across all audience types.
  scope :visible_to_person, ->(person, ctx) {
    joins(:shares).where(
      "(document_shares.audience_type = 'person'      AND document_shares.audience_id = :pid) OR " \
      "(document_shares.audience_type = 'talent_pool' AND document_shares.audience_id IN (:pools)) OR " \
      "(document_shares.audience_type = 'team'        AND production_documents.production_id IN (:team_prods))",
      pid: person.id,
      pools: ctx[:pool_ids].presence || [ 0 ],
      team_prods: ctx[:team_production_ids].presence || [ 0 ]
    ).distinct
  }

  def visible_to?(person)
    return false unless person
    ctx = person.document_audience_context
    shares.any? { |s| share_matches?(s, person, ctx) }
  end

  def writable_by?(person)
    return false unless person
    ctx = person.document_audience_context
    shares.any? { |s| s.write? && share_matches?(s, person, ctx) }
  end

  # Default share applied to a new document: the production team, with write.
  def apply_default_sharing!
    shares.create!(audience_type: "team", permission: "write") unless shared_with_team?
  end

  # Rebuild all shares from the Sharing modal's selections.
  #   team:          { enabled:, permission: }
  #   talent_pools:  { "<pool_id>" => { enabled:, permission: } }
  #   people:        { "<person_id>" => permission }
  def set_sharing!(team:, talent_pools:, people:)
    team = team.to_h.with_indifferent_access
    transaction do
      shares.delete_all
      if ActiveModel::Type::Boolean.new.cast(team[:enabled])
        shares.create!(audience_type: "team", permission: norm_permission(team[:permission]))
      end
      (talent_pools || {}).each do |pool_id, cfg|
        cfg = cfg.to_h.with_indifferent_access
        next unless ActiveModel::Type::Boolean.new.cast(cfg[:enabled])
        shares.create!(audience_type: "talent_pool", audience_id: pool_id.to_i,
                       permission: norm_permission(cfg[:permission]))
      end
      (people || {}).each do |person_id, permission|
        next if person_id.to_i.zero?
        shares.create!(audience_type: "person", audience_id: person_id.to_i,
                       permission: norm_permission(permission))
      end
    end
  end

  # ----- editor helpers -----
  def team_share = shares.find { |s| s.audience_type == "team" }
  def shared_with_team? = team_share.present?
  def team_permission = team_share&.permission

  def talent_pool_shares = shares.select { |s| s.audience_type == "talent_pool" }
  def person_shares      = shares.select { |s| s.audience_type == "person" }
  def talent_pool_share_ids = talent_pool_shares.map(&:audience_id)
  def person_share_ids      = person_shares.map(&:audience_id)
  def pool_permission(pool_id)     = talent_pool_shares.find { |s| s.audience_id == pool_id }&.permission
  def person_permission(person_id) = person_shares.find { |s| s.audience_id == person_id }&.permission

  # Short human summary of who can see this, for lists.
  def audience_summary
    parts = []
    parts << "Production team" if shared_with_team?
    pools = talent_pool_shares.size
    parts << "#{pools} talent pool#{"s" unless pools == 1}" if pools.positive?
    people = person_shares.size
    parts << "#{people} #{"person".pluralize(people)}" if people.positive?
    parts.empty? ? "No one yet" : parts.join(" · ")
  end

  private

  def norm_permission(value)
    value.to_s == "write" ? "write" : "read"
  end

  def share_matches?(share, person, ctx)
    case share.audience_type
    when "person"      then share.audience_id == person.id
    when "talent_pool" then ctx[:pool_ids].include?(share.audience_id)
    when "team"        then ctx[:team_production_ids].include?(production_id)
    else false
    end
  end
end
