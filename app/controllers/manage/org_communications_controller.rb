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

    def send_message
      production = Current.organization.productions.find(params[:production_id])

      # Build email draft
      email_draft = EmailDraft.new(
        title: params[:email_draft][:title],
        body: params[:email_draft][:body]
      )

      # Determine recipients
      if params[:send_to_all] == "1"
        talent_pool = production.effective_talent_pool
        recipients = talent_pool&.people&.to_a || []
      else
        person_ids = params[:person_ids] || []
        recipients = Person.where(id: person_ids).to_a
      end

      if recipients.empty?
        flash[:alert] = "No recipients selected."
        redirect_to manage_communications_path and return
      end

      # Create email batch
      email_batch = EmailBatch.create!(
        user: Current.user,
        subject: email_draft.title,
        mailer_class: "CommunicationsMailer",
        mailer_action: "send_message",
        sent_at: Time.current
      )

      # Send emails
      recipients.each do |person|
        next unless person.email.present?

        CommunicationsMailer.send_message(
          production: production,
          recipient: person,
          subject: email_draft.title,
          body: email_draft.body,
          email_batch: email_batch
        ).deliver_later
      end

      flash[:notice] = "Message sent to #{recipients.count} #{"recipient".pluralize(recipients.count)}."
      redirect_to manage_communications_path
    end

    def talent_pool_members
      production = Current.organization.productions.find(params[:production_id])
      talent_pool = production.effective_talent_pool

      people = if talent_pool
                 talent_pool.people.order(:name).map { |p| { id: p.id, name: p.name } }
      else
                 []
      end

      render json: { people: people }
    end
  end
end
