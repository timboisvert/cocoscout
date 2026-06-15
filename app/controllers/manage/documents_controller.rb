# frozen_string_literal: true

module Manage
  # Rich-text documents & handbooks for a production, with per-audience sharing
  # (read/write). New documents default to the production team with write access;
  # sharing is then adjusted via the Sharing modal.
  class DocumentsController < Manage::ManageController
    before_action :set_production
    before_action :check_production_access
    before_action :ensure_user_is_manager, except: %i[index show]
    before_action :set_document, only: %i[show edit update destroy share]
    before_action :load_audience_options, only: %i[edit update share index]

    def index
      @documents = @production.documents.includes(:shares).ordered
    end

    def show
    end

    def new
      @document = @production.documents.new
    end

    def create
      @document = @production.documents.new(document_params)
      @document.position = (@production.documents.maximum(:position) || 0) + 1
      if @document.save
        @document.apply_default_sharing! # visible to the production team by default
        redirect_to edit_manage_production_document_path(@production, @document), notice: "Document created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @document.update(document_params)
        redirect_to manage_production_document_path(@production, @document), notice: "Document saved."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Sharing modal submit — rebuilds the document's audience grants.
    def share
      @document.set_sharing!(
        team: { enabled: params[:team_enabled], permission: params[:team_permission] },
        talent_pools: (params[:talent_pools] || {}).to_unsafe_h,
        people: (params[:people] || {}).to_unsafe_h
      )
      redirect_back_or_to edit_manage_production_document_path(@production, @document), notice: "Sharing updated."
    end

    def destroy
      @document.destroy!
      redirect_to manage_production_documents_path(@production), notice: "Document deleted."
    end

    private

    # Talent pools + candidate people for the Sharing modal's people picker.
    def load_audience_options
      @talent_pools = @production.talent_pools.order(:created_at)

      people = []
      people.concat(@production.cast_people.to_a) if @production.respond_to?(:cast_people)
      @talent_pools.each { |pool| people.concat(pool.members.select { |m| m.is_a?(Person) }) }
      @candidate_people = people.uniq.sort_by { |p| p.name.to_s }
    end

    def set_production
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
      @production = Current.organization.productions.find(params[:production_id])
      sync_current_production(@production)
    end

    def set_document
      @document = @production.documents.find(params[:id])
    end

    def document_params
      params.require(:production_document).permit(:title, :body)
    end
  end
end
