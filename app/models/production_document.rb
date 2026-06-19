# frozen_string_literal: true

# A rich-text document attached to a production — general docs or a performer
# handbook. Edited in-app with a rich text editor. Visibility/edit rights are
# governed by document_shares (audiences with a read/write permission).
class ProductionDocument < ApplicationRecord
  # Primary "home" production. The document ALSO applies to every production in
  # `productions` (via document_productions) — that's what lets one handbook be
  # shared by several shows. The primary is always part of that set.
  belongs_to :production
  has_many :document_productions, dependent: :destroy
  has_many :productions, through: :document_productions

  has_rich_text :body
  has_many :shares, class_name: "DocumentShare", dependent: :destroy

  validates :title, presence: true, length: { maximum: 200 }

  scope :ordered, -> { order(:position, :created_at) }

  # Keep the primary production in the applies-to set no matter how the document
  # was created (controllers, specs, factories all stay correct).
  after_create :ensure_primary_production_link

  # Documents visible to a person, given their precomputed audience context
  # (see Person#document_audience_context). One query across all audience types.
  scope :visible_to_person, ->(person, ctx) {
    # Team visibility is satisfied by ANY production the document applies to.
    joins(:shares).joins(:document_productions).where(
      "(document_shares.audience_type = 'person'      AND document_shares.audience_id = :pid) OR " \
      "(document_shares.audience_type = 'talent_pool' AND document_shares.audience_id IN (:pools)) OR " \
      "(document_shares.audience_type = 'team'        AND document_productions.production_id IN (:team_prods))",
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

  # ----- productions this document applies to -----
  def applies_to_production_ids
    document_productions.loaded? ? document_productions.map(&:production_id) : document_productions.pluck(:production_id)
  end

  # Short "Starlet · Rising Stars" summary for lists, primary first.
  def applies_to_summary(limit: 3)
    names = ([ production ] + productions.to_a).uniq.compact.sort_by { |p| (p.id == production_id ? 0 : 1).to_s + p.name.to_s }.map(&:name)
    extra = names.size - limit
    extra > 0 ? "#{names.first(limit).join(" · ")} +#{extra}" : names.join(" · ")
  end

  # Replace the applies-to set. Never empties it; re-points the primary if the
  # current primary was removed so the document always has a valid home.
  def set_productions!(production_ids)
    ids = Array(production_ids).map(&:to_i).reject(&:zero?).uniq
    ids = [ production_id ].compact if ids.empty?
    transaction do
      unless ids.include?(production_id)
        update_column(:production_id, ids.first)
      end
      document_productions.where.not(production_id: ids).delete_all
      existing = document_productions.pluck(:production_id)
      (ids - existing).each { |pid| document_productions.create!(production_id: pid) }
    end
  end

  private

  def norm_permission(value)
    value.to_s == "write" ? "write" : "read"
  end

  def share_matches?(share, person, ctx)
    case share.audience_type
    when "person"      then share.audience_id == person.id
    when "talent_pool" then ctx[:pool_ids].include?(share.audience_id)
    when "team"        then (applies_to_production_ids & ctx[:team_production_ids]).any?
    else false
    end
  end

  def ensure_primary_production_link
    return if production_id.nil?
    document_productions.find_or_create_by!(production_id: production_id)
  end
end
