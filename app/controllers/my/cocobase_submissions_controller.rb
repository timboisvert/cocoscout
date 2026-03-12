# frozen_string_literal: true

module My
  class CocobaseSubmissionsController < ApplicationController
    before_action :require_superadmin
    before_action :set_submission

    def show
      @cocobase = @submission.cocobase
      @show = @cocobase.show
      @production = @show.production
      @fields = @cocobase.cocobase_fields.order(:position)
      @answers_by_field = @submission.cocobase_answers.index_by(&:cocobase_field_id)
    end

    def update
      @cocobase = @submission.cocobase
      @show = @cocobase.show
      @production = @show.production
      @fields = @cocobase.cocobase_fields.order(:position)

      if @cocobase.closed? || @submission.submitted?
        redirect_to my_cocobase_submission_path(@submission),
                    alert: "This submission is no longer accepting changes."
        return
      end

      ActiveRecord::Base.transaction do
        @fields.each do |field|
          answer = @submission.cocobase_answers.find_or_initialize_by(cocobase_field_id: field.id)

          case field.field_type
          when "file_upload"
            if params.dig(:answers, field.id.to_s, :file).present?
              answer.file.attach(params[:answers][field.id.to_s][:file])
            end
          else
            answer.value = params.dig(:answers, field.id.to_s, :value).to_s
          end

          answer.save!
        end

        if params[:commit] == "Submit"
          @submission.submit!
        else
          @submission.update!(status: :in_progress) if @submission.pending?
        end
      end

      if @submission.submitted?
        redirect_to my_cocobase_submission_path(@submission),
                    notice: "Your submission has been received. Thank you!"
      else
        redirect_to my_cocobase_submission_path(@submission),
                    notice: "Your progress has been saved."
      end
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:alert] = e.message
      @answers_by_field = @submission.cocobase_answers.reload.index_by(&:cocobase_field_id)
      render :show, status: :unprocessable_entity
    end

    private

    def set_submission
      @submission = CocobaseSubmission.find(params[:id])

      # Verify the current user owns this submission
      entity = @submission.submittable
      person_ids = Current.user.people.pluck(:id)

      authorized = if entity.is_a?(Person)
        person_ids.include?(entity.id)
      elsif entity.is_a?(Group)
        GroupMembership.where(group: entity, person_id: person_ids).exists?
      else
        false
      end

      unless authorized
        redirect_to my_requests_path, alert: "You don't have access to this submission."
      end
    end
  end
end
