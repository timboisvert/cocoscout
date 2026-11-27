# frozen_string_literal: true

module Manage
  # "Cancel or move this date" (Tim, 2026-11-27): one flow for canceling,
  # moving, deleting, and bringing back dates. The manager chooses what's
  # happening and which dates, sees everything it touches with a default for
  # each, reviews it in sentences, and confirms; CocoScout then does all of it
  # (ShowChangePlan::Apply, in DateChangeApplyJob) and the change's page keeps
  # the record of each step finishing.
  #
  # A draft DateChange holds the choices between steps, so Back always works.
  class DateChangesController < Manage::ManageController
    before_action :set_show_from_path, only: %i[new create new_restore destroy_dates new_contract_move]
    before_action :set_change, except: %i[new create new_restore destroy_dates new_contract_move]
    before_action :check_production_access
    before_action :ensure_user_is_manager
    before_action :require_draft, only: %i[dates save_dates when_page save_when check touches save_touches review apply]

    CHOICE_KEYS = %i[
      buyers_action rebook_listing_id buyers_subject buyers_body rebook_subject rebook_body other_paid comps_email
      cast_notify cast_subject cast_body shifts_off staff_notify staff_subject staff_body signups_cancel
      students_email students_subject students_body clear_pay respread followers
      buyers_email buyers_refund_offer shifts_move signups_action signups_notify contract_notify staff_back
      back_on_subject back_on_body
    ].freeze

    # Step 1: what to do with the date.
    def new
      @facts = ShowChangePlan::Dates.facts([ @show ])[@show.id]
      @series = ShowChangePlan::Dates.series(@show)
      @following = ShowChangePlan::Dates.following(@show)
      @delete_blockers = ShowChangePlan::Delete.blockers([ @show ])
      @linked = @show.event_linkage ? @show.event_linkage.shows.reject { |s| s.id == @show.id || s.canceled? } : []
      return redirect_to manage_new_date_restore_path(@production, @show) if @show.canceled?

      @kind = params[:kind].presence_in(%w[cancel move delete]) || "cancel"
      @kind = "move" if params[:move].present?
    end

    def create
      kind = params[:kind].presence_in(%w[cancel move delete])
      return redirect_to(manage_new_date_change_path(@production, @show), alert: "Choose what you'd like to do with the date.") unless kind
      return redirect_to(manage_new_date_change_path(@production, @show, kind: "delete", delete: 1)) if kind == "delete"
      return redirect_to(manage_move_contract_date_path(@show.space_rental.contract_id, @show)) if kind == "move" && @show.space_rental_id

      change = build_change(kind)
      change.scope = "this"
      change.show_ids = [ @show.id ]
      change.also_show_ids = default_ties([ @show ], kind)
      change.save!
      redirect_to kind == "move" ? manage_date_change_when_path(change) : manage_date_change_dates_path(change)
    end

    # Step 2 of a cancel: which dates, and the events tied to them.
    def dates
      load_dates_step
    end

    def save_dates
      scope = params[:scope].presence_in(DateChange::SCOPES) || "this"
      ids = case scope
      when "this" then [ @change.show_id ]
      when "following" then ShowChangePlan::Dates.following(@change.show).map(&:id)
      else chosen_ids
      end
      ids = [ @change.show_id ] if ids.empty?
      also = Array(params[:also_show_ids]).flat_map { |v| v.to_s.split(",") }.map(&:to_i)
      if refreshing? && (scope != @change.scope || ids.sort != @change.show_ids.map(&:to_i).sort)
        also = default_ties(org_shows(ids), @change.kind)
      end
      @change.update!(scope: scope, show_ids: ids, also_show_ids: also - ids)
      return redirect_to(@change.move? ? manage_date_change_when_path(@change) : manage_date_change_dates_path(@change)) if refreshing?

      redirect_to manage_date_change_touches_path(@change)
    end

    # Step 2 of a move: which dates, and where they go.
    def when_page
      load_when_step
      render :when
    end

    def save_when
      move = (@change.move || {}).dup
      scope = params[:scope].presence_in(%w[this following]) || @change.scope || "this"
      ids = scope == "following" ? ShowChangePlan::Dates.following(@change.show).map(&:id) : [ @change.show_id ]
      fields = params.fetch(:move, {}).permit(:date, :starts, :ends, :place, :linked, :wday, per_date: {})
      move.merge!(fields.to_h.except("per_date", "place"))
      if fields.key?(:place)
        location_id, space_id = fields[:place].to_s.split(":")
        location = Current.organization.locations.find_by(id: location_id)
        move["location_id"] = location&.id&.to_s
        move["location_space_id"] = location&.location_spaces&.find_by(id: space_id)&.id&.to_s
      end
      move["mode"] = scope == "following" ? "series" : "single"
      move["per_date"] = fields[:per_date].to_h if fields.key?(:per_date)
      also = ActiveModel::Type::Boolean.new.cast(move["linked"]) ? linked_for(org_shows(ids)).map(&:id) : []
      @change.update!(scope: scope, show_ids: ids, also_show_ids: also, move: move)
      return redirect_to(manage_date_change_when_path(@change)) if refreshing?

      dests = ShowChangePlan::Moves.destinations(@change)
      if dests.none?(&:moves?)
        return redirect_to(manage_date_change_when_path(@change), alert: "Choose a new date, time, or place. Nothing would move yet.")
      end

      redirect_to manage_date_change_touches_path(@change)
    end

    # The live check under Where does it go?, redrawn as the fields change.
    def check
      load_when_step
      render partial: "manage/date_changes/check", locals: { change: @change, dests: @dests, plan: @plan }
    end

    # Step 3: everything it touches, with a default for each.
    def touches
      @plan = ShowChangePlan.new(@change)
      if @change.move?
        @dests = ShowChangePlan::Moves.destinations(@change)
        moving = @dests.select(&:moves?)
        @cast_conflicts = moving.reject(&:linked_to).flat_map { |d| ShowChangePlan::Moves.cast_conflicts(d, @change) }.uniq { |c| c.person.id }
        @staff_conflicts = moving.flat_map do |dest|
          lines = @plan.staff.changing.select do |line|
            line.shift.covered_shows.map(&:id).include?(dest.show.id) ||
              (line.shift.source.nil? && line.shift.starts_at.to_date == dest.was_starts.to_date)
          end
          ShowChangePlan::Moves.staff_conflicts(dest, @change, lines)
        end.uniq { |c| [ c.shift.id, c.person.id ] }
      end
      @previews = preview_notices
      render :contract_move if @change.move? && @change.contract_id
    end

    def save_touches
      choices = (@change.choices || {}).merge(choice_params)
      @change.update!(choices: choices)
      if @change.contract_id && params[:move].present?
        move = (@change.move || {}).merge(params.require(:move).permit(:what, :date, :rental_starts, :rental_ends, :own_times, :show_starts, :show_ends, :location_space_id).to_h)
        move["mode"] = "contract"
        @change.update!(move: move)
        error = ShowChangePlan::Moves.contract_error(@change.main_shows.first, move)
        return redirect_to(manage_date_change_touches_path(@change), alert: error) if error
        return redirect_to(manage_date_change_touches_path(@change)) if refreshing?
      end
      return redirect_to(manage_date_change_touches_path(@change)) if refreshing?

      redirect_to manage_date_change_review_path(@change)
    end

    # Step 4: every action in a sentence, every message, one button.
    def review
      @plan = ShowChangePlan.new(@change)
      @dests = ShowChangePlan::Moves.destinations(@change) if @change.move?
      @review = ShowChangePlan::Review.new(@change, @plan, dests: @dests, previews: preview_notices)
    end

    def apply
      @change.update!(choices: (@change.choices || {}).merge(choice_params)) if params[:choices].present?
      @change.update!(status: "applying", applied_at: Time.current, created_by_user: Current.user,
                      steps: ShowChangePlan::Review.new(@change, ShowChangePlan.new(@change)).planned_steps)
      DateChangeApplyJob.perform_later(@change.id, Current.user.id)
      redirect_to manage_date_change_path(@change)
    end

    # The record: what was done, who was notified, what couldn't be done.
    def show
      return redirect_to(next_step_path(@change)) if @change.draft?

      @shows = @change.shows
    end

    def progress
      render partial: "manage/date_changes/progress", locals: { change: @change }
    end

    # A failed refund tried again, or a problem marked as dealt with.
    def retry_problem
      problem = @change.open_problems.find { |p| p["key"] == params[:key] }
      return redirect_to(manage_date_change_path(@change), alert: "That's already been dealt with.") unless problem

      order = TicketOrder.where(organization: Current.organization).find_by(id: problem["order_id"])
      begin
        refund = TicketOrderRefund.issue!(order, by: Current.user, reason: "Date canceled", notify: true, outside_policy: true, reprice: false)
        @change.resolve_problem!(problem["key"], status: "resolved", by: Current.user)
        redirect_to manage_date_change_path(@change), notice: "#{order.buyer_name.presence || 'The buyer'} was refunded #{ShowChangePlan::BuyerWords.money(refund.amount_cents)}.", status: :see_other
      rescue StandardError => e
        redirect_to manage_date_change_path(@change), alert: "It still didn't go through: #{e.message}", status: :see_other
      end
    end

    def resolve_problem
      problem = @change.open_problems.find { |p| p["key"] == params[:key] }
      return redirect_to(manage_date_change_path(@change), status: :see_other) unless problem

      if problem["kind"] == "refund" && (order = TicketOrder.where(organization: Current.organization).find_by(id: problem["order_id"]))
        # Refunded another way: the books say so, and nothing more is sent.
        order.update!(status: "refunded") if order.paid?
      end
      @change.resolve_problem!(problem["key"], status: (problem["kind"] == "untold" ? "told" : "resolved"), by: Current.user)
      redirect_to manage_date_change_path(@change), status: :see_other
    end

    # Bring a canceled date back: which dates, and what comes back with them.
    def new_restore
      unless @show.canceled?
        return redirect_to manage_show_path(@production, @show), notice: "That date isn't canceled."
      end

      cancel = Current.organization.date_changes.applied.where(kind: "cancel")
                      .where("show_ids @> ? OR also_show_ids @> ?", [ @show.id ].to_json, [ @show.id ].to_json).order(:created_at).last
      @change = build_change("restore")
      @change.restores = cancel
      @change.scope = "this"
      @change.show_ids = [ @show.id ]
      @change.save!
      redirect_to manage_date_change_restore_path(@change)
    end

    def restore
      return redirect_to(manage_date_change_path(@change)) unless @change.draft?

      @cancel = @change.restores
      @all_ids = @cancel ? @cancel.still_canceled_shows.map(&:id) : [ @change.show_id ]
      if params[:dates].present?
        ids = params[:dates] == "all" ? @all_ids : [ @change.show_id ]
        @change.update!(show_ids: ids, also_show_ids: [], scope: (params[:dates] == "all" ? "chosen" : "this"))
      end
      @plan = ShowChangePlan.new(@change)
    end

    def apply_restore
      return redirect_to(manage_date_change_path(@change)) unless @change.draft?

      ids = params[:dates] == "all" && @change.restores ? @change.restores.still_canceled_shows.map(&:id) : [ @change.show_id ]
      @change.update!(show_ids: ids, choices: (@change.choices || {}).merge(choice_params))
      apply
    end

    # A date entered by mistake: gone, as if never entered.
    def destroy_dates
      shows = case params[:scope]
      when "following" then ShowChangePlan::Dates.following(@show)
      when "all" then ShowChangePlan::Dates.series(@show).reject { |s| s.date_and_time < Time.current && s.id != @show.id }
      else [ @show ]
      end
      blockers = ShowChangePlan::Delete.blockers(shows)
      if blockers.any?
        return redirect_to manage_new_date_change_path(@production, @show, kind: "cancel"),
                           alert: "#{shows.one? ? 'This date' : 'These dates'} can't be deleted: #{blockers.to_sentence}. Cancel #{shows.one? ? 'it' : 'them'} instead."
      end

      label = shows.one? ? @show.date_and_time.strftime("%A, %B %-d") : "#{shows.size} dates"
      ShowChangePlan::Delete.delete!(shows)
      redirect_to manage_production_shows_path(@production), notice: "#{label} #{shows.one? ? 'is' : 'are'} deleted.", status: :see_other
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey => e
      redirect_to manage_new_date_change_path(@production, @show), alert: "That couldn't be deleted: #{e.message.truncate(160)}. Cancel it instead."
    end

    # A contract date's move: its own page (the rental, and the show's own
    # times inside it), then Review. A contractor's request fills it in.
    def new_contract_move
      rental = @show.space_rental
      return redirect_to(manage_new_date_change_path(@production, @show, kind: "move")) unless rental

      request = ContractDateRequest.where(contract_id: rental.contract_id, show_id: @show.id, kind: "move", status: ContractDateRequest::WAITING)
                                   .find_by(id: params[:request_id]) ||
                ContractDateRequest.where(contract_id: rental.contract_id, show_id: @show.id, kind: "move", status: ContractDateRequest::WAITING).order(:created_at).last
      change = build_change("move")
      change.contract = rental.contract
      change.contract_date_request = request
      change.scope = "this"
      change.show_ids = [ @show.id ]
      change.move = contract_move_defaults(@show, rental, request)
      change.save!
      redirect_to manage_date_change_touches_path(change)
    end

    private

    # A choice changed and the page redraws in place (auto-submit sends no
    # button); Continue says commit.
    def refreshing? = params[:commit].blank?

    def set_show_from_path
      @production = Current.organization.productions.find(params[:production_id]) if params[:production_id]
      if params[:contract_id]
        contract = Current.organization.contracts.find(params[:contract_id])
        @show = Show.where(space_rental_id: contract.space_rentals.select(:id)).find(params[:show_id])
        @production = @show.production
      else
        @show = @production.shows.find(params[:show_id])
      end
      sync_current_production(@production) if respond_to?(:sync_current_production, true)
    end

    def set_change
      @change = Current.organization.date_changes.find(params[:id])
      @show = @change.show
      @production = @change.production || @show&.production
      redirect_to(manage_path, alert: "That date is gone.") unless @production
    end

    def require_draft
      redirect_to manage_date_change_path(@change) unless @change.draft?
    end

    def build_change(kind)
      Current.organization.date_changes.new(kind: kind, show: @show, production: @production, created_by_user: Current.user)
    end

    def org_shows(ids)
      Show.joins(:production).where(productions: { organization_id: Current.organization.id }, id: ids)
          .includes(:production, :location, event_linkage: :shows).order(:date_and_time).to_a
    end

    def chosen_ids
      ids = Array(params[:show_ids]).map(&:to_i)
      org_shows(ids).reject(&:canceled?).map(&:id)
    end

    def linked_for(shows)
      ShowChangePlan::Dates.ties(shows, Current.organization).select { |t| t.key.start_with?("linked") }.flat_map(&:shows)
    end

    def default_ties(shows, kind)
      ties = ShowChangePlan::Dates.ties(shows, Current.organization)
      ties = ties.select { |t| t.key.start_with?("linked") } if kind == "move"
      ties.select(&:default).flat_map(&:shows).map(&:id)
    end

    def choice_params
      raw = params.fetch(:choices, {})
      permitted = raw.permit(*CHOICE_KEYS, cast_conflicts: {}, staff_conflicts: {}, add_shifts: {}).to_h
      raw.each_key do |key|
        permitted[key] = raw[key] if key.to_s.match?(/\A(cast_conflict_reason_\d+|staff_conflict_reason_\d+-\d+)\z/)
      end
      permitted
    end

    def load_dates_step
      @plan = ShowChangePlan.new(@change)
      @series = ShowChangePlan::Dates.series(@change.show)
      @following = ShowChangePlan::Dates.following(@change.show)
      @past = ShowChangePlan::Dates.past_in_series(@change.show)
      @choosable = @change.scope == "chosen" ? ShowChangePlan::Dates.choosable(@change.show, Current.organization) : []
      @main = @change.main_shows
      @facts = ShowChangePlan::Dates.facts(@main + @change.also_shows)
      @ties = ShowChangePlan::Dates.ties(@main, Current.organization)
    end

    def load_when_step
      @plan = ShowChangePlan.new(@change)
      @following = ShowChangePlan::Dates.following(@change.show)
      @dests = ShowChangePlan::Moves.destinations(@change)
      @locations = Current.organization.locations.includes(:location_spaces).order(:name)
      @linked = linked_for([ @change.show ])
    end

    # The cast and staff messages as they'll go, built from the change
    # before it happens.
    def preview_notices
      kind = @change.cancel? ? "canceled" : "moved"
      off = @change.cancel? ? @plan.acting_ids : []
      dests = @change.move? ? ShowChangePlan::Moves.destinations(@change).index_by { |d| d.show.id } : {}
      changes = @plan.acting_shows.filter_map do |show|
        dest = dests[show.id]
        next if @change.move? && !dest&.moves?

        staff = ShowChanges.staff_entries(ShowChanges.shifts_for(show, kind, off_ids: off))
        cast = ShowChanges.cast_entries(show)
        next if cast.empty? && staff.empty?

        ShowChange.new(organization: Current.organization, production: show.production, show: show, kind: kind, batch: "preview",
                       show_label: ShowChanges.label(show, show.date_and_time), cast: cast, staff: staff,
                       was_starts_at: show.date_and_time, was_ends_at: show.ends_at,
                       now_starts_at: dest&.now_starts, now_ends_at: dest&.now_ends)
      end
      ShowChangeNotices.new(Current.organization, changes)
    end

    def next_step_path(change)
      return manage_date_change_restore_path(change) if change.restore?
      return manage_date_change_touches_path(change) if change.contract_id

      change.move? ? manage_date_change_when_path(change) : manage_date_change_dates_path(change)
    end

    def contract_move_defaults(show, rental, request)
      at = request&.proposed_at
      date = (at || rental.starts_at).to_date
      own = rental.event_starts_at.present?
      starts = rental.starts_at
      offset = at ? at - rental.effective_event_starts_at : 0
      {
        "mode" => "contract", "what" => "night", "date" => date.iso8601,
        "rental_starts" => (starts + offset).strftime("%H:%M"), "rental_ends" => (rental.ends_at + offset).strftime("%H:%M"),
        "own_times" => own ? "1" : "0",
        "show_starts" => (rental.effective_event_starts_at + offset).strftime("%H:%M"),
        "show_ends" => (rental.effective_event_ends_at + offset).strftime("%H:%M"),
        "location_space_id" => rental.location_space_id.to_s
      }
    end
  end
end
