# frozen_string_literal: true

module Manage
  # Org-level Documents hub: every document the current user can edit across the
  # productions they manage, plus a create-new flow that picks a production first.
  # Viewing/editing a specific document happens under Manage::DocumentsController.
  class OrgDocumentsController < Manage::ManageController
    before_action :load_managed_productions

    def index
      docs = ProductionDocument.where(production_id: @managed_productions.map(&:id))
                               .includes(:production, :shares).ordered
      @documents_by_production = docs.group_by(&:production)
    end

    def new
      @document = ProductionDocument.new
    end

    def create
      production = @managed_productions.find { |p| p.id.to_s == params[:production_id].to_s }
      unless production
        redirect_to manage_new_org_document_path, alert: "Choose a production for this document."
        return
      end

      @document = production.documents.new(document_params)
      @document.position = (production.documents.maximum(:position) || 0) + 1
      if @document.save
        @document.apply_default_sharing!
        redirect_to edit_manage_production_document_path(production, @document), notice: "Document created."
      else
        @production_id = production.id
        render :new, status: :unprocessable_entity
      end
    end

    private

    # Productions in this org the user can manage (and therefore edit docs in).
    def load_managed_productions
      @managed_productions = Current.organization.productions.active
                                    .select { |p| Current.user.manager_for_production?(p) }
                                    .sort_by { |p| p.name.to_s.downcase }
    end

    def document_params
      params.require(:production_document).permit(:title)
    end
  end
end
