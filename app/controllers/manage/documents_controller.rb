# frozen_string_literal: true

module Manage
  # Rich-text documents & handbooks for a production, with per-audience sharing
  # (read/write). New documents default to the production team with write access;
  # sharing is then adjusted via the Sharing modal.
  class DocumentsController < Manage::ManageController
    include DocumentAudienceOptions

    before_action :set_production
    before_action :check_production_access
    before_action :ensure_user_is_manager, except: %i[index show]
    before_action :set_document, only: %i[show edit update destroy share productions]
    before_action :load_audience_options, only: %i[show edit update share productions]

    def index
      # Everything that applies to this production — including shared documents
      # whose home is a different production.
      @documents = @production.applied_documents.includes(:shares).ordered
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

    # Sharing modal submit — rebuilds the document's audience grants (visibility).
    def share
      @document.set_sharing!(
        team: { enabled: params[:team_enabled], permission: params[:team_permission] },
        talent_pools: unsafe_hash(:talent_pools),
        people: unsafe_hash(:people)
      )
      redirect_back_or_to edit_manage_production_document_path(@production, @document), notice: "Sharing updated."
    end

    # Productions modal submit — which productions this document belongs to
    # (ownership). Restricted to productions the user manages; currently-attached
    # productions are always allowed so they're never silently dropped. Adding a
    # production gives its team access automatically (team sharing matches any
    # attached production).
    def productions
      allowed = (@attachable_productions.map(&:id) + @document.applies_to_production_ids).uniq
      ids = Array(params[:production_ids]).map(&:to_i).select { |i| allowed.include?(i) }
      @document.set_productions!(ids)
      redirect_back_or_to edit_manage_production_document_path(@production, @document), notice: "Productions updated."
    end

    def destroy
      @document.destroy!
      redirect_to manage_production_documents_path(@production), notice: "Document deleted."
    end

    private

    # Nested params (talent_pools / people) may be absent when nothing of that
    # kind is selected — return a plain hash either way.
    def unsafe_hash(key)
      val = params[key]
      val.respond_to?(:to_unsafe_h) ? val.to_unsafe_h : (val || {})
    end

    # Productions the user can attach this document to (the org's, that they
    # manage) + talent-pool/people options drawn from every production it
    # currently applies to, for the Sharing modal.
    def load_audience_options
      @attachable_productions = Current.organization.productions.active
                                       .select { |p| Current.user.manager_for_production?(p) }
                                       .sort_by { |p| p.name.to_s.downcase }

      @talent_pool_options, @candidate_people = document_audience_options(@document, @production)
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
      # Resolve against everything that applies to this production, so a shared
      # document can be opened from any production it's attached to.
      @document = @production.applied_documents.find(params[:id])
    end

    def document_params
      params.require(:production_document).permit(:title, :body)
    end
  end
end
