# frozen_string_literal: true

module Manage
  class EmailLogsController < Manage::ManageController
    def show
      @email_log = EmailLog.find(params[:id])
      @recipient_entity = @email_log.recipient_entity

      # Find other recipients from the same email batch
      @other_recipients = if @email_log.email_batch_id.present?
        EmailLog.where(email_batch_id: @email_log.email_batch_id)
                .where.not(id: @email_log.id)
                .where.not(recipient_entity_id: nil)
                .includes(:recipient_entity)
      else
        EmailLog.none
      end

      # Determine back path based on recipient entity type
      @back_path = if @recipient_entity.is_a?(Person)
                     manage_person_path(@recipient_entity, tab: 3)
                   elsif @recipient_entity.is_a?(Group)
                     manage_group_path(@recipient_entity, tab: 3)
                   else
                     manage_directory_path
                   end
    end
  end
end
