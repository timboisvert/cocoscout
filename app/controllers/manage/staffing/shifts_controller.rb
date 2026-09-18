# frozen_string_literal: true

module Manage
  module Staffing
    class ShiftsController < Manage::ManageController
      include Manage::SchedulingReturn

      before_action :ensure_org_owner_or_manager
      before_action :set_shift, only: %i[update destroy assign unassign split merge merge_with_next]

      def create
        @shift = Current.organization.shifts.new(shift_params)
        attach_extra_shows
        saved = ActiveRecord::Base.transaction do
          @shift.save && (apply_additional_roles || true)
        end
        if saved
          assigned_note = assign_initial_person
          redirect_to_scheduling notice: [ "Shift added.", assigned_note ].compact.join(" ")
        else
          redirect_to_scheduling alert: "Couldn't add shift: #{@shift.errors.full_messages.to_sentence}"
        end
      rescue ActiveRecord::RecordNotUnique
        redirect_to_scheduling alert: "There's already a shift for this role at that time."
      rescue ActiveRecord::RecordInvalid => e
        redirect_to_scheduling alert: "Couldn't add shift: #{e.record.errors.full_messages.to_sentence}"
      end

      def update
        saved = ActiveRecord::Base.transaction do
          @shift.update(shift_params) && (apply_additional_roles || true)
        end
        if saved
          redirect_to_scheduling notice: "Shift updated."
        else
          redirect_to_scheduling alert: "Couldn't update shift: #{@shift.errors.full_messages.to_sentence}"
        end
      rescue ActiveRecord::RecordNotUnique
        redirect_to_scheduling alert: "There's already a shift for this role at that time."
      rescue ActiveRecord::RecordInvalid => e
        redirect_to_scheduling alert: "Couldn't update shift: #{e.record.errors.full_messages.to_sentence}"
      end

      def destroy
        @shift.shift_assignments.each { |a| record_removal_if_notified(a) }
        @shift.destroy!
        redirect_to_scheduling notice: "Shift removed."
      end

      def assign
        person_id = params[:person_id].to_i
        person = Current.organization.people.find_by(id: person_id)
        unless person
          redirect_to_scheduling(alert: "Person not found in this organization.") and return
        end
        # Only allow assigning if the person is on staff and qualified for the role.
        unless qualified_for_shift?(person, @shift)
          redirect_to_scheduling(alert: "That person isn't on staff or isn't qualified for this role.") and return
        end

        next_position = (@shift.shift_assignments.maximum(:position) || 0) + 1
        assignment = @shift.shift_assignments.new(person: person, position: next_position)
        if assignment.save
          redirect_to_scheduling notice: "Assigned #{person.name}.#{availability_note(person, @shift)}"
        else
          redirect_to_scheduling alert: assignment.errors.full_messages.to_sentence.presence || "Couldn't assign."
        end
      end

      def unassign
        assignment = @shift.shift_assignments.find_by(person_id: params[:person_id])
        if assignment
          name = assignment.person.name
          record_removal_if_notified(assignment)
          assignment.destroy!
          redirect_to_scheduling notice: "Removed #{name} from this shift."
        else
          redirect_to_scheduling alert: "Assignment not found."
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
          redirect_to_scheduling(alert: "Pick at least one shift to merge.") and return
        end

        all_shifts = [ @shift ] + others
        new_start = all_shifts.map(&:starts_at).min
        new_end   = all_shifts.map(&:ends_at).max
        # The shows the merged shift will cover (its own source + all the others).
        extra_shows = all_shifts.flat_map(&:covered_shows).uniq.reject { |s| s == @shift.source }
        # Read before anything moves: each shift's extra roles, pinned to the
        # shows that shift covered. Otherwise a manager "also covers" on one
        # show's shift would spread to every show in the merge.
        role_ids, show_ids_by_role = merged_additional_roles(all_shifts)

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
          @shift.reload.assign_additional_roles!(role_ids, show_ids_by_role)
        end
        redirect_to_scheduling notice: "Merged #{all_shifts.size} shifts."
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        redirect_to_scheduling alert: "Couldn't merge: #{e.message}"
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
            redirect_to_scheduling(alert: "Each segment must end after it starts.") and return
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
        redirect_to_scheduling notice: "Split into #{segments.size} shifts."
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        redirect_to_scheduling alert: "Couldn't split: #{e.message}"
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
          redirect_to_scheduling(alert: "No adjacent shift to merge with.") and return
        end

        # Same bookkeeping as #merge. This used to drop the next shift's shows,
        # so the merged shift silently stopped covering them in Role Call — and
        # its extra roles went with it.
        extra_shows = [ @shift, next_shift ].flat_map(&:covered_shows).uniq.reject { |s| s == @shift.source }
        role_ids, show_ids_by_role = merged_additional_roles([ @shift, next_shift ])

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
          @shift.shows = extra_shows if extra_shows.any?
          @shift.reload.assign_additional_roles!(role_ids, show_ids_by_role)
        end
        redirect_to_scheduling notice: "Shifts merged."
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        redirect_to_scheduling alert: "Couldn't merge: #{e.message}"
      end

      private

      # Every action here goes back to the page the manager is already on, which
      # lets Turbo morph it in place instead of re-rendering. See
      # Manage::SchedulingReturn for why the URL has to match exactly.
      def redirect_to_scheduling(notice: nil, alert: nil)
        redirect_to scheduling_return_url, notice: notice, alert: alert
      end

      def qualified_for_shift?(person, shift)
        member = OrganizationStaffMember.active.find_by(organization: Current.organization, person: person)
        member.present? && member.house_role_ids.include?(shift.house_role_id)
      end

      # The add-shift modal can name a person to put straight onto the new
      # shift. Optional — an unassigned shift is perfectly valid — and guarded
      # by the same staff/qualification rule as assign.
      def assign_initial_person
        person_id = params[:person_id].to_i
        return nil if person_id.zero?

        person = Current.organization.people.find_by(id: person_id)
        return "Couldn't assign: person not found." unless person
        return "Couldn't assign #{person.name}: not on staff or not qualified for this role." unless qualified_for_shift?(person, @shift)

        @shift.shift_assignments.create!(person: person, position: 1)
        "Assigned #{person.name}.#{availability_note(person, @shift)}"
      rescue ActiveRecord::RecordInvalid => e
        "Couldn't assign #{person&.name}: #{e.message}"
      end

      # Assigning never refuses someone for what they said about their
      # availability — the manager may know better — but it doesn't stay quiet
      # about it either: " Note: Free from 8:30 PM, misses the first 1h 30m
      # (their usual Friday)."
      def availability_note(person, shift)
        verdict = StaffAvailabilityResolver.new([ person.id ], from: shift.starts_at.to_date, to: shift.ends_at.to_date)
                                           .verdict(person.id, shift.starts_at, shift.ends_at)
        verdict.flagged? ? " Note: #{StaffAvailabilityWording.detail(verdict)}" : ""
      end

      # Split a merged show-based shift back into one shift per show it covers —
      # each anchored to its show with that show's hours. The first show's shift
      # reuses this record (so existing assignments stay on it); the rest are new,
      # empty shifts to staff per show.
      def split_into_shows
        shows = @shift.covered_shows
        if shows.size < 2
          redirect_to_scheduling(alert: "This shift only covers one show.") and return
        end

        # Extra roles pinned to one show follow that show onto its own shift;
        # ones covering every show stay on the first, as they always did.
        scoped = @shift.shift_additional_roles.to_a
        everywhere = scoped.select(&:all_shows?).map(&:house_role_id)
        by_show = scoped.reject(&:all_shows?).group_by(&:show_id).transform_values { |rows| rows.map(&:house_role_id) }

        ActiveRecord::Base.transaction do
          first = shows.first
          @shift.update!(source: first, starts_at: first.date_and_time, ends_at: first.ends_at)
          @shift.shift_shows.destroy_all # back to a single-show shift
          @shift.reload.assign_additional_roles!((everywhere + by_show.fetch(first.id, [])).uniq)
          shows[1..].each do |show|
            split = Current.organization.shifts.create!(
              house_role_id: @shift.house_role_id,
              source: show,
              starts_at: show.date_and_time,
              ends_at: show.ends_at,
              required_count: @shift.required_count,
              coverage_mode: @shift.coverage_mode,
              renter_name: @shift.renter_name,
              notes: @shift.notes
            )
            split.assign_additional_roles!(by_show.fetch(show.id, []))
          end
        end
        redirect_to_scheduling notice: "Split into #{shows.size} per-show shifts."
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        redirect_to_scheduling alert: "Couldn't split: #{e.message}"
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

      # "Also covers" roles are deliberately not mass-assigned: a role can now be
      # scoped to some of the shows a shift covers, which a flat id list can't
      # say. apply_additional_roles handles them after the shift is saved.
      def shift_params
        params.require(:shift).permit(
          :house_role_id, :starts_at, :ends_at, :required_count,
          :coverage_mode, :renter_name, :notes, :source_type, :source_id
        )
      end

      # The "also covers" set from the form: which roles, and — on a shift that
      # covers several shows — which of those shows each role applies to. Only
      # touched when the form sent the set at all (the modal always does, with a
      # blank so unchecking everything still arrives).
      def apply_additional_roles
        raw = params[:shift]
        return unless raw.key?(:additional_role_ids)

        role_ids = Array(raw[:additional_role_ids]).map(&:to_s).reject(&:blank?).map(&:to_i).uniq
        # Only the org's own roles — a posted id from anywhere else is dropped.
        role_ids &= Current.organization.house_roles.where(id: role_ids).pluck(:id)

        # { role_id => [show_id, ...] } for the roles the modal offered scoping
        # on. The show ids are narrowed to the shift's own shows in the model.
        scoped = raw[:additional_role_show_ids]
        scoped = scoped.respond_to?(:to_unsafe_h) ? scoped.to_unsafe_h : (scoped || {})
        show_ids_by_role = scoped.to_h.each_with_object({}) do |(role_id, show_ids), h|
          h[role_id.to_i] = Array(show_ids).map(&:to_s).reject(&:blank?).map(&:to_i)
        end

        @shift.assign_additional_roles!(role_ids, show_ids_by_role)
      end

      # The extra roles a merge should end up with: every source shift's roles,
      # each pinned to the shows its own shift covered. Returns [role_ids,
      # { role_id => show_ids }] for Shift#assign_additional_roles!, which
      # collapses a role back to "every show" when it ends up covering them all.
      # Shifts with no shows (house shifts, free-standing) carry their roles
      # across unscoped — there's nothing to pin them to.
      def merged_additional_roles(shifts)
        role_ids = []
        show_ids_by_role = Hash.new { |h, k| h[k] = [] }
        unscoped = Set.new

        shifts.each do |shift|
          own_show_ids = shift.covered_shows.map(&:id)
          shift.shift_additional_roles.each do |row|
            next if row.house_role_id == @shift.house_role_id

            role_ids << row.house_role_id
            if row.show_id
              show_ids_by_role[row.house_role_id] << row.show_id
            elsif own_show_ids.any?
              show_ids_by_role[row.house_role_id].concat(own_show_ids)
            else
              unscoped << row.house_role_id
            end
          end
        end

        pinned = show_ids_by_role.to_h.except(*unscoped).transform_values(&:uniq)
        [ role_ids.uniq, pinned ]
      end

      # Extra shows this shift covers beyond its source anchor — the Add-shift
      # modal's multi-show checklist. Same shape merge produces: the earliest
      # show is the source, the rest live in shift_shows. Deliberately not in
      # shift_params so the ids are scoped to the org here, never mass-assigned.
      def attach_extra_shows
        ids = Array(params[:shift][:show_ids]).map(&:to_s).reject(&:blank?).uniq
        return if ids.empty? || @shift.source_type != "Show" || @shift.source_id.blank?
        @shift.shows = ::Show.joins(:production)
                             .where(productions: { organization_id: Current.organization.id })
                             .where(id: ids)
                             .where.not(id: @shift.source_id)
                             .to_a
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
