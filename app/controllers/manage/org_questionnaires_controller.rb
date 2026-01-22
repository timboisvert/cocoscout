# frozen_string_literal: true

module Manage
  class OrgQuestionnairesController < Manage::ManageController
    def index
      @filter = params[:filter]

      # Get all questionnaires across all productions
      base_scope = Questionnaire.joins(:production)
                                .where(productions: { organization_id: Current.organization.id })
                                .includes(:production, :questionnaire_responses)

      # Apply filter
      case @filter
      when "accepting"
        questionnaires = base_scope.where(archived_at: nil, accepting_responses: true)
        @page_title = "Accepting Responses"
        @page_description = "Questionnaires currently accepting responses across all productions."
      when "archived"
        questionnaires = base_scope.where.not(archived_at: nil)
        @page_title = "Archived Questionnaires"
        @page_description = "Archived questionnaires across all productions."
      else
        questionnaires = base_scope.where(archived_at: nil)
        @page_title = "All Questionnaires"
        @page_description = "All active questionnaires across all productions."
      end

      # Group by production
      @questionnaires_by_production = questionnaires.order(created_at: :desc)
                                                    .group_by(&:production)

      # Get archived questionnaires for the archived section
      @archived_questionnaires = base_scope.where.not(archived_at: nil)
                                           .order(archived_at: :desc)
                                           .limit(10) unless @filter == "archived"
    end
  end
end
