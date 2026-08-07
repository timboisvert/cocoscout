# frozen_string_literal: true

# What actually changed, in plain English.
#
# Asking someone to re-read a six-page contract to find the three numbers that
# moved is how you get people signing things they haven't read. This turns a
# staged amendment into a short list — "Your share goes from 40% to 50%. Two
# dates added." — shown beside the document on the signing page.
#
# It compares the staged amendment against the contract as it stands, so it
# only ever describes real differences.
class ContractAmendmentSummary
  # Reads from the counterparty's side ("your share"), since that's who's being
  # asked to sign. Pass perspective: :org for the producer-facing view.
  def self.lines(contract, amendment, perspective: :counterparty)
    new(contract, amendment, perspective).lines
  end

  def initialize(contract, amendment, perspective = :counterparty)
    @contract = contract
    @amendment = (amendment || {}).with_indifferent_access
    @perspective = perspective
  end

  def lines
    [
      production_name_line,
      *money_lines,
      *date_lines,
      services_line,
      ticketing_line
    ].compact
  end

  private

  attr_reader :contract, :amendment

  def theirs = @perspective == :counterparty ? "Your" : "Their"
  def them = @perspective == :counterparty ? "you" : "them"

  def production_name_line
    staged = amendment[:production_name].to_s.strip
    return if staged.blank? || staged == contract.production_name.to_s

    "Renamed to #{staged}."
  end

  def money_lines
    return [] unless amendment.key?(:payment_config)

    old = contract.draft_payment_config || {}
    new = amendment[:payment_config] || {}
    out = []

    out << share_line(old, new)
    out << fee_line(old, new)
    out << settlement_line(old, new)
    out << structure_line
    out.compact
  end

  def share_line(old, new)
    was = old["revenue_their_share"].presence
    now = new["revenue_their_share"].presence
    return if now.blank? || was.to_s == now.to_s

    was.present? ? "#{theirs} share goes from #{was}% to #{now}%." : "#{theirs} share is #{now}%."
  end

  def fee_line(old, new)
    was = old["flat_fee_amount"].to_f
    now = new["flat_fee_amount"].to_f
    return if now.zero? || was == now

    was.positive? ? "The fee goes from #{money(was)} to #{money(now)}." : "A fee of #{money(now)} is added."
  end

  def settlement_line(old, new)
    was = old["flat_fee_settlement"].presence || old["revenue_settlement"].presence
    now = new["flat_fee_settlement"].presence || new["revenue_settlement"].presence
    return if now.blank? || was.to_s == now.to_s

    "Settling #{settlement_label(now)} instead of #{was.present? ? settlement_label(was) : 'as before'}."
  end

  def settlement_label(value)
    {
      "once" => "once at the end", "per_event" => "after each show",
      "weekly" => "weekly", "monthly" => "monthly",
      "same_day" => "the same day", "next_day" => "the next business day"
    }[value.to_s] || value.to_s.humanize.downcase
  end

  def structure_line
    return unless amendment.key?(:payment_structure)

    was = contract.draft_payment_structure
    now = amendment[:payment_structure]
    return if was.to_s == now.to_s || now.blank?

    "How the money works changes to #{now.to_s.humanize.downcase}."
  end

  def date_lines
    out = []

    added = Array(amendment[:new_bookings]).filter_map do |b|
      Time.zone.parse(b[:starts_at].to_s)&.strftime("%b %-d")
    rescue ArgumentError, TypeError
      nil
    end
    if added.any?
      out << "#{added.size == 1 ? 'One date added' : "#{added.size} dates added"}: #{added.to_sentence}."
    end

    removed_ids = Array(amendment[:removed_rental_ids]).map(&:to_i).reject(&:zero?)
    if removed_ids.any?
      dates = contract.space_rentals.where(id: removed_ids).order(:starts_at).map { |r| r.starts_at.strftime("%b %-d") }
      label = dates.any? ? ": #{dates.to_sentence}" : ""
      out << "#{removed_ids.size == 1 ? 'One date removed' : "#{removed_ids.size} dates removed"}#{label}."
    end

    out
  end

  def services_line
    return unless amendment.key?(:services)

    was = names_of(contract.draft_services)
    now = names_of(amendment[:services])
    return if was.sort == now.sort

    added = now - was
    dropped = was - now
    bits = []
    bits << "#{added.to_sentence} added" if added.any?
    bits << "#{dropped.to_sentence} removed" if dropped.any?
    bits.any? ? "Services: #{bits.join(', ')}." : "The services on this contract changed."
  end

  def names_of(services)
    Array(services).filter_map { |s| (s.is_a?(Hash) ? (s["name"] || s[:name]) : nil).presence }
  end

  def ticketing_line
    return unless amendment.key?(:ticketing)
    return if amendment[:ticketing] == contract.draft_ticketing

    "Ticket prices or discounts have changed."
  end

  def money(amount)
    ActionController::Base.helpers.number_to_currency(amount)
  end
end
