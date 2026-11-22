# frozen_string_literal: true

# Changing an organization's time zone (Tim, 2026-11-22). Times are stored as
# moments, and every organization started on Central, so one in California
# that entered "8:00 PM" for years stored 8:00 PM Central. Switching it to
# Pacific would make all of those read 6:00 PM. Keeping the clock moves each
# time the organization entered so its clock reading stays the same in the new
# zone (8:00 PM stays 8:00 PM), date by date, so daylight saving comes out
# right. Keeping the moment changes only the zone and leaves every time where
# it is.
#
# Only times someone entered as a clock reading move: dates and calls, bookings,
# shifts, auditions, sign-up, course and ticket sale windows, and the snapshots
# of what people were notified of, which move with them so shift and order
# notices don't see a change that didn't happen. Things that happened at a
# moment (sent, paid, signed) never move. Rows are written directly, so no
# callbacks run and nobody is notified.
class OrganizationTimeZoneChange
  Target = Data.define(:label, :scope, :columns)

  def self.targets(organization)
    org = organization.id
    productions = Production.where(organization_id: org).select(:id)
    listings = TicketListing.where(organization_id: org).select(:id)
    [
      Target.new("Dates", Show.where(production_id: productions), %w[date_and_time call_time]),
      Target.new("Bookings", SpaceRental.where(location_id: Location.where(organization_id: org).select(:id)),
                 %w[starts_at ends_at event_starts_at event_ends_at]),
      Target.new("Shifts", Shift.where(organization_id: org), %w[starts_at ends_at]),
      Target.new("Shift notices", ShiftAssignment.where(shift_id: Shift.where(organization_id: org).select(:id)), %w[told_starts_at told_ends_at]),
      Target.new("Shift notices", StaffScheduleRemoval.where(organization_id: org), %w[shift_starts_at shift_ends_at]),
      Target.new("Tip shares", TipShare.where(settlement_day_id: SettlementDay.where(organization_id: org).select(:id)), %w[worked_from worked_to]),
      Target.new("Auditions", AuditionCycle.where(production_id: productions), %w[opens_at closes_at]),
      Target.new("Auditions", AuditionSession.where(audition_cycle_id: AuditionCycle.where(production_id: productions).select(:id)), %w[start_at end_at]),
      Target.new("Courses", CourseOffering.where(production_id: productions), %w[opens_at closes_at early_bird_deadline delivery_scheduled_at]),
      Target.new("Sign-ups", SignUpForm.where(production_id: productions), %w[opens_at closes_at]),
      Target.new("Sign-ups", SignUpFormInstance.where(sign_up_form_id: SignUpForm.where(production_id: productions).select(:id)), %w[opens_at closes_at edit_cutoff_at]),
      Target.new("Ticket sales", TicketListing.where(organization_id: org), %w[on_sale_at off_sale_at]),
      Target.new("Ticket sales", TicketTier.where(ticket_listing_id: listings)
                                           .or(TicketTier.where(production_ticketing_id: ProductionTicketing.where(organization_id: org).select(:id))),
                 %w[sales_start_at sales_end_at]),
      Target.new("Ticket sales", TicketPass.where(organization_id: org), %w[sales_start_at sales_end_at]),
      Target.new("Ticket sales", TicketDiscountCode.where(organization_id: org), %w[starts_at ends_at]),
      Target.new("Ticket sales", TicketOffer.where(organization_id: org), %w[starts_at ends_at]),
      Target.new("Order notices", TicketOrder.where(organization_id: org), %w[told_starts_at]),
      Target.new("Date changes", ShowChange.where(organization_id: org), %w[was_starts_at was_ends_at now_starts_at now_ends_at]),
      Target.new("Date requests", ContractDateRequest.where(organization_id: org), %w[original_at proposed_at])
    ]
  end

  # What keeping the clock would move: { label => count of rows }, and one
  # upcoming date as an example of how it reads now and after.
  def self.preview(organization, to:)
    from = ActiveSupport::TimeZone[organization.time_zone]
    counts = Hash.new(0)
    targets(organization).each do |target|
      counts[target.label] += target.scope.where(target.columns.map { |c| "#{c} IS NOT NULL" }.join(" OR ")).count
    end
    show = targets(organization).first.scope.where("date_and_time >= ?", Time.current).order(:date_and_time).first
    example = show && { name: show.production&.name, moment: show.date_and_time,
                        kept_clock: shift(show.date_and_time, from, ActiveSupport::TimeZone[to]) }
    { counts: counts.reject { |_, n| n.zero? }, example: example }
  end

  # keep: :clock (move every entered time so it reads the same in the new
  # zone) or :moment (change only the zone).
  def self.apply!(organization, to:, keep:)
    from = ActiveSupport::TimeZone[organization.time_zone]
    zone = ActiveSupport::TimeZone[to]
    raise ArgumentError, "unknown time zone" unless zone
    return organization.update!(time_zone: to) if keep.to_s == "moment" || from.name == zone.name

    Organization.transaction do
      targets(organization).each do |target|
        target.scope.in_batches(of: 500) do |batch|
          batch.pluck(:id, *target.columns).each do |id, *values|
            changes = target.columns.zip(values).each_with_object({}) do |(column, value), moved|
              moved[column] = shift(value, from, zone) if value
            end
            target.scope.model.where(id: id).update_all(changes) if changes.any?
          end
        end
      end
      organization.update!(time_zone: to)
    end
  end

  # The same clock reading, from one zone to another, on its own date.
  def self.shift(moment, from, to)
    local = moment.in_time_zone(from)
    to.local(local.year, local.month, local.day, local.hour, local.min, local.sec)
  end
end
