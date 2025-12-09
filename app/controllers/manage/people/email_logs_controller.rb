# frozen_string_literal: true

module Manage
  module People
    class EmailLogsController < Manage::ManageController
      before_action :set_person
      before_action :set_email_log, only: :show

      def index
        @search = params[:search].to_s.strip
        @email_logs = @person.email_logs.recent

        # Filter by search term if provided (search by subject or body)
        if @search.present?
          @email_logs = @email_logs.where(
            "subject LIKE ? OR body LIKE ?",
            "%#{@search}%",
            "%#{@search}%"
          )
        end

        # Paginate
        @pagy, @email_logs = pagy(@email_logs, items: 25)
      end

      def show
        # @email_log is set by before_action
      end

      private

      def set_person
        @person = Current.organization.people.find(params[:person_id])
      end

      def set_email_log
        @email_log = @person.email_logs.find(params[:id])
      end
    end
  end
end
