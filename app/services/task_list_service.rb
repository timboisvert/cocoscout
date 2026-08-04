# frozen_string_literal: true

# The single source of truth for a talent user's "My Tasks" list:
# availability requests, sign-ups, and questionnaires, split into
# open (needs a response) and answered/completed lists.
#
# Used by the My Tasks page, the sidebar nav badge, and the dashboard
# summary card — counts are derived from the same item lists the page
# renders, so the badge can never disagree with the page.
#
#   service = TaskListService.new(user)                    # full page mode
#   TaskListService.open_count(user)                       # cheap badge mode
#
# include_details: false skips view-only eager loads and the extra lists
# (non-event sign-ups, completed questionnaires) that never affect counts.
class TaskListService
  # How far ahead we ask about shows. The nav badge historically used 90
  # days while the page used 120 — unified here.
  UPCOMING_WINDOW = 120.days

  attr_reader :user, :people, :groups,
              :open_availability_items, :answered_availability_items,
              :open_signup_items, :answered_signup_items,
              :non_event_signups,
              :open_questionnaire_items, :completed_questionnaire_items

  def self.open_count(user)
    new(user, include_details: false).counts[:total]
  end

  def initialize(user, selected_person_ids: nil, selected_group_ids: nil, include_details: true)
    @user = user
    @include_details = include_details

    @people = user ? user.people.active.order(:created_at).to_a : []
    @people_by_id = @people.index_by(&:id)

    @groups = if @people.any?
                Group.active
                     .joins(:group_memberships)
                     .where(group_memberships: { person_id: @people_by_id.keys })
                     .distinct
                     .order(:name)
                     .to_a
    else
                []
    end
    @groups_by_id = @groups.index_by(&:id)

    @selected_person_ids = selected_person_ids || @people_by_id.keys
    @selected_group_ids = selected_group_ids || @groups_by_id.keys

    load_show_items
    load_questionnaire_items
    load_non_event_signups
  end

  # Awaiting-only counts — what the badge and section pills show.
  def counts
    @counts ||= {
      availability: open_availability_items.size,
      signups: open_signup_items.size,
      questionnaires: open_questionnaire_items.size,
      total: open_availability_items.size + open_signup_items.size + open_questionnaire_items.size
    }
  end

  # Whether the user is reachable through any production's talent pools at
  # all (drives the "No productions" empty state vs "all caught up").
  def any_productions?
    return @any_productions if defined?(@any_productions)

    productions_exist = @people.any? &&
      Production.joins(talent_pools: :people).where(people: { id: @people_by_id.keys }).exists?
    groups_in_productions = @groups.any? { |g| g.talent_pool_memberships.joins(talent_pool: :production).exists? }
    @any_productions = productions_exist || groups_in_productions
  end

  # Builds a single sign-up item hash, computing the declined state with
  # per-item queries. Used by the sign-up/decline actions to re-render one
  # row; the batch path in load_show_items prefetches these sets instead.
  def self.build_signup_item(show, person, instance, registration, declined: false)
    declined ||= ShowAvailability.exists?(
      show_id: show.id,
      available_entity_type: "Person",
      available_entity_id: person.id,
      status: "unavailable"
    ) || SignUpRegistration.joins(sign_up_slot: { sign_up_form_instance: :show })
                           .where(shows: { id: show.id })
                           .where(person_id: person.id)
                           .where(status: "cancelled")
                           .exists?

    signup_item(show, person, instance, registration, declined: declined)
  end

  def self.signup_item(show, person, instance, registration, declined:)
    {
      type: :signup,
      show: show,
      entity: person,
      entity_type: "Person",
      entity_key: "person_#{person.id}",
      instance: instance,
      registration: registration,
      declined: declined
    }
  end

  private

  def load_show_items
    @open_availability_items = []
    @answered_availability_items = []
    @open_signup_items = []
    @answered_signup_items = []

    all_shows_with_source = collect_shows_with_source
    show_ids = all_shows_with_source.map { |item| item[:show].id }.uniq
    return if show_ids.empty?

    # Shows with active sign-up forms are sign-up tasks; everything else is
    # an availability request.
    shows_with_signup = SignUpFormInstance.joins(:sign_up_form)
                                          .where(show_id: show_ids)
                                          .where(status: %w[scheduled open])
                                          .where(sign_up_forms: { archived_at: nil })
                                          .pluck(:show_id)
                                          .to_set

    availabilities = fetch_availabilities(show_ids)

    registrations = if @selected_person_ids.any?
                      SignUpRegistration.joins(sign_up_slot: { sign_up_form_instance: :show })
                                        .where(shows: { id: show_ids })
                                        .where(person_id: @selected_person_ids)
                                        .where.not(status: "cancelled")
                                        .includes(sign_up_slot: :sign_up_form_instance)
                                        .index_by { |r| [ r.sign_up_slot.sign_up_form_instance.show_id, r.person_id ] }
    else
                      {}
    end

    # Prefetched declined signals (one query each, not per item):
    # an "unavailable" answer or a cancelled registration both mean "no".
    declined_pairs = ShowAvailability.where(show_id: show_ids, available_entity_type: "Person",
                                            available_entity_id: @selected_person_ids, status: "unavailable")
                                     .pluck(:show_id, :available_entity_id)
                                     .to_set
    if @selected_person_ids.any?
      declined_pairs.merge(
        SignUpRegistration.joins(sign_up_slot: { sign_up_form_instance: :show })
                          .where(shows: { id: show_ids })
                          .where(person_id: @selected_person_ids)
                          .where(status: "cancelled")
                          .pluck("shows.id", :person_id)
      )
    end

    all_shows_with_source.each do |item|
      show = item[:show]
      entity = item[:entity]

      if shows_with_signup.include?(show.id)
        # Sign-up tasks exist for people only, never groups.
        next unless item[:entity_type] == "Person"

        instance = show.sign_up_form_instances.find { |i|
          %w[scheduled open].include?(i.status) && i.sign_up_form&.archived_at.nil?
        }
        next unless instance

        form = instance.sign_up_form
        if instance.status == "scheduled"
          # Form not yet open — only visible when talent self pre-registration
          # is allowed and we're inside the window.
          next unless form.allows_talent_self_pre_registration? && form.pre_registration_open_for?(show)
        end

        registration = registrations[[ show.id, entity.id ]]
        declined = declined_pairs.include?([ show.id, entity.id ])
        signup_item = self.class.signup_item(show, entity, instance, registration, declined: declined)

        if registration.nil? && !declined
          @open_signup_items << signup_item
        else
          @answered_signup_items << signup_item
        end
      else
        availability = availabilities[[ show.id, item[:entity_type], entity.id ]]
        availability_item = {
          type: :availability,
          show: show,
          entity: entity,
          entity_type: item[:entity_type],
          entity_key: item[:entity_key],
          availability: availability
        }

        # A row that exists but was never actually answered (status "unset")
        # still needs a response.
        if availability.nil? || availability.unset?
          @open_availability_items << availability_item
        else
          @answered_availability_items << availability_item
        end
      end
    end

    [ @open_availability_items, @answered_availability_items,
      @open_signup_items, @answered_signup_items ].each do |list|
      list.sort_by! { |i| i[:show].date_and_time }
    end
  end

  def collect_shows_with_source
    all_shows_with_source = []

    if @selected_person_ids.any?
      upcoming_pool_shows(production: { talent_pools: :people }, source: :people, ids: @selected_person_ids).each do |s|
        add_show_source(all_shows_with_source, s, :source_person_id, @people_by_id, "Person", "person")
      end
      upcoming_pool_shows(production: { talent_pool_shares: { talent_pool: :people } }, source: :people, ids: @selected_person_ids).each do |s|
        add_show_source(all_shows_with_source, s, :source_person_id, @people_by_id, "Person", "person", dedupe: true)
      end
    end

    if @selected_group_ids.any?
      upcoming_pool_shows(production: { talent_pools: :groups }, source: :groups, ids: @selected_group_ids).each do |s|
        add_show_source(all_shows_with_source, s, :source_group_id, @groups_by_id, "Group", "group")
      end
      upcoming_pool_shows(production: { talent_pool_shares: { talent_pool: :groups } }, source: :groups, ids: @selected_group_ids).each do |s|
        add_show_source(all_shows_with_source, s, :source_group_id, @groups_by_id, "Group", "group", dedupe: true)
      end
    end

    all_shows_with_source
  end

  def upcoming_pool_shows(production:, source:, ids:)
    id_column = source == :people ? "people.id as source_person_id" : "groups.id as source_group_id"
    source_table = source == :people ? :people : :groups

    scope = Show.joins(production: production)
                .select("shows.*, #{id_column}")
                .where(source_table => { id: ids })
                .where.not(canceled: true)
                .where("date_and_time > ?", Time.current)
                .where("date_and_time <= ?", UPCOMING_WINDOW.from_now)
                .where.not(productions: { production_type: "course" })
                .distinct

    scope = if @include_details
              scope.includes(:production, :location, :event_linkage, sign_up_form_instances: :sign_up_form)
    else
              scope.includes(sign_up_form_instances: :sign_up_form)
    end

    scope.to_a
  end

  def add_show_source(list, show, id_attr, entities_by_id, entity_type, key_prefix, dedupe: false)
    entity_id = show.read_attribute(id_attr)
    entity = entities_by_id[entity_id]
    return unless entity

    entity_key = "#{key_prefix}_#{entity_id}"
    return if dedupe && list.any? { |item| item[:show].id == show.id && item[:entity_key] == entity_key }

    list << { show: show, entity_key: entity_key, entity: entity, entity_type: entity_type }
  end

  def fetch_availabilities(show_ids)
    conditions = []
    params = []

    @selected_person_ids.each do |pid|
      conditions << "(available_entity_type = 'Person' AND available_entity_id = ?)"
      params << pid
    end
    @selected_group_ids.each do |gid|
      conditions << "(available_entity_type = 'Group' AND available_entity_id = ?)"
      params << gid
    end

    return {} if conditions.empty?

    ShowAvailability.where(show_id: show_ids)
                    .where(conditions.join(" OR "), *params)
                    .index_by { |a| [ a.show_id, a.available_entity_type, a.available_entity_id ] }
  end

  def load_questionnaire_items
    @open_questionnaire_items = []
    @completed_questionnaire_items = []
    return unless @selected_person_ids.any?

    questionnaire_ids = QuestionnaireInvitation.where(invitee_type: "Person", invitee_id: @selected_person_ids)
                                               .pluck(:questionnaire_id)
                                               .uniq
    return if questionnaire_ids.empty?

    questionnaires = Questionnaire.where(id: questionnaire_ids)
                                  .includes(:organization, :production, :questionnaire_invitations, :questionnaire_responses)

    # Invitation contexts (e.g. course offerings) give the display label.
    invitations_with_context = QuestionnaireInvitation
      .where(invitee_type: "Person", invitee_id: @selected_person_ids, questionnaire_id: questionnaire_ids)
      .where.not(context_type: nil)
      .includes(context: :production)
      .group_by { |i| [ i.questionnaire_id, i.invitee_id ] }

    questionnaires.each do |questionnaire|
      next if questionnaire.archived_at.present?
      next unless questionnaire.accepting_responses

      @selected_person_ids.each do |person_id|
        person = @people_by_id[person_id]
        next unless person
        next unless questionnaire.questionnaire_invitations.any? { |i| i.invitee_id == person_id && i.invitee_type == "Person" }

        responded = questionnaire.questionnaire_responses.any? { |r| r.respondent_id == person_id && r.respondent_type == "Person" }

        # Badge mode only needs the open ones for counting.
        next if responded && !@include_details

        invitation_context = invitations_with_context[[ questionnaire.id, person_id ]]&.first&.context
        context_name = if invitation_context.is_a?(CourseOffering)
                         invitation_context.title
        elsif questionnaire.production
                         questionnaire.production.name
        end

        item = {
          questionnaire: questionnaire,
          entity: person,
          entity_key: "person_#{person_id}",
          responded: responded,
          context_name: context_name
        }
        (responded ? @completed_questionnaire_items : @open_questionnaire_items) << item
      end
    end

    [ @open_questionnaire_items, @completed_questionnaire_items ].each do |list|
      list.sort_by! { |i| i[:questionnaire].created_at }.reverse!
    end
  end

  # Sign-ups on shared_pool forms (not tied to a specific event). Read-only
  # rows on the page; never counted as open tasks.
  def load_non_event_signups
    @non_event_signups = []
    return unless @include_details && @selected_person_ids.any?

    registrations = SignUpRegistration
      .eager_load(sign_up_slot: { sign_up_form_instance: :show, sign_up_form: :production })
      .where(person_id: @selected_person_ids)
      .where.not(status: "cancelled")
      .to_a
      .select do |reg|
        form = reg.sign_up_slot&.sign_up_form
        next false unless form&.shared_pool? && !form.archived? && form.active?
        form.status_service&.accepting_registrations? || reg.status == "confirmed"
      end

    registrations.group_by { |r| r.sign_up_slot&.sign_up_form }.each do |form, regs|
      next unless form

      @non_event_signups << {
        form: form,
        production: form.production,
        registrations: regs,
        people: regs.map { |r| @people_by_id[r.person_id] }.compact.uniq
      }
    end

    @non_event_signups.sort_by! { |item| item[:form].name.downcase }
  end
end
