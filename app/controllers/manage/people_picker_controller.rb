# frozen_string_literal: true

module Manage
  # The shared People Picker's search (V1.1 plan §5): the one place every
  # "pick a person" sheet asks, scoped to what the page is picking for.
  #   q              what was typed; two characters or more, or nothing with
  #                  list=pool
  #   scope          "people" (the organization's people, the default),
  #                  "users" (only those with an account, for team pages),
  #                  "members" (people and groups), "staff" (who's qualified
  #                  for a shift's role, with shift_id; fit=all|can_work|free
  #                  keeps everyone, those who can work some of it, or those
  #                  free for all of it), "auditionees" (a cycle's sign-ups
  #                  for an audition session, with audition_session_id;
  #                  fit=available|all, hide_scheduled=1|0)
  #   list           "pool": with nothing typed, the production's talent pool,
  #                  available for the show first (casting pages); "org": the
  #                  organization's people (and groups) before anything's typed
  #   outside        "1" adds people on CocoScout outside the organization
  #                  (PersonSearch: by name, profile key or their exact email;
  #                  their email never shows unless it's what was typed)
  #   invite         "1" offers to invite a typed email nobody has
  #   guest          "1" offers to add a guest by name (and email) instead
  #   production_id  its talent pool's members wear "In the talent pool"; on
  #                  the users scope its team is "On the team" and not pickable
  #   talent_pool_id that pool's members are "In the pool" and not pickable
  #   show_id        each person's availability for that show (and its linked
  #                  shows) as a badge; who's in the show already is
  #                  "Already in this show" and not pickable, or a badge when
  #                  in_show=badge (an act-based night casts one person twice)
  #   role_id        a restricted role: those not approved for it wear
  #                  "Not approved for this role" (the page asks before
  #                  assigning anyway)
  #   exclude        ids (or Type_id keys) already picked or added: "Already
  #                  added" (or exclude_label), not pickable
  #   invited        ids already invited: "Already invited", not pickable
  class PeoplePickerController < Manage::ManageController
    before_action :set_production_scope
    before_action :ensure_user_is_manager

    SCOPES = %w[people users members staff auditionees].freeze
    HEADSHOTS = { profile_headshots: { image_attachment: :blob } }.freeze

    def search
      q = params[:q].to_s.strip
      scope = params[:scope].presence_in(SCOPES) || "people"
      return search_staff(q) if scope == "staff"
      return search_auditionees(q) if scope == "auditionees"

      listing = q.length < 2 && ((params[:list] == "pool" && @production.present?) || params[:list] == "org")
      locals = { query: q, people: [], groups: [], outside: [], already: {}, badges: Hash.new { |h, k| h[k] = [] }, ineligible: Set.new,
                 invite_email: nil, invite_name: params[:invite_name] == "1", guest: params[:guest] == "1", listing: listing, extras: {} }

      if q.length >= 2 || listing
        org = Current.organization
        people, groups = if !listing then search_members(org, q, scope)
        elsif params[:list] == "org" then org_members(org, scope)
        else pool_members(scope)
        end

        already = {}
        exclude_label = params[:exclude_label].presence || "Already added"
        Array(params[:exclude]).each { |id| already[key_for(id)] = exclude_label }
        Array(params[:invited]).each { |id| already[key_for(id)] = "Already invited" }
        if (pool = talent_pool)
          pool.talent_pool_memberships.pluck(:member_type, :member_id).each { |type, id| already["#{type}_#{id}"] = "In the pool" }
        end
        badges = locals[:badges]
        if @production
          if scope == "users"
            team_user_ids = @production.production_permissions.pluck(:user_id).to_set
            people.each { |p| already["Person_#{p.id}"] = "On the team" if team_user_ids.include?(p.user_id) }
          elsif !listing && (effective = @production.effective_talent_pool)
            effective.talent_pool_memberships.where(member_type: "Person").pluck(:member_id).to_set
                     .each { |id| badges["Person_#{id}"] << "In the talent pool" }
          end
        end

        show = @production && params[:show_id].present? ? @production.shows.find_by(id: params[:show_id]) : nil
        if show
          members = people + groups
          availability_badges(show, members).each { |key, badge| badges[key] << badge }
          in_show = ShowPersonRoleAssignment.where(show: show).pluck(:assignable_type, :assignable_id).map { |t, id| "#{t}_#{id}" }.to_set
          members.each do |m|
            key = "#{m.class.name}_#{m.id}"
            next unless in_show.include?(key)

            if params[:in_show] == "badge" then badges[key] << "Already in this show"
            else already[key] ||= "Already in this show"
            end
          end
          if params[:role_id].present? && (role = show.available_roles.find_by(id: params[:role_id])) && role.restricted?
            members.each do |m|
              next if role.eligible?(m)

              locals[:ineligible] << "#{m.class.name}_#{m.id}"
              badges["#{m.class.name}_#{m.id}"] << "Not approved for this role"
            end
          end
          if listing
            rank = ->(m) { badges["#{m.class.name}_#{m.id}"].find { |b| b.start_with?("Available", "Unavailable") }.to_s }
            order = { "Available" => 0, "" => 2, "Unavailable" => 3 }
            people.sort_by! { |m| [ order.fetch(rank.call(m).split(" ").first.to_s, 1), m.name.to_s.downcase ] }
            groups.sort_by! { |m| [ order.fetch(rank.call(m).split(" ").first.to_s, 1), m.name.to_s.downcase ] }
          end
        end

        outside = []
        if params[:outside] == "1" && !listing
          outside = PersonSearch.outside(q).where.not(id: org.people.select(:id)).includes(HEADSHOTS).limit(10).to_a
          outside.select! { |p| p.user_id.present? } if scope == "users"
        end

        if params[:invite] == "1" && q.include?("@") && (people + outside).none? { |p| p.email&.casecmp?(q) }
          locals[:invite_email] = q
        end
        locals.merge!(people: people, groups: groups, outside: outside, already: already)
      end

      render partial: "shared/people_picker/results", locals: locals
    end

    private

    FIT = { "free" => 0, "partial" => 2, "unknown" => 4, "blocked" => 6 }.freeze

    # Staffing's shift assign (V1.1 plan §5): everyone qualified for the
    # shift's role, free for all of it first, then partly, then hasn't said,
    # then can't; who's on it already, in a show that night, or on another
    # shift that overlaps, so the page can ask before double-booking. The
    # Everyone / Can work / Free filters are fit=all|can_work|free.
    def search_staff(q)
      shift = Current.organization.shifts.includes(:house_role, :source).find(params[:shift_id])
      role = shift.house_role
      members = StaffRoleQualification.joins(organization_staff_member: :person)
                                      .where(house_role_id: role.id, organization_staff_members: { organization_id: Current.organization.id, archived_at: nil })
                                      .includes(organization_staff_member: { person: HEADSHOTS })
                                      .order("people.name").map(&:organization_staff_member)
      members.select! { |m| m.person.name.to_s.downcase.include?(q.downcase) } if q.length >= 2
      people = members.map(&:person)
      ids = people.map(&:id)

      resolver = StaffAvailabilityResolver.new(ids, from: shift.starts_at.to_date, to: shift.ends_at.to_date)
      on_shift = shift.active_assignments.pluck(:person_id).to_set
      day = shift.source.is_a?(Show) ? shift.source.date_and_time.to_date : shift.starts_at.to_date
      shows = Show.joins(:production).where(productions: { organization_id: Current.organization.id }, date_and_time: day.all_day).includes(:production)
      cast = ShowPersonRoleAssignment.where(show_id: shows.map(&:id), assignable_type: "Person", assignable_id: ids)
                                     .group_by(&:assignable_id).transform_values { |as| as.map(&:show_id).uniq }
      show_label = shows.index_by(&:id).transform_values { |show| "#{show.production&.name} (#{show.date_and_time.strftime("%-l:%M %p")})" }
      overlapping = Current.organization.shifts.where("starts_at < ? AND ends_at > ?", shift.ends_at, shift.starts_at).where.not(id: shift.id)
                                        .includes(:house_role, shift_assignments: []).to_a
      busy = overlapping.each_with_object(Hash.new { |h, k| h[k] = [] }) do |other, h|
        other.active_assignments.each do |a|
          h[a.person_id] << { role: other.house_role.name, day: other.starts_at.strftime("%a %b %-d"),
                              time_range: "#{other.starts_at.strftime("%-l:%M %p")}–#{other.ends_at.strftime("%-l:%M %p")}" }
        end
      end

      fit = params[:fit].presence_in(%w[all can_work free]) || "all"
      rows = people.map do |person|
        verdict = resolver.verdict(person.id, shift.starts_at, shift.ends_at)
        status = verdict.status.to_s
        { person: person, status: status,
          verdict: { status: status, badge: StaffAvailabilityWording.badge(verdict), detail: StaffAvailabilityWording.detail(verdict) },
          cast: (cast[person.id] || []).map { |id| show_label[id] }.compact, conflicts: busy[person.id] }
      end
      rows.select! { |r| r[:status] != "blocked" } if fit == "can_work"
      rows.select! { |r| r[:status].in?(%w[free unknown]) } if fit == "free"
      # Free first, then partly, hasn't said, can't; a clash that night (a
      # show, another shift) sorts after the clean ones of the same kind, and
      # whoever's on the shift already comes last. Alphabetical within each.
      rows.sort_by!.with_index do |r, i|
        rank = if on_shift.include?(r[:person].id) then 9
        else FIT.fetch(r[:status], 4) + ((r[:cast].any? || r[:conflicts].any?) ? 1 : 0)
        end
        [ rank, i ]
      end

      already = {}
      badges = Hash.new { |h, k| h[k] = [] }
      extras = {}
      rows.each do |r|
        key = "Person_#{r[:person].id}"
        if on_shift.include?(r[:person].id) then already[key] = "Assigned"
        elsif r[:cast].any? then badges[key] << "In a show"
        elsif r[:status] == "blocked" then badges[key] << "Unavailable"
        elsif r[:status] == "partial" then badges[key] << (r[:verdict][:badge] || "Partly available")
        elsif r[:status] == "unknown" then badges[key] << "Hasn't said"
        end
        badges[key] << "On another shift" if r[:conflicts].any? && !on_shift.include?(r[:person].id)
        extras[key] = { pick: { staff: { verdict: r[:verdict], cast: r[:cast], conflicts: r[:conflicts] } } }
      end

      render partial: "shared/people_picker/results",
             locals: { query: q, people: rows.map { |r| r[:person] }, groups: [], outside: [], already: already, badges: badges, ineligible: Set.new,
                       invite_email: nil, invite_name: false, guest: false, listing: true, extras: extras,
                       heading: "Qualified for #{role.name}",
                       empty: (fit == "all" ? "No one is qualified for this role yet." : "No one who can work this shift.") }
    end

    # Audition scheduling (V1.1 plan §5): the cycle's sign-ups for one
    # session, those marked available for it first (by yes votes), each
    # saying what they said, whether they're in this session (not pickable)
    # or another. Available / Everyone is fit=available|all; hide_scheduled=1
    # drops everyone already on the schedule.
    def search_auditionees(q)
      session = AuditionSession.joins(audition_cycle: :production)
                               .where(productions: { organization_id: Current.organization.id }).find(params[:audition_session_id])
      cycle = session.audition_cycle
      requests = cycle.audition_requests.active.includes(:requestable, :audition_request_votes).to_a
      requests.select! { |r| r.requestable&.name.to_s.downcase.include?(q.downcase) } if q.length >= 2
      requests.reject! { |r| r.requestable.nil? }

      availability = AuditionSessionAvailability.where(audition_session: session)
                                                .to_h { |a| [ "#{a.available_entity_type}_#{a.available_entity_id}", a.status.to_s ] }
      in_this = session.auditions.pluck(:audition_request_id).compact.to_set
      scheduled = Audition.joins(:audition_session).where(audition_sessions: { audition_cycle_id: cycle.id }).pluck(:audition_request_id).compact.to_set

      fit = params[:fit].presence_in(%w[available all]) || "available"
      hide_scheduled = params[:hide_scheduled] != "0"
      status_of = ->(r) { availability["#{r.requestable_type}_#{r.requestable_id}"] || "unset" }
      requests.select! { |r| status_of.call(r) == "available" } if fit == "available"
      requests.reject! { |r| scheduled.include?(r.id) || in_this.include?(r.id) } if hide_scheduled
      rank = { "available" => 0, "unset" => 1, "unavailable" => 2 }
      requests.sort_by! { |r| [ rank.fetch(status_of.call(r), 1), -r.vote_counts[:yes], r.created_at ] }

      already = {}
      badges = Hash.new { |h, k| h[k] = [] }
      extras = {}
      requests.each do |r|
        key = "#{r.requestable_type}_#{r.requestable_id}"
        status = status_of.call(r)
        badges[key] << { "available" => "Available", "unavailable" => "Unavailable" }.fetch(status, "No response")
        if in_this.include?(r.id) then already[key] = "In this session"
        elsif scheduled.include?(r.id) then badges[key] << "In another session"
        end
        vc = r.vote_counts
        extras[key] = { pick: { requestId: r.id, votes: vc },
                        detail: (vc.values.sum.zero? ? "No votes yet" : "#{vc[:yes]} yes · #{vc[:no]} no · #{vc[:maybe]} not sure") }
      end

      empty = if q.length >= 2 then "No auditionees match your search."
      elsif fit == "available" then "No one is marked available for this session. Switch to Everyone to see all auditionees."
      else "Everyone is already scheduled. Show the scheduled too to see them."
      end
      render partial: "shared/people_picker/results",
             locals: { query: q, people: requests.map(&:requestable), groups: [], outside: [], already: already, badges: badges, ineligible: Set.new,
                       invite_email: nil, invite_name: false, guest: false, listing: true, extras: extras,
                       heading: (fit == "available" ? "Available for this session" : "Auditionees"), empty: empty }
    end

    # A production's picker checks the production's managers; the rest the
    # organization's.
    def set_production_scope
      return if params[:production_id].blank?

      @production = Current.organization.productions.find(params[:production_id])
    end

    def talent_pool
      return nil if params[:talent_pool_id].blank?

      TalentPool.joins(:production).where(productions: { organization_id: Current.organization.id }).find_by(id: params[:talent_pool_id])
    end

    def search_members(org, q, scope)
      like = "%#{Person.sanitize_sql_like(q)}%"
      people = org.people.where("people.name ILIKE :like OR people.email ILIKE :like", like: like).includes(HEADSHOTS).order(:name).limit(20).to_a
      people.select! { |p| p.user_id.present? } if scope == "users"
      groups = scope == "members" ? org.groups.where("groups.name ILIKE ?", like).order(:name).limit(10).to_a : []
      [ people, groups ]
    end

    # The organization's people (and groups), for a page's list before a search.
    def org_members(org, scope)
      people = org.people.where(archived_at: nil).includes(HEADSHOTS).order(:name).limit(100).to_a
      people.select! { |p| p.user_id.present? } if scope == "users"
      groups = scope == "members" ? org.groups.order(:name).limit(30).to_a : []
      [ people, groups ]
    end

    # The production's talent pool, for a casting page's list before a search.
    def pool_members(scope)
      pool = @production.effective_talent_pool
      return [ [], [] ] unless pool

      people = pool.people.includes(HEADSHOTS).order(:name).limit(60).to_a
      groups = scope == "members" ? pool.groups.order(:name).limit(20).to_a : []
      [ people, groups ]
    end

    # "Available" or "Unavailable" for the show; on a linked event, how many
    # of its dates they're available for.
    def availability_badges(show, members)
      shows = [ show ] + show.linked_shows.to_a
      answers = ShowAvailability.where(show_id: shows.map(&:id))
                                .where(available_entity_type: members.map { |m| m.class.name }.uniq)
                                .group_by { |a| "#{a.available_entity_type}_#{a.available_entity_id}" }
      members.each_with_object({}) do |m, badges|
        key = "#{m.class.name}_#{m.id}"
        mine = answers[key] || []
        here = mine.find { |a| a.show_id == show.id }
        if shows.size > 1
          available = mine.count { |a| a.status == "available" }
          badges[key] =
            if available == shows.size then "Available"
            elsif available.positive? then "Available #{available} of #{shows.size} dates"
            elsif here&.status == "unavailable" then "Unavailable"
            end
        elsif here&.status.in?(%w[available unavailable])
          badges[key] = here.status.capitalize
        end
        badges.delete(key) if badges[key].nil?
      end
    end

    def key_for(id)
      id.to_s.include?("_") ? id.to_s : "Person_#{id.to_i}"
    end
  end
end
