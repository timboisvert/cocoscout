# frozen_string_literal: true

module Manage
  class OrgCommunicationsController < Manage::ManageController
    def index
      # Get all productions for the organization
      @productions = Current.organization.productions.order(:name)

      # Load all email logs across all productions, grouped by batch
      base_query = EmailLog.for_organization(Current.organization)

      if params[:search].present?
        search_term = "%#{params[:search]}%"
        base_query = base_query.where("subject LIKE ? OR recipient LIKE ?", search_term, search_term)
      end

      # Get unique emails: one per batch (first one) + all non-batched emails
      batched_ids = base_query.where.not(email_batch_id: nil)
                              .group(:email_batch_id)
                              .pluck(Arel.sql("MIN(id)"))
      non_batched_ids = base_query.where(email_batch_id: nil).pluck(:id)

      all_ids = batched_ids + non_batched_ids
      email_logs_query = EmailLog.where(id: all_ids).recent

      @email_logs_pagy, @email_logs = pagy(email_logs_query.includes(:recipient_entity, :email_batch, :production), limit: 20)
      @search_query = params[:search]

      # For the send message modal
      @email_draft = EmailDraft.new

      # Load all people from the organization for recipient selection
      @talent_pool_people = Person.joins(:organizations)
                                  .where(organizations: { id: Current.organization.id })
                                  .includes(profile_headshots: { image_attachment: :blob })
                                  .order(:name)
                                  .distinct
    end
  end
end
