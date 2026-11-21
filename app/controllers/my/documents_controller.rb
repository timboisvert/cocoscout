# frozen_string_literal: true

module My
  # Documents shared with the signed-in user across all their productions and
  # talent pools — the talent-side "My Documents".
  class DocumentsController < ApplicationController
    include DocumentAudienceOptions

    before_action :require_authentication

    def index
      @show_my_sidebar = true
      @documents = accessible_documents.includes(:production, :rich_text_body).order(updated_at: :desc)
      @documents_by_production = @documents.group_by(&:production)

      # Shared folders (Google Drive, Dropbox, or OneDrive) of every production
      # the user is in: its talent pool, which takes in the cast, or its team.
      # Each heads its production's group, even one with no documents.
      @linked_productions = linked_folder_productions
      @linked_productions.each { |production| @documents_by_production[production] ||= [] }

      # Agreements the user has signed — surfaced here so performers can always
      # find what they agreed to (links to the signed copy on the production).
      person_ids = Current.user.people.pluck(:id)
      @signed_agreements = AgreementSignature.where(person_id: person_ids)
                                             .includes(:production)
                                             .recent
    end

    def show
      @show_my_sidebar = true
      @document = accessible_documents.find_by(id: params[:id])
      redirect_to(my_documents_path, alert: "That document isn't available to you.") and return unless @document

      # If the viewer also manages one of this document's productions, surface the
      # full management UI (Sharing / Edit / Delete) inline — Edit/Delete route
      # through that production's manage pages, so no "my" edit/delete is needed.
      @manage_production = manageable_production_for(@document)
      if @manage_production
        @talent_pool_options, @candidate_people = document_audience_options(@document, @manage_production)
      end
    end

    private

    # The first of the document's productions that the user manages, or nil.
    # Checks production-specific and org-level manager grants explicitly so it
    # works on the talent side where Current.organization isn't set.
    def manageable_production_for(document)
      prods = ([ document.production ] + document.productions.to_a).compact.uniq
      managed_prod_ids = Current.user.production_permissions.where(role: "manager").pluck(:production_id).to_set
      managed_org_ids  = Current.user.organization_roles.where(company_role: "manager").pluck(:organization_id).to_set
      prods.find { |p| managed_prod_ids.include?(p.id) || managed_org_ids.include?(p.organization_id) }
    end

    # Productions with a shared folder that the user is in: one whose effective
    # talent pool holds any of their profiles (or their groups), or whose team
    # they're on. Same rule as reaching the production on My.
    def linked_folder_productions
      contexts = Current.user.people.active.map(&:document_audience_context)
      pool_ids = contexts.flat_map { |c| c[:pool_ids] }.uniq
      team_ids = contexts.flat_map { |c| c[:team_production_ids] }.uniq
      org_ids = Production.where(id: TalentPool.where(id: pool_ids).select(:production_id)).pluck(:organization_id) +
                Production.where(id: team_ids).pluck(:organization_id)
      return [] if org_ids.empty?

      Production.active.where(organization_id: org_ids.uniq).where.not(documents_link_url: [ nil, "" ])
                .includes(:organization, :talent_pools, talent_pool_shares: :talent_pool).order(:name)
                .select { |p| p.documents_link? && (team_ids.include?(p.id) || pool_ids.include?(p.effective_talent_pool&.id)) }
    end

    # Union of documents visible to any of the user's active profiles.
    def accessible_documents
      doc_ids = Current.user.people.active.flat_map { |p| p.accessible_production_documents.pluck(:id) }.uniq
      ProductionDocument.where(id: doc_ids)
    end
  end
end
