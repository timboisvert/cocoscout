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
    before_action :load_audience_options, only: %i[show edit update share]

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

    # Talent pool option(s) + candidate people for the Sharing modal.
    def load_audience_options
      @talent_pool_options = build_talent_pool_options

      people = []
      people.concat(@production.cast_people.to_a) if @production.respond_to?(:cast_people)
      @talent_pool_options.each { |opt| people.concat(opt[:pool].members.select { |m| m.is_a?(Person) }) }
      @candidate_people = people.uniq.sort_by { |p| p.name.to_s }
    end

    # The single talent pool worth offering for this production, named for its
    # kind. Returns [] when there's nothing meaningful to share with:
    #   - org-wide pool  → only when the org runs a single shared pool
    #   - shared pool    → when this production borrows another's pool
    #   - own pool       → otherwise, but hidden when it has no members yet
    def build_talent_pool_options
      org = @production.organization

      if org.talent_pool_single? && org.organization_talent_pool.present?
        pool = org.organization_talent_pool
        return [ { id: pool.id, pool: pool, name: "#{org.name} Talent Pool",
                   subtitle: "Organization talent pool" } ]
      end

      if @production.uses_shared_pool?
        pool = @production.effective_talent_pool
        names = pool.all_productions.order(:name).pluck(:name)
        return [ { id: pool.id, pool: pool, name: "Shared Talent Pool",
                   subtitle: names.join(" · ") } ]
      end

      pool = @production.talent_pool
      return [] unless pool && pool.talent_pool_memberships.exists?

      [ { id: pool.id, pool: pool, name: "#{@production.name} Talent Pool", subtitle: "Talent pool" } ]
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
