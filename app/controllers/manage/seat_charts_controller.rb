# frozen_string_literal: true

module Manage
  # Seat charts (advanced ticketing plan §1): drawn for one room from
  # Ticketing → Settings → Rooms and seating. A chart is built from sections
  # (rows of seats, tables, a standing area); each seat can be marked a
  # wheelchair space, a companion seat or restricted view, or killed. Active
  # charts are the ones productions and dates pick from.
  class SeatChartsController < Manage::TicketingBaseController
    before_action :set_chart, except: %i[new create]

    def new
      @room = org_rooms.find(params[:room_id])
      @chart = SeatChart.new(location_space: @room, name: "#{@room.name} seating")
    end

    def create
      @room = org_rooms.find(params.dig(:seat_chart, :location_space_id))
      @chart = Current.organization.seat_charts.new(location_space: @room, name: params.dig(:seat_chart, :name).to_s.squish.presence || "#{@room.name} seating")
      if @chart.save
        redirect_to manage_seat_chart_path(@chart), notice: "#{@chart.name} is started. Add its rows, tables and standing areas."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show
      @sections = @chart.sections.includes(:seats).to_a
      @payload = Ticketing::ChartPayload.for(@chart)
      @tiers_using = TicketTier.joins(:zones).where(ticket_tier_zones: { seat_section_id: @sections.map(&:id) }).distinct.count
    end

    def update
      attrs = params.require(:seat_chart).permit(:name)
      if @chart.update(attrs)
        redirect_to manage_seat_chart_path(@chart), notice: "Saved."
      else
        redirect_to manage_seat_chart_path(@chart), alert: @chart.errors.full_messages.to_sentence
      end
    end

    # Draft → active (productions can pick it), active → archived (they
    # can't any more; dates already on it keep selling), archived → active.
    def change_status
      to = params[:status].to_s
      return redirect_to(manage_seat_chart_path(@chart), alert: "That can't be done.") unless to.in?(SeatChart::STATUSES)
      return redirect_to(manage_seat_chart_path(@chart), alert: "Add at least one seat or standing area first.") if to == "active" && @chart.seat_count.zero? && @chart.standing_capacity.zero?

      @chart.update!(status: to)
      redirect_to manage_seat_chart_path(@chart), notice: { "active" => "#{@chart.name} is active: productions and dates can sell from it.", "archived" => "#{@chart.name} is archived.", "draft" => "Back to a draft." }[to]
    end

    def destroy
      return redirect_to(manage_seat_chart_path(@chart), alert: "This chart is in use; archive it instead.") if @chart.in_use?

      room = @chart.location_space
      RoomTicketingSetting.where(default_seat_chart_id: @chart.id).update_all(default_seat_chart_id: nil)
      @chart.destroy!
      redirect_to manage_ticketing_settings_path(section: "rooms"), notice: "#{@chart.name} is gone; #{room.name} has no chart."
    end

    # A section of rows ("Orchestra: 12 rows of 20 from A"), tables ("6 tables of 8") or a standing area.
    def add_section
      p = params.require(:seat_section).permit(:name, :kind, :rows, :per_row, :first_row, :first_number, :standing_capacity, :best_order)
      section = @chart.sections.new(name: p[:name].to_s.squish.presence || default_section_name(p[:kind]), kind: p[:kind].presence || "rows",
                                    standing_capacity: p[:standing_capacity].to_i, best_order: p[:best_order].presence || "center",
                                    position: (@chart.sections.maximum(:position) || 0) + 1)
      section.standing_capacity = 0 unless section.standing?
      return redirect_to(manage_seat_chart_path(@chart), alert: section.errors.full_messages.to_sentence) unless section.save

      if section.standing?
        @chart.relayout!
      else
        section.add_rows!(count: p[:rows], per_row: p[:per_row], first_row: (p[:first_row].presence || (section.kind == "tables" ? "T1" : "A")), first_number: (p[:first_number].presence || 1))
      end
      redirect_to manage_seat_chart_path(@chart), notice: "Added #{section.name}: #{section.standing? ? "standing room for #{section.standing_capacity}" : helpers.pluralize(section.live_seat_count, 'seat')}."
    end

    def update_section
      section = @chart.sections.find(params[:section_id])
      attrs = params.require(:seat_section).permit(:name, :standing_capacity, :best_order)
      attrs.delete(:standing_capacity) unless section.standing?
      if section.update(attrs)
        @chart.relayout! if attrs.key?(:best_order)
        redirect_to manage_seat_chart_path(@chart), notice: "Saved #{section.name}."
      else
        redirect_to manage_seat_chart_path(@chart), alert: section.errors.full_messages.to_sentence
      end
    end

    # More rows on a section that has some.
    def add_rows
      section = @chart.sections.find(params[:section_id])
      return redirect_to(manage_seat_chart_path(@chart), alert: "A standing area has no rows.") if section.standing?

      p = params.permit(:rows, :per_row, :first_row, :first_number)
      made = section.add_rows!(count: p[:rows], per_row: p[:per_row], first_row: p[:first_row].presence || section.rows.last&.first.to_s.succ.presence || "A", first_number: p[:first_number].presence || 1)
      redirect_to manage_seat_chart_path(@chart), notice: "Added #{helpers.pluralize(made.size, 'seat')} to #{section.name}."
    end

    def remove_section
      section = @chart.sections.find(params[:section_id])
      if Ticket.where(seat_section_id: section.id).exists?
        return redirect_to(manage_seat_chart_path(@chart), alert: "#{section.name} has tickets on it; kill its seats instead of removing it.")
      end

      section.destroy!
      @chart.relayout!
      redirect_to manage_seat_chart_path(@chart), notice: "Removed #{section.name}."
    end

    # Mark the ticked seats: a kind, killed or not, a note. From the editor's
    # selection; seat_ids[] + what to do.
    def update_seats
      seats = Seat.where(id: Array(params[:seat_ids]).map(&:to_i), seat_section_id: @chart.sections.select(:id))
      return redirect_to(manage_seat_chart_path(@chart), alert: "Tap some seats first.") if seats.empty?

      change = {}
      change[:kind] = params[:kind] if params[:kind].to_s.in?(Seat::KINDS)
      change[:killed] = params[:killed] == "1" if params.key?(:killed)
      change[:note] = params[:note].to_s.strip.first(120).presence if params.key?(:note)
      seats.update_all(change.merge(updated_at: Time.current)) if change.any?
      what = change[:kind] ? Seat::KIND_LABELS[change[:kind]].downcase : (change.key?(:killed) ? (change[:killed] ? "killed" : "back on sale") : "noted")
      redirect_to manage_seat_chart_path(@chart), notice: "#{helpers.pluralize(seats.size, 'seat')} #{what}."
    end

    private

    def set_chart
      @chart = Current.organization.seat_charts.includes(:location_space).find(params[:id])
    end

    def org_rooms
      LocationSpace.joins(:location).where(locations: { organization_id: Current.organization.id })
    end

    def default_section_name(kind)
      { "tables" => "Tables", "standing" => "Standing" }.fetch(kind.to_s, "Seats")
    end
  end
end
