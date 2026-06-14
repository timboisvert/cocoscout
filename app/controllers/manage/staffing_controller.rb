# frozen_string_literal: true

module Manage
  # Staffing module landing page IS the weekly schedule. Sub-areas for House
  # Roles (Manage::Staffing::HouseRolesController) and Staff
  # (Manage::Staffing::StaffController) live under app/controllers/manage/staffing/.
  class StaffingController < Manage::ManageController
    before_action :ensure_org_owner_or_manager

    def index
      return unless Current.organization

      @week_start = parse_week_start(params[:week_start])
      @week_end = @week_start + 6.days

      @shows_by_day = shows_in_range(@week_start..@week_end).group_by { |s| s.date_and_time.to_date }
      week_range = (@week_start..@week_end)
      shifts = Current.organization.shifts
        .for_week(@week_start)
        .includes(:house_role, :secondary_house_role, :source, shift_assignments: :person)
        .ordered
        .to_a
      @shifts_by_day = shifts.group_by { |s| staffing_day_for(s, week_range) }

      @finalization = Current.organization.staffing_finalizations.find_by(week_start: @week_start)
      @week_finalized = @finalization&.finalized? || false
      # Who the finalize modal would notify, with each person's shift count.
      @finalize_recipients = build_finalize_recipients(shifts)

      @house_roles = Current.organization.house_roles.active.ordered.to_a
      @house_role_count = @house_roles.size
      @staff_count = Current.organization.organization_staff_members.active.count
      @staff_by_role_payload = build_staff_by_role_payload

      # Collision-detection payloads (consumed by the assign modal): the time
      # span + label of every shift this week, and which shift ids each person
      # is already on. The modal warns before double-booking someone.
      @shift_times_payload = shifts.each_with_object({}) do |s, h|
        h[s.id.to_s] = {
          starts_at: s.starts_at.iso8601,
          ends_at: s.ends_at.iso8601,
          role: s.house_role.name,
          day: s.starts_at.strftime("%a %b %-d"),
          # The schedule day this shift belongs to (follows its source show when
          # it crosses midnight). Used to match against cast on that day.
          cast_date: staffing_day_for(s, week_range).iso8601,
          time_range: "#{s.starts_at.strftime("%-l:%M %p")}–#{s.ends_at.strftime("%-l:%M %p")}"
        }
      end

      # Cast on each day, so the assign modal can warn when a staffer is also
      # performing that day, and the schedule can show each show's cast.
      all_week_shows = @shows_by_day.values.flatten
      @show_cast = build_show_cast(all_week_shows)
      @cast_by_day_payload = build_cast_by_day_payload(@shows_by_day, @show_cast)
      @person_busy_payload = shifts.each_with_object({}) do |s, h|
        s.shift_assignments.each do |a|
          (h[a.person_id.to_s] ||= []) << s.id.to_s
        end
      end

      # Staff unavailability for this week, so the assign modal can flag/filter
      # people who marked themselves unavailable on a shift's date + day part.
      staff_person_ids = Current.organization.organization_staff_members.active.pluck(:person_id)
      @staff_unavailability_payload = StaffUnavailability
        .where(person_id: staff_person_ids, date: @week_start..@week_end)
        .group_by { |u| u.person_id.to_s }
        .transform_values { |list| list.map { |u| { date: u.date.iso8601, scope: u.scope } } }
    end

    # Per-day shift auto-generation. See the long comment in the previous
    # ScheduleController for the algorithm — moved here when /staffing became
    # the schedule page itself.
    def generate
      @week_start = parse_week_start(params[:week_start])
      @week_end = @week_start + 6.days
      roles = Current.organization.house_roles.active.to_a
      if roles.empty?
        redirect_to manage_staffing_index_path(week_start: @week_start.to_s),
                    alert: "Add at least one house role first." and return
      end

      shows = shows_in_range(@week_start..@week_end)
      # Optional: restrict to a hand-picked subset of shows. Absent = all shows
      # in the week (the default), so the plain "generate for the week" still works.
      if params[:show_ids].present?
        selected_ids = Array(params[:show_ids]).map(&:to_i).to_set
        shows = shows.select { |s| selected_ids.include?(s.id) }
      end
      shows_by_day = shows.group_by { |s| s.date_and_time.to_date }
      created = 0
      skipped = 0

      shows_by_day.each do |_day, day_shows|
        sorted = day_shows.sort_by(&:date_and_time)
        first_show = sorted.first
        last_show = sorted.last

        roles.each do |role|
          # Each role generates against a set of (start, end, source) anchors:
          # house roles get ONE anchor spanning first-show-start → last-show-end;
          # show-specific roles get one anchor PER show on the day.
          anchors =
            if role.show_specific?
              sorted.map { |show| [ show.date_and_time, show.ends_at, show ] }
            else
              [ [ first_show.date_and_time, last_show.ends_at, first_show ] ]
            end

          anchors.each do |show_start, show_end, source_show|
            # Venue-scoped roles only staff shows at their venue.
            next if role.location_id.present? && source_show.location_id != role.location_id

            # The end offset is "minutes after the show ends," not after it starts.
            starts_at = show_start + role.default_start_offset_minutes.minutes
            ends_at   = show_end   + role.default_end_offset_minutes.minutes
            next if ends_at <= starts_at

            shift = Current.organization.shifts.new(
              house_role: role,
              source: source_show,
              starts_at: starts_at,
              ends_at: ends_at,
              required_count: role.default_required_count,
              coverage_mode: :needs_assignment
            )
            begin
              shift.save!
              created += 1
            rescue ActiveRecord::RecordNotUnique
              skipped += 1
            end
          end
        end
      end

      notice =
        if created.zero? && skipped.zero?
          "No shows in this week — nothing to generate."
        elsif created.zero?
          "Already up to date — no new shifts needed."
        else
          "#{created} shift(s) generated#{" (#{skipped} already existed and were skipped)" if skipped > 0}."
        end
      redirect_to manage_staffing_index_path(week_start: @week_start.to_s), notice: notice
    end

    # Finalize a week's schedule: record it and message every assigned staffer
    # their shifts for the week. Until this runs, staff can't see their draft
    # assignments. Re-running re-notifies (e.g. after a schedule change).
    def finalize
      @week_start = parse_week_start(params[:week_start])
      @week_end = @week_start + 6.days

      shifts = Current.organization.shifts
        .for_week(@week_start)
        .includes(:house_role, :secondary_house_role, :source, shift_assignments: :person)
        .ordered
        .to_a

      shifts_by_person = Hash.new { |h, k| h[k] = [] }
      shifts.each do |shift|
        shift.shift_assignments.each { |a| shifts_by_person[a.person] << shift }
      end

      finalization = Current.organization.staffing_finalizations.find_or_initialize_by(week_start: @week_start)
      finalization.finalized_at = Time.current
      finalization.finalized_by = Current.user
      finalization.save!

      subject = params[:subject].to_s.strip.presence || default_finalize_subject
      intro   = params[:message].to_s.strip.presence || default_finalize_intro

      notified = 0
      shifts_by_person.each do |person, person_shifts|
        next unless person&.user

        # Sent from the system (no individual sender) so it reads as an
        # "Automated Notification", not as coming from whoever clicked finalize.
        MessageService.create_message(
          sender: nil,
          recipients: [ person ],
          subject: subject,
          body: schedule_message_body(person_shifts.sort_by(&:starts_at), intro),
          message_type: :direct,
          organization: Current.organization,
          visibility: :personal,
          system_generated: true
        )
        Shift.where(id: person_shifts.map(&:id)).each do |s|
          s.shift_assignments.where(person_id: person.id).update_all(notified_at: Time.current)
        end
        notified += 1
      end

      notice =
        if notified.zero?
          "Schedule finalized. No staff are assigned yet, so no one was notified."
        else
          "Schedule finalized and #{notified} staff member#{"s" unless notified == 1} notified."
        end
      redirect_to manage_staffing_index_path(week_start: @week_start.to_s), notice: notice
    end

    public

    # Default subject/intro for the finalize message; also shown (editable) in
    # the finalize modal so the wording the manager sees is the wording sent.
    def default_finalize_subject
      "Your work schedule — week of #{@week_start.strftime("%b %-d")}"
    end
    helper_method :default_finalize_subject

    def default_finalize_intro
      "Your shifts for the week of #{@week_start.strftime("%B %-d")} are confirmed:"
    end
    helper_method :default_finalize_intro

    private

    # HTML body for a staffer: the manager's intro text, then that person's own
    # shift list, then a link to My Shifts. The intro is editable in the modal;
    # the per-person shift list is always appended by the system.
    def schedule_message_body(shifts, intro)
      rows = shifts.map do |s|
        location = s.house_role.location&.name || s.source.try(:location).try(:name)
        "<li style=\"margin-bottom:6px;\">" \
          "<strong>#{ERB::Util.html_escape(s.starts_at.strftime("%A, %b %-d"))}</strong> · " \
          "#{ERB::Util.html_escape(s.starts_at.strftime("%-l:%M %p"))}–#{ERB::Util.html_escape(s.ends_at.strftime("%-l:%M %p"))} · " \
          "#{ERB::Util.html_escape(s.role_label)}" \
          "#{location ? " · #{ERB::Util.html_escape(location)}" : ""}" \
        "</li>"
      end.join

      intro_html = ERB::Util.html_escape(intro).gsub("\n", "<br>")
      "<p>#{intro_html}</p>" \
      "<ul style=\"padding-left:18px;\">#{rows}</ul>" \
      "<p>See all your shifts any time on your <a href=\"#{my_shifts_url}\">My Shifts</a> page.</p>"
    end

    # Which calendar day a shift belongs to on the schedule. Source-linked shifts
    # (generated from a show or rental) follow their source's day, so a show at
    # 12:00 AM whose shift starts 11:00 PM the previous evening still groups with
    # the show's day. Falls back to the shift's own start date for free-standing
    # shifts, or when the source's day lands outside the visible week.
    def staffing_day_for(shift, week_range)
      anchor = shift.source.try(:date_and_time) || shift.source.try(:starts_at)
      day = anchor&.to_date
      return day if day && week_range.cover?(day)

      shift.starts_at.to_date
    end

    def parse_week_start(value)
      Date.parse(value.to_s).beginning_of_week
    rescue ArgumentError, TypeError
      Date.current.beginning_of_week
    end

    def shows_in_range(range)
      ::Show.joins(:production)
            .where(productions: { organization_id: Current.organization.id })
            .where(date_and_time: range.first.beginning_of_day..range.last.end_of_day)
            .where(canceled: [ false, nil ])
            .includes(:production, :location)
            .order(:date_and_time)
            .to_a
    end

    # [{ person:, shift_count:, notifiable: }] for the finalize modal, sorted by
    # name. notifiable is false for staff without an account (can't be messaged).
    def build_finalize_recipients(shifts)
      by_person = Hash.new(0)
      shifts.each do |shift|
        shift.shift_assignments.each { |a| by_person[a.person] += 1 }
      end
      by_person.map { |person, count|
        { person: person, shift_count: count, notifiable: person&.user.present? }
      }.sort_by { |r| r[:person].name.to_s }
    end

    # { show_id => [Person, ...] } — direct cast plus members of any cast groups.
    # Queries the join table directly: the Show#cast_people scope references the
    # join table by name, which breaks under eager preloading.
    def build_show_cast(shows)
      return {} if shows.empty?

      show_ids = shows.map(&:id)
      result = Hash.new { |h, k| h[k] = [] }

      ShowPersonRoleAssignment
        .where(show_id: show_ids, assignable_type: "Person")
        .includes(:assignable)
        .each { |a| result[a.show_id] << a.assignable if a.assignable }

      ShowPersonRoleAssignment
        .where(show_id: show_ids, assignable_type: "Group")
        .includes(:assignable)
        .each { |a| a.assignable&.members&.each { |m| result[a.show_id] << m } }

      result.transform_values(&:uniq)
    end

    # { "YYYY-MM-DD" => { "<person_id>" => ["Production (7:00 PM)", ...] } }
    def build_cast_by_day_payload(shows_by_day, show_cast)
      payload = {}
      shows_by_day.each do |day, day_shows|
        key = day.iso8601
        day_shows.each do |show|
          label = "#{show.production&.name} (#{show.date_and_time.strftime("%-l:%M %p")})"
          (show_cast[show.id] || []).each do |person|
            ((payload[key] ||= {})[person.id.to_s] ||= []) << label
          end
        end
      end
      payload
    end

    def build_staff_by_role_payload
      quals = StaffRoleQualification
        .joins(organization_staff_member: :person)
        .where(organization_staff_members: { organization_id: Current.organization.id, archived_at: nil })
        .includes(organization_staff_member: :person)
        .order("people.name")

      quals.group_by(&:house_role_id).transform_values do |group|
        group.map do |q|
          p = q.organization_staff_member.person
          variant = p.respond_to?(:safe_headshot_variant) ? p.safe_headshot_variant(:thumb) : nil
          {
            id: p.id,
            name: p.name,
            initials: p.initials,
            headshot_url: variant ? url_for(variant) : nil
          }
        end
      end.transform_keys(&:to_s)
    end
  end
end
