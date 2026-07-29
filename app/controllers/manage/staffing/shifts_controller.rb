# frozen_string_literal: true

module Manage
  module Staffing
    class ShiftsController < Manage::ManageController
      before_action :ensure_org_owner_or_manager
      before_action :set_shift, only: %i[update destroy assign unassign split merge merge_with_next acknowledge_gap unacknowledge_gap]

      def create
        attrs = shift_params
        @shift = Current.organization.shifts.new(sanitize_roles(attrs, attrs[:house_role_id]))
        if @shift.save
          flash[:notice] = "Shift added."
        else
          flash[:alert] = "Couldn't add shift: #{@shift.errors.full_messages.to_sentence}"
        end
        redirect_back_or_to manage_staffing_scheduling_path
      rescue ActiveRecord::RecordNotUnique
        redirect_back_or_to manage_staffing_scheduling_path, alert: "There's already a shift for this role at that time."
      end

      def update
        if @shift.update(sanitize_roles(shift_params, @shift.house_role_id))
          flash[:notice] = "Shift updated."
        else
          flash[:alert] = "Couldn't update shift: #{@shift.errors.full_messages.to_sentence}"
        end
        redirect_back_or_to manage_staffing_scheduling_path
      rescue ActiveRecord::RecordNotUnique
        redirect_back_or_to manage_staffing_scheduling_path, alert: "There's already a shift for this role at that time."
      end

      def destroy
        @shift.shift_assignments.each { |a| record_removal_if_notified(a) }
        @shift.destroy!
        redirect_back_or_to manage_staffing_scheduling_path, notice: "Shift removed."
      end

      def assign
        person_id = params[:person_id].to_i
        person = Current.organization.people.find_by(id: person_id)
        unless person
          redirect_back_or_to(manage_staffing_scheduling_path, alert: "Person not found in this organization.") and return
        end
        # Only allow assigning if the person is on staff and qualified for the role.
        member = OrganizationStaffMember.active.find_by(organization: Current.organization, person: person)
        unless member && member.house_role_ids.include?(@shift.house_role_id)
          redirect_back_or_to(manage_staffing_scheduling_path, alert: "That person isn't on staff or isn't qualified for this role.") and return
        end

        next_position = (@shift.shift_assignments.maximum(:position) || 0) + 1
        assignment = @shift.shift_assignments.new(person: person, position: next_position)
        if assignment.save
          redirect_back_or_to manage_staffing_scheduling_path, notice: "Assigned #{person.name}."
        else
          redirect_back_or_to manage_staffing_scheduling_path,
                              alert: assignment.errors.full_messages.to_sentence.presence || "Couldn't assign."
        end
      end

      def unassign
        assignment = @shift.shift_assignments.find_by(person_id: params[:person_id])
        if assignment
          name = assignment.person.name
          record_removal_if_notified(assignment)
          assignment.destroy!
          redirect_back_or_to manage_staffing_scheduling_path, notice: "Removed #{name} from this shift."
        else
          redirect_back_or_to manage_staffing_scheduling_path, alert: "Assignment not found."
        end
      end

      # Split a shift into N segments. The Split modal sends params[:segments]
      # as an array of { starts_at, ends_at } pairs. The first segment replaces
      # the original (so existing assignments stay on it); subsequent segments
      # are created as new shifts. If no segments are sent (e.g. a future
      # programmatic caller), falls back to splitting in half at the midpoint.
      # Merge this shift with one or more chosen same-role shifts (shift_ids) into
      # a single shift spanning them all, absorbing everyone's assignments.
      def merge
        ids = Array(params[:shift_ids]).map(&:to_i).reject(&:zero?)
        others = Current.organization.shifts
          .where(id: ids, house_role_id: @shift.house_role_id)
          .where.not(id: @shift.id)
          .to_a
        if others.empty?
          redirect_back_or_to(manage_staffing_scheduling_path, alert: "Pick at least one shift to merge.") and return
        end

        all_shifts = [ @shift ] + others
        new_start = all_shifts.map(&:starts_at).min
        new_end   = all_shifts.map(&:ends_at).max
        # The shows the merged shift will cover (its own source + all the others).
        extra_shows = all_shifts.flat_map(&:covered_shows).uniq.reject { |s| s == @shift.source }

        ActiveRecord::Base.transaction do
          seen = @shift.shift_assignments.pluck(:person_id).to_set
          pos = @shift.shift_assignments.maximum(:position) || 0
          others.each do |o|
            o.shift_assignments.order(:position).each do |a|
              next if seen.include?(a.person_id)
              seen << a.person_id
              pos += 1
              @shift.shift_assignments.create!(person_id: a.person_id, position: pos,
                                               notified_at: a.notified_at, accepted_at: a.accepted_at, declined_at: a.declined_at)
            end
          end
          @shift.update!(starts_at: new_start, ends_at: new_end)
          others.each(&:destroy!)
          @shift.shows = extra_shows if extra_shows.any?
        end
        redirect_back_or_to manage_staffing_scheduling_path, notice: "Merged #{all_shifts.size} shifts."
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        redirect_back_or_to manage_staffing_scheduling_path, alert: "Couldn't merge: #{e.message}"
      end

      def split
        return split_into_shows if params[:by_show].present?

        segments = parse_segments(params[:segments])

        if segments.size < 2
          # Fallback: split in half at the midpoint
          midpoint = @shift.starts_at + ((@shift.ends_at - @shift.starts_at) / 2)
          segments = [
            { starts_at: @shift.starts_at, ends_at: midpoint },
            { starts_at: midpoint, ends_at: @shift.ends_at }
          ]
        end

        segments.each do |seg|
          if seg[:ends_at] <= seg[:starts_at]
            redirect_back_or_to(manage_staffing_scheduling_path, alert: "Each segment must end after it starts.") and return
          end
        end

        ActiveRecord::Base.transaction do
          @shift.update!(starts_at: segments.first[:starts_at], ends_at: segments.first[:ends_at])
          segments[1..].each do |seg|
            Current.organization.shifts.create!(
              house_role_id: @shift.house_role_id,
              source_type: @shift.source_type,
              source_id: @shift.source_id,
              starts_at: seg[:starts_at],
              ends_at: seg[:ends_at],
              required_count: @shift.required_count,
              coverage_mode: @shift.coverage_mode,
              renter_name: @shift.renter_name,
              notes: @shift.notes
            )
          end
        end
        redirect_back_or_to manage_staffing_scheduling_path,
                            notice: "Split into #{segments.size} shifts."
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        redirect_back_or_to manage_staffing_scheduling_path, alert: "Couldn't split: #{e.message}"
      end

      # Merge with the adjacent same-role shift that starts at this one's end.
      # Combines assignments (dedup by person), then deletes the second shift.
      def merge_with_next
        # The next same-role shift that begins where this one ends — regardless of
        # which show each is anchored to (adjacent shifts for different shows are
        # exactly what we want to combine).
        next_shift = Current.organization.shifts
          .where(house_role_id: @shift.house_role_id)
          .where(starts_at: @shift.ends_at)
          .where.not(id: @shift.id)
          .order(:starts_at)
          .first

        unless next_shift
          redirect_back_or_to(manage_staffing_scheduling_path, alert: "No adjacent shift to merge with.") and return
        end

        ActiveRecord::Base.transaction do
          existing_person_ids = @shift.shift_assignments.pluck(:person_id)
          next_position = (@shift.shift_assignments.maximum(:position) || 0)
          next_shift.shift_assignments.order(:position).each do |a|
            next if existing_person_ids.include?(a.person_id)
            next_position += 1
            @shift.shift_assignments.create!(person_id: a.person_id, position: next_position,
                                             notified_at: a.notified_at, accepted_at: a.accepted_at, declined_at: a.declined_at)
          end
          @shift.update!(ends_at: [ next_shift.ends_at, @shift.ends_at ].max)
          next_shift.destroy!
        end
        redirect_back_or_to manage_staffing_scheduling_path, notice: "Shifts merged."
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        redirect_back_or_to manage_staffing_scheduling_path, alert: "Couldn't merge: #{e.message}"
      end

      # Mark the gap between this shift and the next same-role shift as intentional.
      # We store the next shift's starts_at; if the schedule shifts, the stored value
      # no longer matches and the warning reappears automatically.
      def acknowledge_gap
        next_starts_at = Time.zone.parse(params[:next_starts_at].to_s)
        if next_starts_at.nil? || next_starts_at <= @shift.ends_at
          redirect_back_or_to(manage_staffing_scheduling_path, alert: "Couldn't acknowledge gap.") and return
        end
        @shift.update!(gap_after_acknowledged_until: next_starts_at)
        redirect_back_or_to manage_staffing_scheduling_path, notice: "Gap marked OK."
      end

      def unacknowledge_gap
        @shift.update!(gap_after_acknowledged_until: nil)
        redirect_back_or_to manage_staffing_scheduling_path, notice: "Gap warning restored."
      end

      private

      # Split a merged show-based shift back into one shift per show it covers —
      # each anchored to its show with that show's hours. The first show's shift
      # reuses this record (so existing assignments stay on it); the rest are new,
      # empty shifts to staff per show.
      def split_into_shows
        shows = @shift.covered_shows
        if shows.size < 2
          redirect_back_or_to(manage_staffing_scheduling_path, alert: "This shift only covers one show.") and return
        end

        ActiveRecord::Base.transaction do
          first = shows.first
          @shift.update!(source: first, starts_at: first.date_and_time, ends_at: first.ends_at)
          @shift.shift_shows.destroy_all # back to a single-show shift
          shows[1..].each do |show|
            Current.organization.shifts.create!(
              house_role_id: @shift.house_role_id,
              source: show,
              starts_at: show.date_and_time,
              ends_at: show.ends_at,
              required_count: @shift.required_count,
              coverage_mode: @shift.coverage_mode,
              renter_name: @shift.renter_name,
              notes: @shift.notes
            )
          end
        end
        redirect_back_or_to manage_staffing_scheduling_path, notice: "Split into #{shows.size} per-show shifts."
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        redirect_back_or_to manage_staffing_scheduling_path, alert: "Couldn't split: #{e.message}"
      end

      # If this assignment was already notified to the person, log a pending
      # "shift removed" notice so the next targeted Notify updates tells them.
      def record_removal_if_notified(assignment)
        return if assignment.notified_at.nil?

        shift = assignment.shift
        location = shift.house_role.location&.name || shift.source.try(:location).try(:name)
        Current.organization.staff_schedule_removals.create!(
          person_id: assignment.person_id,
          shift_starts_at: shift.starts_at,
          shift_label: shift.role_label,
          location_name: location
        )
      end

      def set_shift
        @shift = Current.organization.shifts.find(params[:id])
      end

      def shift_params
        params.require(:shift).permit(
          :house_role_id, :starts_at, :ends_at, :required_count,
          :coverage_mode, :renter_name, :notes, :source_type, :source_id,
          additional_role_ids: []
        )
      end

      # Clean the "also covers" set: ints, no blanks, no dups, and never the
      # primary role itself (the UI disables it; this is the server backstop).
      def sanitize_roles(attrs, primary_id)
        return attrs unless attrs.key?(:additional_role_ids)
        ids = Array(attrs[:additional_role_ids]).map(&:to_s).reject(&:blank?).map(&:to_i).uniq
        ids.delete(primary_id.to_i) if primary_id
        attrs.merge(additional_role_ids: ids)
      end

      # Coerce the segments param into [{ starts_at: Time, ends_at: Time }, ...].
      # Rejects anything unparseable so split fails cleanly instead of crashing.
      def parse_segments(raw)
        return [] unless raw.is_a?(Array) || raw.respond_to?(:to_unsafe_h)
        list = raw.is_a?(Array) ? raw : raw.values
        list.map { |seg|
          begin
            { starts_at: Time.zone.parse(seg[:starts_at] || seg["starts_at"]),
              ends_at:   Time.zone.parse(seg[:ends_at]   || seg["ends_at"]) }
          rescue ArgumentError, TypeError
            nil
          end
        }.compact
      end
    end
  end
end
