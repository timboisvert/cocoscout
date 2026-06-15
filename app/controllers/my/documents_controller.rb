# frozen_string_literal: true

module My
  # Documents shared with the signed-in user across all their productions and
  # talent pools — the talent-side "My Documents".
  class DocumentsController < ApplicationController
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
    end

    private

    # Union of documents visible to any of the user's active profiles.
    def accessible_documents
      doc_ids = Current.user.people.active.flat_map { |p| p.accessible_production_documents.pluck(:id) }.uniq
      ProductionDocument.where(id: doc_ids)
    end
  end
end
