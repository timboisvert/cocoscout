# frozen_string_literal: true

# The dates in a contractor's own production that follow a contract's dates
# (Show#linked_show; ContractConnection). Three rules (Tim, 2026-11-16):
#
#   1. The contract is the signed record. Every date on it arrives in the
#      contractor's production, however many, and follows it from then on:
#      its time, its length, whether it's on. Its place is the other
#      organization's venue, read through the link.
#   2. Nothing of the contractor's is overwritten. A date they already had
#      is never deleted, replaced or moved unless they said it's the same
#      show; then it's their date that carries on, with its cast, following
#      the contract.
#   3. Nothing is guessed. The same day and time is offered as a match; the
#      same day at another time is a question; anything else is left alone.
#
# A contract's dates are the shows on its bookings (space rentals), never
# "every show of the production", which changes when a second contract
# arrives.
class LinkedDates
  # How a production's own dates line up with a contract's, for the Your
  # dates step and for the summary on the last step.
  Comparison = Struct.new(:matches, :questions, :added, :theirs_only, :zone, :reasons, keyword_init: true) do
    # Why a date of theirs is offered for a contract date though the times
    # differ: :booking_start when theirs starts when the booking does (the
    # room is held from then; the show itself is later), else nil.
    def reason_for(contract_show, show) = (reasons || {})[[ contract_show.id, show.id ]]

    # What to start a question on: the one date that begins exactly when
    # the booking does is very likely the same show, entered with the
    # booking's time. It's still only a starting point: they choose.
    def likely_same(contract_show, candidates)
      likely = candidates.select { |show| reason_for(contract_show, show) == :booking_start }
      likely.first if likely.one? && candidates.one?
    end

    # Nothing of theirs to weigh against the contract: every date is new.
    def nothing_to_check? = matches.empty? && questions.empty? && theirs_only.empty?

    def summary_words(pair: nil, join: nil)
      pair = LinkedDates.plain(pair)
      joined = LinkedDates.plain(join).values.count(&:present?)
      same = pair.values.count { |value| value.to_s.match?(/\A\d+\z/) } + joined
      unsure = questions.count { |contract_show, _| !pair.key?(contract_show.id.to_s) || pair[contract_show.id.to_s] == "unsure" }
      fresh = added.size + questions.size + matches.size - same
      [ ("#{same} will be treated as the same show" if same.positive?),
        ("#{fresh} will be added from the contract" if fresh.positive?),
        ("#{unsure} #{unsure == 1 ? 'is' : 'are'} left as a question for later" if unsure.positive?) ].compact.to_sentence.presence || "there was nothing to compare"
    end
  end

  # How far apart two start times can be and still be asked about as the
  # same night.
  SAME_NIGHT = 4.hours

  class << self
    # Form answers as a plain hash with string keys, whether they came as
    # request parameters or a hash.
    def plain(answers)
      (answers.respond_to?(:to_unsafe_h) ? answers.to_unsafe_h : answers.to_h).transform_keys(&:to_s)
    end

    # The contract's dates: the shows on its bookings.
    def contract_shows(contract)
      Show.where(space_rental_id: contract.space_rentals.select(:id)).order(:date_and_time)
    end

    # Their own shows that could be one of the contract's: shows (not
    # rehearsals or meetings) that don't already follow something.
    def own_shows(production)
      production.shows.where(event_type: "show", linked_show_id: nil).order(:date_and_time)
    end

    def compare(contract, production)
      zone = Time.find_zone(contract.organization.time_zone.presence) || Time.zone
      theirs = own_shows(production).to_a
      taken = []
      matches = []
      questions = []
      added = []
      reasons = {}
      contract_shows(contract).where(canceled: false).includes(:space_rental).each do |contract_show|
        rental = contract_show.space_rental
        # Only shows are compared with their shows: a rehearsal or meeting on
        # the contract is simply added, as its own kind.
        if contract_show.event_type != "show"
          added << contract_show
          next
        end
        day = contract_show.date_and_time.in_time_zone(zone).to_date
        # The same night: the same day on the venue's clock, or within a few
        # hours either way (a show that runs past midnight, a load-in the
        # afternoon before), or inside the hours the room is booked for.
        same_night = theirs.reject { |show| taken.include?(show.id) || show.canceled }.select do |show|
          show.date_and_time.in_time_zone(zone).to_date == day ||
            (show.date_and_time - contract_show.date_and_time).abs <= SAME_NIGHT ||
            (rental && show.date_and_time.between?(rental.starts_at, rental.ends_at))
        end
        if (exact = same_night.find { |show| show.date_and_time == contract_show.date_and_time })
          taken << exact.id
          matches << [ contract_show, exact ]
        elsif same_night.any?
          same_night.each { |show| reasons[[ contract_show.id, show.id ]] = :booking_start if rental && show.date_and_time == rental.starts_at }
          questions << [ contract_show, same_night ]
        else
          added << contract_show
        end
      end
      asked = questions.flat_map(&:last).map(&:id)
      theirs_only = theirs.reject { |show| taken.include?(show.id) || asked.include?(show.id) || show.canceled || show.date_and_time < Time.current }
      Comparison.new(matches: matches, questions: questions, added: added, theirs_only: theirs_only, zone: zone, reasons: reasons)
    end

    # What they said on the Your dates step, checked against what's really
    # there and kept on the connection until it's accepted:
    #   "pairs"    { contract show id => their show id }   the same show
    #   "calls"    [ contract show ids ]                   keep their old time as the cast call
    #   "unsure"   [ [ contract show id, their show id ] ] left as a question
    def answers_from(contract, production, pair: nil, call: nil, join: nil)
      comparison = compare(contract, production)
      pair = plain(pair)
      join = plain(join)
      call = plain(call)
      pairs = {}
      unsure = []
      used = []
      choose = lambda do |contract_show, candidates, chosen|
        show = candidates.find { |candidate| candidate.id.to_s == chosen.to_s && !used.include?(candidate.id) }
        next false unless show

        used << show.id
        pairs[contract_show.id.to_s] = show.id
        true
      end

      comparison.matches.each { |contract_show, show| choose.call(contract_show, [ show ], pair[contract_show.id.to_s]) }
      comparison.questions.each do |contract_show, candidates|
        answer = pair[contract_show.id.to_s].to_s
        next if choose.call(contract_show, candidates, answer)

        candidates.each { |show| unsure << [ contract_show.id, show.id ] } unless answer == "separate"
      end
      # A date of theirs joined by hand to one of the contract's that nothing matched.
      comparison.theirs_only.each do |show|
        contract_show = comparison.added.find { |candidate| candidate.id.to_s == join[show.id.to_s].to_s && !pairs.key?(candidate.id.to_s) }
        choose.call(contract_show, [ show ], show.id) if contract_show
      end

      { "pairs" => pairs, "calls" => call.select { |_, value| value.to_s == "1" }.keys & pairs.keys, "unsure" => unsure }
    end

    # The production a connection asked to have made from the contract.
    def create_production!(connection)
      connection.linked_organization.productions.create!(name: connection.new_production_name.presence || connection.contract.production&.name)
    end

    # Accepted: every date on the contract goes into their production. A
    # date they said is the same show carries on, following the contract;
    # the rest arrive new, with nobody cast.
    def connect!(connection)
      production = connection.linked_production
      answers = connection.date_answers || {}
      pairs = (answers["pairs"] || {}).to_h
      calls = Array(answers["calls"]).map(&:to_s)
      apart do
        contract_shows(connection.contract).each do |contract_show|
          next if following(contract_show, production).exists?

          own = own_shows(production).find_by(id: pairs[contract_show.id.to_s])
          if own
            adopt!(own, contract_show, keep_call: calls.include?(contract_show.id.to_s))
          elsif !contract_show.canceled
            create_following!(production, contract_show)
          end
        end
      end
    end

    # Either side unlinked: the dates stay in their production as their own,
    # where they are, and stop following.
    def release!(connection)
      apart do
        following_for(connection).includes(linked_show: :location).find_each do |show|
          stand_alone!(show, venue: show.linked_show&.location, released_from: connection)
        end
      end
    end

    # The dates kept from a connection that has ended, still to come.
    def released_coming(connection)
      Show.where(released_connection_id: connection.id, canceled: false).where("shows.date_and_time > ?", Time.current).order(:date_and_time)
    end

    # Whether anyone is on a date: cast in it, or scheduled to work it.
    # Such a date is never removed for them: it's theirs to cancel, so the
    # people on it are notified the usual way.
    def people_on?(show)
      show.show_person_role_assignments.exists? || show.shift_shows.exists?
    end

    # After unlinking, the contractor's side removes the coming dates it
    # kept: the ones nobody is on. Returns [removed, kept because someone
    # is on them]. Past dates always stay.
    def remove_released!(connection)
      removed = kept = 0
      apart do
        released_coming(connection).find_each do |show|
          if people_on?(show)
            kept += 1
          else
            show.destroy!
            removed += 1
          end
        end
      end
      [ removed, kept ]
    end

    # A question left open on the Your dates step, answered later: the same
    # show after all (their own date carries on; the one that arrived from
    # the contract for it goes, if nobody was cast in it), or two events.
    def resolve!(connection, contract_show_id:, show_id:, same:)
      answers = (connection.date_answers || {}).deep_dup
      answers["unsure"] = Array(answers["unsure"]).reject { |pair| pair.map(&:to_i) == [ contract_show_id.to_i, show_id.to_i ] }
      if same
        contract_show = contract_shows(connection.contract).find(contract_show_id)
        own = own_shows(connection.linked_production).find(show_id)
        arrived = following(contract_show, connection.linked_production).first
        if arrived&.show_person_role_assignments&.exists?
          raise ArgumentError, "Both dates have people cast. Take the cast off one of them first."
        end

        apart do
          if arrived
            arrived.following_contract = true
            arrived.destroy!
          end
          adopt!(own, contract_show, keep_call: false)
        end
        answers["unsure"] = answers["unsure"].reject { |pair| pair.first.to_i == contract_show_id.to_i }
      end
      connection.update!(date_answers: answers)
    end

    # The questions still open on a connection: [ contract show, their show ].
    def open_questions(connection)
      return [] unless connection.connected? && connection.linked_production

      pairs = Array(connection.date_answers&.dig("unsure"))
      return [] if pairs.empty?

      contract_side = contract_shows(connection.contract).where(id: pairs.map(&:first)).index_by(&:id)
      own_side = own_shows(connection.linked_production).where(id: pairs.map(&:last), canceled: false).index_by(&:id)
      pairs.filter_map do |contract_show_id, show_id|
        contract_show = contract_side[contract_show_id.to_i]
        own = own_side[show_id.to_i]
        [ contract_show, own ] if contract_show && own && !contract_show.canceled && contract_show.date_and_time > Time.current
      end
    end

    # --- Keeping in step (Show's after_commit) ---

    # A contract date was saved: the dates that follow it take its time, its
    # length and whether it's on.
    def source_changed!(source)
      followers = Show.where(linked_show_id: source.id).to_a
      return if followers.empty?

      apart do
        followers.each do |show|
          changes = { date_and_time: source.date_and_time, duration_minutes: source.duration_minutes, canceled: source.canceled }
          next if changes.all? { |key, value| show.public_send(key) == value }

          show.following_contract = true
          show.update!(changes)
        end
      end
    end

    # A date was added to a contract that's connected: it arrives in their
    # production too.
    def source_added!(source)
      contract_id = SpaceRental.where(id: source.space_rental_id).pick(:contract_id)
      return unless contract_id

      ContractConnection.connected.where(contract_id: contract_id).includes(:linked_production).find_each do |connection|
        production = connection.linked_production
        next if production.nil? || source.canceled || following(source, production).exists?

        apart { create_following!(production, source) }
      end
    end

    # A contract date was removed. The dates that followed it stay where
    # they were, canceled, as the contractor's own record: nothing of theirs
    # is deleted from the other side.
    def source_removed!(show_ids, was:)
      return if show_ids.blank?

      apart do
        Show.where(id: show_ids).find_each do |show|
          stand_alone!(show, venue: was.location, canceled: true)
        end
      end
    end

    # The daily pass: anything a hook missed.
    def sweep!
      Show.where.not(linked_show_id: nil).includes(:linked_show).find_each do |show|
        source_changed!(show.linked_show) if show.linked_show
      rescue StandardError => e
        Rails.logger.error("[LinkedDates] sweep show #{show.id}: #{e.class}: #{e.message}")
      end
    end

    def following(contract_show, production)
      Show.where(linked_show_id: contract_show.id, production_id: production.id)
    end

    def following_for(connection)
      return Show.none unless connection.linked_production_id

      Show.where(production_id: connection.linked_production_id, linked_show_id: contract_shows(connection.contract).select(:id))
    end

    private

    def create_following!(production, contract_show)
      # The date keeps its kind: a contract can book rehearsals as well as
      # shows (Tim, 2026-11-18: "They're rehearsing at our theater"), and a
      # rehearsal arrives as a rehearsal, with casting as that kind starts.
      kind = contract_show.event_type.presence || "show"
      production.shows.create!(linked_show: contract_show, following_contract: true, event_type: kind,
                               casting_enabled: EventTypes.casting_enabled_default(kind),
                               date_and_time: contract_show.date_and_time, duration_minutes: contract_show.duration_minutes,
                               canceled: contract_show.canceled)
    end

    # Their own date becomes the one that follows: its cast, roles and notes
    # stay; its time and place become the contract's; it leaves any
    # repeating set it was part of.
    def adopt!(show, contract_show, keep_call:)
      was = show.date_and_time
      show.following_contract = true
      attributes = { linked_show: contract_show, date_and_time: contract_show.date_and_time, duration_minutes: contract_show.duration_minutes,
                     canceled: contract_show.canceled, location_id: nil, location_space_id: nil, is_online: false,
                     online_location_info: nil, recurrence_group_id: nil, released_connection_id: nil }
      # Their old time can stay as the cast call, when they asked for that
      # and the date had no call time of its own. One it already had is
      # theirs and is never touched.
      has_call = show.call_time_enabled? && show.call_time.present?
      attributes.merge!(call_time: was, call_time_enabled: true) if keep_call && !has_call && was != contract_show.date_and_time
      show.update!(attributes)
    end

    # A date that stops following: it needs a place of its own, so it gets
    # the contractor's own record of the venue (made if they have none by
    # that name).
    def stand_alone!(show, venue:, canceled: nil, released_from: nil)
      show.following_contract = true
      attributes = { linked_show_id: nil, location: own_record_of(venue, show.production.organization) }
      attributes[:released_connection_id] = released_from.id if released_from
      attributes[:is_online] = true if attributes[:location].nil?
      attributes[:canceled] = canceled unless canceled.nil?
      show.update!(attributes)
    end

    def own_record_of(venue, organization)
      return nil unless venue

      organization.locations.where("LOWER(name) = ?", venue.name.to_s.downcase).first ||
        organization.locations.create!(venue.slice("name", "address1", "address2", "city", "state", "postal_code"))
    end

    # The other organization's dates are changed from inside this one's
    # request. Their change records (ShowChanges) get a batch of their own
    # and no name on them, so nothing of one side's shows up in the other's
    # "people to notify" list.
    def apart(&block)
      Current.set(session: nil, show_change_batch: SecureRandom.uuid, &block)
    end
  end
end
