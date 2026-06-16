# frozen_string_literal: true

module Manage
  module Staffing
    class ShiftsController < Manage::ManageController
      before_action :ensure_org_owner_or_manager
      before_action :set_shift, only: %i[update destroy assign unassign split merge_with_next acknowledge_gap unacknowledge_gap]

      def create
        @shift = Current.organization.shifts.new(shift_params)
        if @shift.save
          flash[:notice] = "Shift added."
        else
          flash[:alert] = "Couldn't add shift: #{@shift.errors.full_messages.to_sentence}"
        end
        redirect_back_or_to manage_staffing_index_path
      end

      def update
        if @shift.update(shift_params)
          flash[:notice] = "Shift updated."
        else
          flash[:alert] = "Couldn't update shift: #{@shift.errors.full_messages.to_sentence}"
        end
        redirect_back_or_to manage_staffing_index_path
      end

      def destroy
        @shift.destroy!
        redirect_back_or_to manage_staffing_index_path, notice: "Shift removed."
      end

      def assign
        person_id = params[:person_id].to_i
        person = Current.organization.people.find_by(id: person_id)
        unless person
          redirect_back_or_to(manage_staffing_index_path, alert: "Person not found in this organization.") and return
        end
        # Only allow assigning if the person is on staff and qualified for the role.
        member = OrganizationStaffMember.active.find_by(organization: Current.organization, person: person)
        unless member && member.house_role_ids.include?(@shift.house_role_id)
          redirect_back_or_to(manage_staffing_index_path, alert: "That person isn't on staff or isn't qualified for this role.") and return
        end

        next_position = (@shift.shift_assignments.maximum(:position) || 0) + 1
        assignment = @shift.shift_assignments.new(person: person, position: next_position)
        if assignment.save
          redirect_back_or_to manage_staffing_index_path, notice: "Assigned #{person.name}."
        else
          redirect_back_or_to manage_staffing_index_path,
                              alert: assignment.errors.full_messages.to_sentence.presence || "Couldn't assign."
        end
      end

      def unassign
        assignment = @shift.shift_assignments.find_by(person_id: params[:person_id])
        if assignment
          name = assignment.person.name
          assignment.destroy!
          redirect_back_or_to manage_staffing_index_path, notice: "Removed #{name} from this shift."
        else
          redirect_back_or_to manage_staffing_index_path, alert: "Assignment not found."
        end
      end

      # Split a shift into N segments. The Split modal sends params[:segments]
      # as an array of { starts_at, ends_at } pairs. The first segment replaces
      # the original (so existing assignments stay on it); subsequent segments
      # are created as new shifts. If no segments are sent (e.g. a future
      # programmatic caller), falls back to splitting in half at the midpoint.
      def split
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
            redirect_back_or_to(manage_staffing_index_path, alert: "Each segment must end after it starts.") and return
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
        redirect_back_or_to manage_staffing_index_path,
                            notice: "Split into #{segments.size} shifts."
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        redirect_back_or_to manage_staffing_index_path, alert: "Couldn't split: #{e.message}"
      end

      # Merge with the adjacent same-role shift that starts at this one's end.
      # Combines assignments (dedup by person), then deletes the second shift.
      def merge_with_next
        next_shift = Current.organization.shifts
          .where(house_role_id: @shift.house_role_id, source_type: @shift.source_type, source_id: @shift.source_id)
          .where(starts_at: @shift.ends_at)
          .order(:starts_at)
          .first

        unless next_shift
          redirect_back_or_to(manage_staffing_index_path, alert: "No adjacent shift to merge with.") and return
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
          @shift.update!(ends_at: next_shift.ends_at)
          next_shift.destroy!
        end
        redirect_back_or_to manage_staffing_index_path, notice: "Shifts merged."
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        redirect_back_or_to manage_staffing_index_path, alert: "Couldn't merge: #{e.message}"
      end

      # Mark the gap between this shift and the next same-role shift as intentional.
      # We store the next shift's starts_at; if the schedule shifts, the stored value
      # no longer matches and the warning reappears automatically.
      def acknowledge_gap
        next_starts_at = Time.zone.parse(params[:next_starts_at].to_s)
        if next_starts_at.nil? || next_starts_at <= @shift.ends_at
          redirect_back_or_to(manage_staffing_index_path, alert: "Couldn't acknowledge gap.") and return
        end
        @shift.update!(gap_after_acknowledged_until: next_starts_at)
        redirect_back_or_to manage_staffing_index_path, notice: "Gap marked OK."
      end

      def unacknowledge_gap
        @shift.update!(gap_after_acknowledged_until: nil)
        redirect_back_or_to manage_staffing_index_path, notice: "Gap warning restored."
      end

      private

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
