# frozen_string_literal: true

module Manage
  # Org-level Documents hub: every document the current user can edit across the
  # productions they manage, plus a create-new flow that picks the production(s)
  # a document applies to. Viewing/editing a specific document happens under
  # Manage::DocumentsController.
  class OrgDocumentsController < Manage::ManageController
    before_action :load_managed_productions

    def index
      ids = @managed_productions.map(&:id)
      @documents = ProductionDocument
                     .joins(:document_productions)
                     .where(document_productions: { production_id: ids })
                     .includes(:production, :productions, :shares)
                     .distinct
                     .order(updated_at: :desc)
    end

    def new
      @document = ProductionDocument.new
      @selected_production_ids = Array(params[:production_id]).map(&:to_i)
    end

    def create
      chosen = chosen_productions
      if chosen.empty?
        redirect_to manage_new_org_document_path, alert: "Pick at least one production for this document."
        return
      end

      primary = chosen.first
      @document = primary.documents.new(document_params)
      @document.position = (primary.documents.maximum(:position) || 0) + 1
      if @document.save
        @document.set_productions!(chosen.map(&:id))
        @document.apply_default_sharing! # production team · can edit, by default
        redirect_to edit_manage_production_document_path(primary, @document), notice: "Document created."
      else
        @selected_production_ids = chosen.map(&:id)
        render :new, status: :unprocessable_entity
      end
    end

    private

    # Productions in this org the user can manage (and therefore add docs to).
    def load_managed_productions
      @managed_productions = Current.organization.productions.active
                                    .select { |p| Current.user.manager_for_production?(p) }
                                    .sort_by { |p| p.name.to_s.downcase }
    end

    def chosen_productions
      ids = Array(params[:production_ids]).map(&:to_s)
      @managed_productions.select { |p| ids.include?(p.id.to_s) }
    end

    def document_params
      params.require(:production_document).permit(:title)
    end
  end
end
