# frozen_string_literal: true

# Builds the talent-pool / people options that feed a document's Sharing modal.
# Shared between Manage::DocumentsController (manager editing in-context) and
# My::DocumentsController (a manager viewing the doc from the talent side), so
# the Sharing modal behaves identically in both places.
module DocumentAudienceOptions
  extend ActiveSupport::Concern

  private

  # Returns [talent_pool_options, candidate_people] drawn from every production
  # the document applies to (falling back to fallback_production for a new doc).
  def document_audience_options(document, fallback_production)
    source_productions = (document&.persisted? ? document.productions.to_a : []).presence ||
                         [ fallback_production ].compact

    talent_pool_options = source_productions.flat_map { |p| talent_pool_options_for(p) }.uniq { |o| o[:id] }

    people = []
    source_productions.each { |p| people.concat(p.cast_people.to_a) if p.respond_to?(:cast_people) }
    talent_pool_options.each { |opt| people.concat(opt[:pool].members.select { |m| m.is_a?(Person) }) }
    candidate_people = people.uniq.sort_by { |p| p.name.to_s }

    [ talent_pool_options, candidate_people ]
  end

  # The single talent pool worth offering for a given production, named for its
  # kind. Returns [] when there's nothing meaningful to share with:
  #   - org-wide pool  → only when the org runs a single shared pool
  #   - shared pool    → when this production borrows another's pool
  #   - own pool       → otherwise, but hidden when it has no members yet
  def talent_pool_options_for(production)
    org = production.organization

    if org.talent_pool_single? && org.organization_talent_pool.present?
      pool = org.organization_talent_pool
      return [ { id: pool.id, pool: pool, name: "#{org.name} Talent Pool",
                 subtitle: "Organization talent pool" } ]
    end

    if production.uses_shared_pool?
      pool = production.effective_talent_pool
      names = pool.all_productions.order(:name).pluck(:name)
      return [ { id: pool.id, pool: pool, name: "Shared Talent Pool",
                 subtitle: names.join(" · ") } ]
    end

    pool = production.talent_pool
    return [] unless pool && pool.talent_pool_memberships.exists?

    [ { id: pool.id, pool: pool, name: "#{production.name} Talent Pool", subtitle: "Talent pool" } ]
  end
end
