# frozen_string_literal: true

module Manage
  module Staffing
    # Staffing → Availability: who can work when, across the whole staff, on a
    # month calendar. Each day says how many can work (all day, or part of it);
    # clicking one opens the day — everyone, grouped by whether they can work,
    # with their hours and their shifts that day. Beside it: who has confirmed
    # their availability lately, and a way to ask the rest (a previewed draft,
    # like every send to several people).
    class AvailabilityController < Manage::ManageController
      before_action :ensure_org_owner_or_manager

      CALENDAR_MONTHS = 12

      def index
        @calendar = ForwardMonthCalendar.new(params[:month], months: CALENDAR_MONTHS)
        @house_roles = Current.organization.house_roles.active.ordered.to_a
        @role = @house_roles.find { |r| r.id == params[:role_id].to_i }
        @members = members

        resolver = StaffAvailabilityResolver.new(@members.map(&:person_id), from: @calendar.range.first, to: @calendar.range.last)
        @days = @calendar.range.index_with { |date| day_summary(resolver, date) }

        # Who's vouched for their availability lately — across all active staff,
        # whatever the role filter.
        everyone = Current.organization.organization_staff_members.active.includes(person: :user).to_a
        today = Date.current
        @confirmed_count = everyone.count { |m| (m.person&.availability_confirmed_through || today - 1) >= today }
        @staff_count = everyone.size
        @unconfirmed = everyone.reject { |m| (m.person&.availability_confirmed_through || today - 1) >= today }
                               .sort_by { |m| [ m.person&.availability_confirmed_at ? 0 : 1, m.display_name.to_s.downcase ] }
        @nudgeable = @unconfirmed.select { |m| StaffAvailabilityNudger.requestable?(m) }
        @nudge_draft = StaffAvailabilityNudger.draft(organization: Current.organization) if @nudgeable.any?
      end

      # One day, everyone: loaded into the page's day modal (a Turbo frame).
      def day
        @date = Date.iso8601(params[:date].to_s)
        @role = Current.organization.house_roles.find_by(id: params[:role_id]) if params[:role_id].present?
        people = members
        resolver = StaffAvailabilityResolver.new(people.map(&:person_id), from: @date, to: @date)

        shifts_by_person = ShiftAssignment.active
                                          .joins(:shift)
                                          .where(shifts: { organization_id: Current.organization.id })
                                          .where(person_id: people.map(&:person_id))
                                          .where("shifts.starts_at >= ? AND shifts.starts_at < ?",
                                                 @date.in_time_zone.beginning_of_day, (@date + 1).in_time_zone.beginning_of_day)
                                          .includes(shift: :house_role)
                                          .group_by(&:person_id)

        rows = people.map do |member|
          day = resolver.day(member.person_id, @date)
          { member: member, day: day, shifts: (shifts_by_person[member.person_id] || []).map(&:shift).sort_by(&:starts_at) }
        end
        @groups = {
          all_day: rows.select { |r| r[:day].free? },
          part: rows.select { |r| r[:day].partial? },
          unknown: rows.select { |r| r[:day].unknown? },
          off: rows.select { |r| r[:day].blocked? }
        }
        render layout: false
      rescue Date::Error
        head :not_found
      end

      # "Ask them to confirm": the ticked people get the (edited) draft, sent
      # from a job.
      def nudge
        ids = Array(params[:staff_member_ids]).map(&:to_i)
        members = Current.organization.organization_staff_members.active.where(id: ids)
                         .includes(person: :user).select { |m| StaffAvailabilityNudger.requestable?(m) }
        if members.empty?
          return redirect_to(return_path, alert: "Tick at least one person to ask.")
        end

        StaffAvailabilityNudgeJob.perform_later(Current.organization.id, members.map(&:id),
                                                params[:email_subject], params[:email_body], Current.user.id)
        redirect_to return_path, notice: "Asking #{helpers.pluralize(members.size, 'person')} to confirm their availability — we're emailing and messaging them now."
      end

      private

      # Active staff, narrowed to one house role when the filter asks.
      def members
        scope = Current.organization.organization_staff_members.active
                       .includes(person: [ :user, Manage::StaffingController::HEADSHOT_PRELOAD ])
                       .joins(:person).order("people.name")
        scope = scope.where(id: StaffRoleQualification.where(house_role_id: @role.id).select(:organization_staff_member_id)) if @role
        scope.to_a
      end

      # What one calendar day says: counts, and the people who can work all or
      # part of it (for the headshot chips).
      def day_summary(resolver, date)
        free = []
        part = []
        off = 0
        @members.each do |m|
          day = resolver.day(m.person_id, date)
          if day.free? || day.unknown? then free << m
          elsif day.partial? then part << m
          else off += 1
          end
        end
        { date: date, free: free, part: part, off: off }
      end

      def return_path
        if params[:from] == "staff" && (member = Current.organization.organization_staff_members.find_by(id: params[:staff_member_ids]&.first))
          manage_edit_staffing_staff_path(member, anchor: "availability")
        else
          manage_staffing_availability_path(month: params[:month].presence, role_id: params[:role_id].presence)
        end
      end
    end
  end
end
