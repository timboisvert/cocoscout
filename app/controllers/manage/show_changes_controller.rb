# frozen_string_literal: true

module Manage
  # Tell people: a batch of shows canceled, taken away or moved, and a send
  # each for their cast and staff, seen and edited first
  # (docs/show_change_notices_plan.md, Tim 2026-10-30).
  class ShowChangesController < Manage::ManageController
    before_action :load_notices, only: %i[show tell close]
    before_action :ensure_can_tell, only: %i[show tell close]

    def show
      @sections = @notices.sections
    end

    def tell
      key = params[:section].to_s
      count = @notices.send!(key, person_ids: Array(params[:person_ids]), subject: params[:subject].to_s, body: params[:body].to_s,
                                  sender: Current.user, shift_action: params[:shift_action] == "1")
      redirect_to manage_show_changes_path(params[:batch]),
                  notice: count.positive? ? "Told #{helpers.pluralize(count, 'person')}." : "Nobody was ticked, so nothing was sent.",
                  status: :see_other
    end

    # "Nobody needs telling."
    def close
      @notices.close!
      redirect_to manage_path, notice: "Closed. Nobody else will be asked about #{@changes.one? ? 'this change' : 'these changes'}.", status: :see_other
    end

    # A show canceled before changes were recorded: the change, from the show
    # as it stands, then the page to tell people.
    def for_canceled_show
      show = Show.joins(:production).where(productions: { organization_id: Current.organization.id }).find(params[:show_id])
      unless show.canceled? && Current.user&.manager_for_production?(show.production)
        redirect_to manage_path, notice: "You do not have permission to access that page." and return
      end

      change = ShowChanges.for_canceled(show)
      if change
        redirect_to manage_show_changes_path(change.batch), status: :see_other
      else
        redirect_to manage_path, notice: "Nobody was cast or scheduled for it, so there's nobody to tell.", status: :see_other
      end
    end

    private

    def load_notices
      @notices = ShowChangeNotices.for_batch(Current.organization, params[:batch].to_s)
      @changes = @notices.changes
      redirect_to manage_path, notice: "That change isn't here any more." if @changes.empty?
    end

    def ensure_can_tell
      return if performed?
      return if @changes.all? { |c| c.production && Current.user&.manager_for_production?(c.production) }

      redirect_to manage_path, notice: "You do not have permission to access that page."
    end
  end
end
