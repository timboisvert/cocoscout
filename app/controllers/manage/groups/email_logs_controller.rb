# frozen_string_literal: true

module Manage
  module Groups
    class EmailLogsController < Manage::ManageController
      before_action :set_group
      before_action :set_email_log, only: :show

      def index
        @search = params[:search].to_s.strip
        @email_logs = @group.email_logs.recent

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
        # Load all group members for display
        @members = @group.members
      end

      private

      def set_group
        @group = Current.organization.groups.find(params[:group_id])
      end

      def set_email_log
        @email_log = @group.email_logs.find(params[:id])
      end
    end
  end
end
