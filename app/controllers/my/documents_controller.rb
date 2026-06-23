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

    # Union of documents visible to any of the user's active profiles.
    def accessible_documents
      doc_ids = Current.user.people.active.flat_map { |p| p.accessible_production_documents.pluck(:id) }.uniq
      ProductionDocument.where(id: doc_ids)
    end
  end
end
