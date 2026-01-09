# frozen_string_literal: true

module Manage
  class CommunicationsController < Manage::ManageController
    before_action :set_production
    before_action :check_production_access

    def index
      # Load all email logs for this production, grouped by batch
      # For batched emails, show one representative per batch
      # For non-batched emails, show each individually
      base_query = EmailLog.for_production(@production).for_organization(Current.organization)

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

      @email_logs_pagy, @email_logs = pagy(email_logs_query.includes(:recipient_entity, :email_batch), limit: 20)
      @search_query = params[:search]

      # For the send message modal - create empty email draft
      @email_draft = EmailDraft.new

      # Load talent pool for recipient selection
      @talent_pool_people = @production.effective_talent_pool.people
                                       .includes(profile_headshots: { image_attachment: :blob })
                                       .order(:name)
    end

    def show
      @email_log = EmailLog.for_production(@production)
                           .for_organization(Current.organization)
                           .find(params[:id])

      # If this is part of a batch, load all recipients
      if @email_log.email_batch.present?
        @other_recipients = @email_log.email_batch.email_logs
                                      .where.not(id: @email_log.id)
                                      .includes(:recipient_entity)
      else
        @other_recipients = []
      end
    end

    def send_message
      person_ids = params[:person_ids]&.select(&:present?) || []
      send_to_all = params[:send_to_all] == "1"

      @email_draft = EmailDraft.new(email_draft_params)
      subject = @email_draft.title
      body_html = @email_draft.body.to_s

      # Determine recipients
      if send_to_all
        people_to_email = @production.effective_talent_pool.people.to_a
      else
        if person_ids.empty?
          redirect_to manage_production_communications_path(@production), alert: "Please select at least one recipient."
          return
        end
        people_to_email = @production.effective_talent_pool.people.where(id: person_ids).to_a
      end

      if people_to_email.empty?
        redirect_to manage_production_communications_path(@production), alert: "No valid recipients found."
        return
      end

      # Prepend production name to subject
      prefixed_subject = "[#{@production.name}] #{subject}"

      # Create email batch if sending to multiple people
      email_batch = nil
      if people_to_email.size > 1
        email_batch = EmailBatch.create!(
          user: Current.user,
          subject: prefixed_subject,
          recipient_count: people_to_email.size,
          sent_at: Time.current
        )
      end

      # Send emails
      people_to_email.each do |person|
        Manage::ProductionMailer.send_message(
          person,
          prefixed_subject,
          body_html,
          Current.user,
          email_batch_id: email_batch&.id,
          production_id: @production.id
        ).deliver_later
      end

      redirect_to manage_production_communications_path(@production),
                  notice: "Message sent to #{people_to_email.count} #{'recipient'.pluralize(people_to_email.count)}."
    end

    private

    def set_production
      if Current.organization
        @production = Current.organization.productions.find(params[:production_id])
      else
        redirect_to select_organization_path, alert: "Please select an organization first."
      end
    end

    def email_draft_params
      params.require(:email_draft).permit(:title, :body)
    end
  end
end
