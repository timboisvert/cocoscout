# frozen_string_literal: true

# What happens to a contractor's request about a contract date
# (ContractDateRequest): asking, the organization's answer, taking it back,
# and closing it by itself when the contract comes to say what was asked or
# the request stops applying. Every step that someone is waiting on notifies
# them (ContractDateRequestNotices).
class ContractDateRequests
  class NotAllowed < StandardError; end

  # Who may ask about this contract's dates: the contractor themself (the
  # person who signs it), on a contract that's live.
  def self.can_ask?(user, contract)
    return false unless user && contract
    return false unless contract.status_active?

    contract.payee_among?(user.people.pluck(:id))
  end

  # The dates a request can be about: the contract's own, still to come.
  def self.askable_shows(contract)
    contract.contract_shows.where(canceled: false).where("shows.date_and_time > ?", Time.current).order(:date_and_time)
  end

  # A new request. One waits per date: asking again about the same date
  # takes the earlier one back. Raises ActiveRecord::RecordInvalid with the
  # reason when it can't be asked.
  def self.ask!(contract:, user:, kind:, show: nil, proposed_at: nil, note: nil)
    raise NotAllowed unless can_ask?(user, contract)
    raise NotAllowed if show && !askable_shows(contract).exists?(id: show.id)

    request = ContractDateRequest.transaction do
      contract.date_requests.waiting.where(show_id: show.id).find_each { |earlier| close!(earlier, "withdrawn") } if show
      contract.date_requests.create!(
        organization: contract.organization, show: show, kind: kind, requested_by: user,
        original_at: show&.date_and_time, proposed_at: proposed_at, note: note.to_s.strip.presence
      )
    end
    ContractDateRequestNotices.asked(request)
    request
  end

  # The asker takes it back.
  def self.withdraw!(request, user:)
    raise NotAllowed unless mine?(request, user)

    close!(request, "withdrawn") if request.waiting?
    request
  end

  # The asker clears an answer from their page.
  def self.dismiss!(request, user:)
    raise NotAllowed unless mine?(request, user)

    request.update!(dismissed_at: Time.current) unless request.waiting?
    request
  end

  # The organization's "no": the date stays as it is, with their reason.
  def self.keep!(request, user:, note: nil)
    return request unless request.open?

    request.update!(status: "kept", answered_by: user, answered_at: Time.current,
                    answer_note: note.to_s.strip.presence, closed_at: Time.current)
    ContractDateRequestNotices.kept(request)
    request
  end

  # After anything changes a contract's dates (Show's after_commit, the daily
  # pass): close the requests it answered, and the ones that no longer apply.
  def self.settle!(contract, by: nil)
    contract.date_requests.waiting.includes(:show, :organization).find_each do |request|
      if request.satisfied?
        answerer = request.answered_by || (by unless by&.id == request.requested_by_id)
        request.update!(status: "done", answered_by: answerer, answered_at: request.answered_at || Time.current, closed_at: Time.current)
        ContractDateRequestNotices.done(request)
      elsif request.lapsed?
        close!(request, "void")
      end
    end
  end

  # An amendment that waits for the contractor's signature: the requests it
  # answers say so, and close when it's signed and its dates change.
  # `amend` is the staged amendment (Contract#amend_data's shape).
  def self.staged!(contract, amend, by: nil)
    moved = (amend["moved_rentals"] || {}).to_h
    removed = Array(amend["removed_rental_ids"]).map(&:to_i)
    added = Array(amend["new_bookings"]).filter_map { |booking| ContractDateChanges.parse_time(booking["event_starts_at"].presence || booking["starts_at"]) }

    contract.date_requests.where(status: "open").includes(show: :space_rental).find_each do |request|
      rental = request.show&.space_rental
      covered = case request.kind
      when "move" then rental && staged_show_start(request.show, rental, moved[rental.id.to_s]) == request.proposed_at
      when "cancel" then rental && removed.include?(rental.id)
      when "add" then added.include?(request.proposed_at)
      end
      next unless covered

      request.update!(status: "amending", answered_by: by, answered_at: Time.current)
      ContractDateRequestNotices.amending(request)
    end
  end

  # The Change dates screen, opened from a request: which booking it's
  # about and what to fill in. { rental_id => { action: "move" | "remove",
  # times: { starts_at:, ends_at:, event_starts_at:, event_ends_at: } } }.
  # The whole night moves by as much as the show was asked to.
  def self.amend_prefill(request)
    rental = request&.show&.space_rental
    return {} unless rental && request.waiting?

    case request.kind
    when "cancel" then { rental.id => { action: "remove" } }
    when "move"
      offset = request.proposed_at - request.show.date_and_time
      { rental.id => { action: "move", times: {
        starts_at: rental.starts_at + offset, ends_at: rental.ends_at + offset,
        event_starts_at: rental.event_starts_at && rental.event_starts_at + offset,
        event_ends_at: rental.event_ends_at && rental.event_ends_at + offset
      } } }
    else {}
    end
  end

  # The daily pass: close what the calendar has passed by, and remind the
  # organization once about a request nobody has answered.
  def self.sweep!(now: Time.current)
    ContractDateRequest.waiting.includes(:show, :organization, :contract).find_each do |request|
      if request.satisfied? || request.lapsed?
        settle!(request.contract)
      elsif request.open? && request.reminded_at.nil? && request.created_at < now - ContractDateRequest::REMIND_AFTER
        request.update!(reminded_at: now)
        ContractDateRequestNotices.reminder(request)
      end
    rescue StandardError => e
      Rails.logger.error("[ContractDateRequests] request #{request.id}: #{e.class}: #{e.message}")
    end
  end

  def self.mine?(request, user)
    request.requested_by_id == user.id || request.contract.payee_among?(user.people.pluck(:id))
  end
  private_class_method :mine?

  # When the show would start under a staged move of its booking: it moves
  # by as much as the show's time inside the booking does (retime!).
  def self.staged_show_start(show, rental, value)
    return nil if value.blank?

    times = ContractDateChanges.staged_times(rental, value)
    times && show.date_and_time + ((times[:event_starts_at] || times[:starts_at]) - rental.effective_event_starts_at)
  end
  private_class_method :staged_show_start

  def self.close!(request, status)
    request.update!(status: status, closed_at: Time.current)
  end
  private_class_method :close!
end
