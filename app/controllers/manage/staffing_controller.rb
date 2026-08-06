# frozen_string_literal: true

module Manage
  # Staffing module landing page IS the weekly schedule. Sub-areas for House
  # Roles (Manage::Staffing::HouseRolesController) and Staff
  # (Manage::Staffing::StaffController) live under app/controllers/manage/staffing/.
  class StaffingController < Manage::ManageController
    before_action :ensure_org_owner_or_manager

    # The Staffing landing is now the people-first hub: the org's staff list with
    # onboarding status. The weekly schedule moved to #scheduling.
    def index
      return unless Current.organization

      members = Current.organization.organization_staff_members
                       .active
                       .includes(:house_roles, person: :user)
                       .joins(:person)
                       .order("people.name")
      @house_roles = Current.organization.house_roles.active.ordered

      # Emails with an outstanding (unaccepted) invite — the concrete signal that
      # someone hasn't set up their CocoScout account yet.
      @pending_invite_emails = PersonInvitation.pending
                                               .where(organization: Current.organization)
                                               .pluck(:email)
                                               .map { |e| e.to_s.downcase }
                                               .to_set

      # A staff member is "pending" until they've created/claimed a CocoScout
      # account. Those people live in a separate sub-list — they're on their way
      # onto the team but not fully onboarded yet.
      @active_staff, @pending_staff = members.partition { |m| account_claimed?(m) }
      @staff_count = @active_staff.size
      @pending_count = @pending_staff.size

      # Inactive members: still loved, still in the records — just not scheduled,
      # paid, counted, or nagged. Shown collapsed under the roster.
      @inactive_staff = Current.organization.organization_staff_members.inactive
                               .includes(:house_roles, person: :user)
                               .joins(:person).order("people.name")

      # Worked hours submitted by staff and awaiting a manager's sign-off — the
      # badge on the "Approve Hours" tile.
      @hours_to_approve_count = Current.organization.staff_time_entries.pending.count

      # Staff who've said "I can't make it" on an upcoming shift.
      @declined_assignments = declined_upcoming_assignments

      # The org chart now lives in a modal opened from the staff list.
      load_org_chart
    end

    # Full org chart of the org's staff, built from manager relationships (kept as
    # a standalone page for deep links; the staffing home opens it in a modal).
    def org_chart
      return unless Current.organization

      load_org_chart
    end

    # The weekly house-staff schedule (formerly the Staffing landing page).
    def scheduling
      return unless Current.organization

      @week_start = parse_week_start(params[:week_start])
      @week_end = @week_start + 6.days

      @shows_by_day = shows_in_range(@week_start..@week_end).group_by { |s| s.date_and_time.to_date }
      week_range = (@week_start..@week_end)
      shifts = Current.organization.shifts
        .for_week(@week_start)
        .includes(:house_role, :additional_roles, :source, :shows, shift_assignments: :person)
        .ordered
        .to_a
      @shifts_by_day = shifts.group_by { |s| staffing_day_for(s, week_range) }

      # Per-show coverage detail — always computed, so the show popover can lay
      # out covered/missing show-specific roles whether or not the assistant is
      # on. The amber chip flag stays opt-in (Staffing settings) and skips shows
      # marked as not needing coverage.
      @show_coverage = show_coverage_by_show(shifts)
      @uncovered_roles_by_show =
        if Current.organization.alert_uncovered_show_roles?
          @show_coverage.each_with_object({}) do |(show_id, entry), h|
            next if entry[:exempt]

            missing = entry[:roles].reject { |r| r[:covered] }.map { |r| r[:name] }
            h[show_id] = missing if missing.any?
          end
        else
          {}
        end

      @finalization = Current.organization.staffing_finalizations.find_by(week_start: @week_start)
      @week_finalized = @finalization&.finalized? || false
      # Who the finalize modal would notify, with each person's shift count.
      @finalize_recipients = build_finalize_recipients(shifts)
      # Staff who've said "I can't make it" on an upcoming shift — a heads-up for
      # the manager (no auto-offering; they decide what to do). The grid also flags
      # declined chips directly via each assignment's declined? state.
      @declined_assignments = declined_upcoming_assignments
      # Smart comms status: who's up to date vs. needs a (re)notify this week.
      @comms = compute_schedule_updates(shifts, @week_start)

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
      modes = Person.where(id: staff_person_ids).pluck(:id, :availability_mode).to_h
      entries_by_person = StaffUnavailability
        .where(person_id: staff_person_ids, date: @week_start..@week_end)
        .group_by(&:person_id)
      # Include every staff person + their mode so the assign modal can interpret
      # "available"-mode people (available only where marked) correctly.
      @staff_unavailability_payload = staff_person_ids.index_with do |pid|
        {
          mode: modes[pid] || "unavailable",
          entries: (entries_by_person[pid] || []).map { |u| { date: u.date.iso8601, scope: u.scope } }
        }
      end.transform_keys(&:to_s)

      load_availability_overview
    end
    # Publish/notify a week's schedule. The FIRST time (never finalized) this
    # publishes the week and notifies everyone assigned. Once published, it's a
    # targeted "Notify updates": only people with a new/changed/removed shift are
    # messaged — unless params[:notify_all] forces a full re-notify. Until a week
    # is published, staff can't see their draft assignments.
    def finalize
      @week_start = parse_week_start(params[:week_start])
      @week_end = @week_start + 6.days

      shifts = Current.organization.shifts
        .for_week(@week_start)
        .includes(:house_role, :additional_roles, :source, shift_assignments: :person)
        .ordered
        .to_a

      was_published = Current.organization.staffing_finalizations.find_by(week_start: @week_start)&.finalized? || false

      finalization = Current.organization.staffing_finalizations.find_or_initialize_by(week_start: @week_start)
      finalization.finalized_at = Time.current
      finalization.finalized_by = Current.user
      finalization.save!

      subject = params[:subject].to_s.strip.presence || default_finalize_subject
      intro   = params[:message].to_s.strip.presence || default_finalize_intro

      comp = compute_schedule_updates(shifts, @week_start)
      notify_everyone = !was_published || params[:notify_all].present?
      people = notify_everyone ? comp[:all_people] : comp[:update].map { |u| u[:person] }

      notified = notify_people_for_week(people: people, week_start: @week_start, shifts: shifts, subject: subject, intro: intro)

      notice =
        if !was_published
          notified.zero? ? "Schedule published. No staff are assigned yet, so no one was notified." :
            "Schedule published — #{notified} staff member#{"s" unless notified == 1} notified."
        elsif notified.zero?
          "Everyone's already up to date — no notifications were sent."
        else
          "Notified #{notified} #{"person".pluralize(notified)} of their schedule #{notify_everyone ? "" : "changes"}.".squeeze(" ")
        end
      redirect_to manage_staffing_scheduling_path(week_start: @week_start.to_s), notice: notice
    end

    # Per-show opt-out of the coverage assistant: "this one doesn't need the
    # show roles." Flips with the same control, so no confirm needed.
    def toggle_show_coverage_exempt
      show = ::Show.joins(:production)
                   .where(productions: { organization_id: Current.organization.id })
                   .find_by(id: params[:id])
      return redirect_to(manage_staffing_scheduling_path, alert: "We couldn't find that show.") unless show

      show.update!(staffing_coverage_exempt: params[:exempt].present?)
      day = show.date_and_time.to_date
      redirect_to manage_staffing_scheduling_path(week_start: day.beginning_of_week.iso8601, anchor: "day-#{day.iso8601}"),
                  notice: show.staffing_coverage_exempt? ? "#{show.display_name} won't be flagged for show-role coverage." : "#{show.display_name} is back in the coverage checks."
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

    # Has this staff member created/claimed their CocoScout account? True once
    # they have a linked user AND no outstanding (unaccepted) invite. Until then
    # they sit in the "pending" list rather than the active roster.
    def account_claimed?(member)
      person = member.person
      return false if person&.user.nil?
      # If they've accepted onboarding they've logged in and claimed their
      # account for real — a stale pending invite (e.g. they already had a
      # CocoScout account, so never clicked the accept link) shouldn't keep them
      # stuck in the pending section.
      return true if member.acknowledged?

      email = person.email.to_s.downcase
      email.blank? || !@pending_invite_emails.include?(email)
    end

    # People in the org who aren't already staff members (for the add-staff picker).
    def available_org_people
      existing_ids = Current.organization.organization_staff_members.active.pluck(:person_id)
      Current.organization.people.where.not(id: existing_ids).order(:name)
    end

    # Classify this week's staff for the comms row / notify action. Returns:
    #   update:        [{ person:, reason: :new|:changed|:removed }] — need a notify
    #   current_count: how many assigned people are fully up to date
    #   total:         distinct people involved (assigned or with a pending removal)
    #   all_people:    every such Person (for a full re-notify)
    # "changed" = the shift row was edited after we last told them (shift.updated_at
    # > their assignment's notified_at). "new" = an un-notified assignment.
    def compute_schedule_updates(shifts, week_start)
      week_range = week_start.beginning_of_day..(week_start + 6.days).end_of_day

      pairs_by_person = Hash.new { |h, k| h[k] = [] }
      shifts.each do |shift|
        shift.shift_assignments.each { |a| pairs_by_person[a.person] << [ a, shift ] if a.person }
      end

      removals = Current.organization.staff_schedule_removals.pending
                        .where(shift_starts_at: week_range).includes(:person).to_a
      removal_person_ids = removals.map(&:person_id).to_set

      update = []
      current_count = 0
      pairs_by_person.each do |person, pairs|
        reason =
          if pairs.any? { |a, _s| a.notified_at.nil? } then :new
          elsif pairs.any? { |a, s| a.notified_at && s.updated_at > a.notified_at } then :changed
          elsif removal_person_ids.include?(person.id) then :removed
          end
        reason ? update << { person: person, reason: reason } : current_count += 1
      end

      # People with a pending removal but no remaining assignment this week.
      assigned_ids = pairs_by_person.keys.map(&:id).to_set
      removals.reject { |r| assigned_ids.include?(r.person_id) }.map(&:person).compact.uniq.each do |person|
        update << { person: person, reason: :removed }
      end

      all_people = (pairs_by_person.keys + removals.map(&:person)).compact.uniq
      {
        update: update.uniq { |u| u[:person].id }.sort_by { |u| u[:person].name.to_s.downcase },
        current_count: current_count,
        total: all_people.size,
        all_people: all_people
      }
    end

    # Message the given people about this week: each gets their own shift list plus
    # any pending removals, via the seeded ContentTemplate (in-app message). Stamps
    # notified_at on their assignments, clears their removals, and records billing.
    # Returns how many people were actually notified (those with a login).
    def notify_people_for_week(people:, week_start:, shifts:, subject:, intro:)
      week_range = week_start.beginning_of_day..(week_start + 6.days).end_of_day

      shifts_by_person = Hash.new { |h, k| h[k] = [] }
      shifts.each { |s| s.shift_assignments.each { |a| shifts_by_person[a.person_id] << s } }

      removals_by_person = Current.organization.staff_schedule_removals.pending
                                  .where(shift_starts_at: week_range).group_by(&:person_id)

      notified = 0
      people.each do |person|
        next unless person&.user

        person_shifts = (shifts_by_person[person.id] || []).sort_by(&:starts_at)
        person_removals = removals_by_person[person.id] || []
        next if person_shifts.empty? && person_removals.empty?

        ContentTemplateService.deliver(
          template_key: "staff_schedule_notification",
          variables: {
            recipient_name: first_name_of(person),
            organization_name: Current.organization.name,
            week_label: week_start.strftime("%B %-d"),
            intro: ERB::Util.html_escape(intro),
            shifts_list: shifts_list_html(person_shifts),
            removals_list: removals_list_html(person_removals),
            my_shifts_link: my_shifts_url
          },
          subject_override: subject,
          sender: nil,
          recipients: [ person ],
          organization: Current.organization,
          message_type: :system,
          visibility: :personal
        )

        Shift.where(id: person_shifts.map(&:id)).each do |s|
          s.shift_assignments.where(person_id: person.id).update_all(notified_at: Time.current)
        end
        StaffScheduleRemoval.where(id: person_removals.map(&:id)).update_all(notified_at: Time.current, updated_at: Time.current)

        # Durably mark billable for every month notified about (survives later
        # changes, so removing assignments can't dodge the charge).
        person_shifts.map { |s| s.starts_at.to_date.beginning_of_month }.uniq.each do |month|
          StaffActivation.record!(organization: Current.organization, person: person, month: month)
        end
        notified += 1
      end
      notified
    end

    def first_name_of(person)
      person.name.to_s.split(/\s+/).first.presence || person.name.to_s
    end

    # Pre-rendered (self-escaped) <li> list of a person's shifts, injected into the
    # notification template.
    def shifts_list_html(shifts)
      shifts.map do |s|
        location = s.house_role.location&.name || s.source.try(:location).try(:name)
        "<li style=\"margin-bottom:6px;\">" \
          "<strong>#{ERB::Util.html_escape(s.starts_at.strftime("%A, %b %-d"))}</strong> · " \
          "#{ERB::Util.html_escape(s.starts_at.strftime("%-l:%M %p"))}–#{ERB::Util.html_escape(s.ends_at.strftime("%-l:%M %p"))} · " \
          "#{ERB::Util.html_escape(s.role_label)}" \
          "#{location ? " · #{ERB::Util.html_escape(location)}" : ""}" \
        "</li>"
      end.join
    end

    def removals_list_html(removals)
      removals.map do |r|
        loc = r.location_name.present? ? " · #{ERB::Util.html_escape(r.location_name)}" : ""
        "<li style=\"margin-bottom:6px;\">" \
          "<strong>#{ERB::Util.html_escape(r.shift_starts_at.strftime("%A, %b %-d"))}</strong> · " \
          "#{ERB::Util.html_escape(r.shift_starts_at.strftime("%-l:%M %p"))} · " \
          "#{ERB::Util.html_escape(r.shift_label.to_s)}#{loc}" \
        "</li>"
      end.join
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

    # Staff who declined ("can't make it") an upcoming shift for this org.
    def declined_upcoming_assignments
      ShiftAssignment.declined
        .joins(:shift)
        .where(shifts: { organization_id: Current.organization.id })
        .where("shifts.ends_at >= ?", Time.current)
        .includes(:person, shift: [ :house_role, :source ])
        .order("shifts.starts_at ASC")
        .to_a
    end
    # { show_id => [role names] } for every show in the loaded week that lacks
    # a fully staffed shift covering it for an applicable show-specific role.
    # "Applicable" respects venue scoping: a role tied to another location is
    # never reported missing for this show. A shift covers a show only through
    # its explicit links (source / merged shift_shows) — never inferred from
    # time — and counts once it's fully staffed (which includes
    # covered_by_renter and not_needed modes).
    #
    # Returns { show_id => { roles: [ { name:, covered: } ], exempt: } } for
    # every show in the week with at least one applicable show-specific role.
    def show_coverage_by_show(shifts)
      show_roles = Current.organization.house_roles.active.select(&:show_specific?)
      return {} if show_roles.empty?

      covered = Hash.new { |h, k| h[k] = Set.new }
      shifts.each do |shift|
        next unless shift.fully_staffed?

        role_ids = [ shift.house_role_id ] + shift.additional_roles.map(&:id)
        shift.covered_shows.each { |show| covered[show.id].merge(role_ids) }
      end

      result = {}
      @shows_by_day.each_value do |shows|
        shows.each do |show|
          applicable = show_roles.select { |role| role.location_id.nil? || role.location_id == show.location_id }
          next if applicable.empty?

          result[show.id] = {
            roles: applicable.map { |role| { name: role.name, covered: covered[show.id].include?(role.id) } },
            exempt: show.staffing_coverage_exempt?
          }
        end
      end
      result
    end

    def shows_in_range(range)
      ::Show.joins(:production)
            .where(productions: { organization_id: Current.organization.id })
            .where(date_and_time: range.first.beginning_of_day..range.last.end_of_day)
            .where(canceled: [ false, nil ])
            .includes(:production, :location, :space_rental)
            .order(:date_and_time)
            .to_a
    end

    # [{ person:, shift_count:, notifiable: }] for the finalize modal, sorted by
    # name. notifiable is false for staff without an account (can't be messaged).
    # Staff manager-tree used by both the standalone org-chart page and the
    # staffing-home modal. Sets @roots + @children_by_manager.
    def load_org_chart
      @staff = Current.organization.organization_staff_members.active
                      .includes(:person, :manager).order("people.name").references(:person).to_a
      active_ids = @staff.map(&:id).to_set
      @children_by_manager = @staff.group_by(&:manager_id)
      # Roots: no manager, or a manager who's no longer active staff.
      @roots = @staff.select { |m| m.manager_id.nil? || active_ids.exclude?(m.manager_id) }
    end

    # Every active staff member (alphabetical) with their upcoming availability
    # marks (today onward), for the read-only "Availability" overview modal on the
    # scheduling page. Anyone with staffing access can see it — the org is flat.
    def load_availability_overview
      members = Current.organization.organization_staff_members.active
                       .includes(:person).order("people.name").references(:person).to_a
      person_ids = members.map(&:person_id)
      future_by_person = StaffUnavailability
        .where(person_id: person_ids, date: Date.current..(Date.current + 4.months))
        .order(:date)
        .group_by(&:person_id)
      @availability_overview = members.map do |m|
        {
          member: m,
          mode: m.person&.availability_mode || "unavailable",
          entries: (future_by_person[m.person_id] || []).map { |u| { date: u.date, label: u.scope_label } }
        }
      end
    end

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
