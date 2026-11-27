# frozen_string_literal: true

# Words for the Cancel or move this date screens (Manage::DateChangesController).
module DateChangesHelper
  # What a move does on its own, without a choice.
  def move_automatic(change, dests)
    moving = Array(dests).select(&:moves?)
    return [] if moving.empty?

    lead = moving.reject(&:linked_to).first || moving.first
    one = moving.reject(&:linked_to).size == 1
    lines = []
    linked = moving.select(&:linked_to)
    if linked.any?
      names = linked.map { |d| d.show.display_name.presence || d.show.production.name }.uniq.to_sentence
      lines << "#{names} #{linked.size == 1 ? 'moves' : 'move'} with #{one ? 'it' : 'them'}, by as much, with #{linked.size == 1 ? 'its' : 'their'} cast."
    end
    if TicketListing.where(show_id: moving.map { |d| d.show.id }).exists?
      lines << (one ? "Online sales close at #{lead.now_starts.strftime('%A')}'s showtime instead of #{lead.was_starts.strftime('%A')}'s." : "Online sales close at each date's new showtime.")
    end
    lines << "Reminders go out for the new #{one ? 'date' : 'dates'}."
    lines << "Your calendar, public pages#{GoogleCalendarSync.on_for?(change.organization_id) ? ', and Google Calendar' : ''} show the new #{one ? 'date' : 'dates'}."
    lines << "The #{one ? "date's" : "dates'"} money, settle up, and cast pay go with #{one ? 'it' : 'them'}."
    lines
  end

  # Why something didn't work, without the payment provider's name (never
  # said to people) or its internal ids.
  def date_change_reason(text)
    text.to_s.sub(/\AStripe couldn't refund it: /, "The card payment couldn't be refunded: ")
        .gsub(/No such payment_intent: '[^']*'/, "the original payment can't be found")
        .gsub(/\bStripe\b/, "the payment processor")
  end

  def date_change_time(time) = "#{time.strftime('%a, %b %-d')}, #{time.strftime('%-l:%M %p').strip}"

  def date_change_kind_word(change)
    { "cancel" => "Canceled", "move" => "Moved", "restore" => "Brought back", "delete" => "Deleted" }[change.kind]
  end
end
