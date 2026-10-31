# frozen_string_literal: true

# A buyer's access needs for their visit (accessibility plan §4): optional,
# seen by the box office and the door for that show only, never in exports
# or mailing lists, deleted 30 days after the show (PurgeAccessRequestsJob).
class TicketOrderAccessRequest < ApplicationRecord
  KEYS = %w[wheelchair_space step_free listening_headset see_interpreter step_out service_animal meet_at_door].freeze
  LABELS = { "wheelchair_space" => "A wheelchair space", "step_free" => "A step-free route in", "listening_headset" => "A listening headset",
             "see_interpreter" => "Seats where we can see the interpreter", "step_out" => "May need to step out and come back",
             "service_animal" => "A service animal is coming", "meet_at_door" => "Someone to meet us at the door" }.freeze
  SHORT = { "wheelchair_space" => "wheelchair space", "step_free" => "step-free route", "listening_headset" => "listening headset",
            "see_interpreter" => "see the interpreter", "step_out" => "may step out", "service_animal" => "service animal", "meet_at_door" => "meet at the door" }.freeze
  KEEP_FOR = 30.days

  belongs_to :ticket_order

  validates :note, length: { maximum: 500 }

  def request_keys=(keys)
    super(Array(keys).map(&:to_s).select { |k| KEYS.include?(k) }.uniq)
  end

  def empty? = request_keys.empty? && note.blank?
  def words = (request_keys.map { |k| SHORT.fetch(k) } + [ note.presence ].compact).join(", ")

  # The buyer's answers, saved on every order of a purchase (one per show).
  def self.record!(orders, keys:, note:)
    orders.each do |order|
      request = order.access_request || order.build_access_request
      request.assign_attributes(request_keys: keys, note: note.to_s.strip.presence)
      request.empty? ? request.destroy : request.save!
    end
  end
end
