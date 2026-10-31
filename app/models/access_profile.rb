# frozen_string_literal: true

# A location's or room's accessibility, answers merged (a room inherits the
# location's unless it says "different here"), summed up in plain words for
# guests and for performers and crew (accessibility plan §1). We describe;
# we never certify.
class AccessProfile
  attr_reader :owner, :location, :room

  def self.for(owner) = new(owner)

  def initialize(owner)
    @owner = owner
    @room = owner.is_a?(LocationSpace) ? owner : nil
    @location = @room ? @room.location : owner
  end

  def location_answers = @location_answers ||= location.access_answers.index_by(&:feature_key)
  def room_answers = @room_answers ||= room ? room.access_answers.index_by(&:feature_key) : {}

  # The answer that applies here: the room's own, else the location's.
  def record(key) = room_answers[key.to_s] || location_answers[key.to_s]
  def answer(key) = record(key)&.answer
  def note(key) = record(key)&.note
  def inherited?(key) = room.present? && room_answers[key.to_s].nil?
  def yes?(key) = answer(key) == "yes"
  def answered? = AccessFeatures::KEYS.any? { |k| answer(k) }

  # Who to ask: the location's access contact.
  def contact_email = location.access_email.presence
  def contact_phone = location.access_phone.presence

  # The yeses for an audience, as short words, in catalog order.
  def chips(audience = :guests)
    AccessFeatures::CATALOG.select { |f| audience == :guests ? f.guests? : f.backstage? }
                           .select { |f| yes?(f.key) || (f.key == "wheelchair_spaces" && room&.wheelchair_spaces.to_i.positive?) }
                           .map { |f| chip_for(f.key) }
  end

  # One line for a guest: "Step-free entrance, 2 wheelchair spaces, accessible
  # restroom, hearing loop or headsets". Nil when nothing's answered.
  def guest_summary
    words = chips(:guests)
    return nil if words.empty?

    sentence(words.first(5))
  end

  # One line for performers and crew.
  def backstage_summary
    words = chips(:backstage)
    words.empty? ? nil : sentence(words)
  end

  # "Step-free entrance, accessible restroom": the first word capped, the rest not.
  def sentence(words)
    words.map.with_index { |w, i| i.zero? || w.match?(/\A\d/) ? w : w[0].downcase + w[1..] }.join(", ")
  end

  # A line for a page: the summary, or an honest "not listed yet".
  def guest_words = guest_summary || "Accessibility details not listed yet"

  private

  def chip_for(key)
    if key == "wheelchair_spaces" && room&.wheelchair_spaces.to_i.positive?
      "#{room.wheelchair_spaces} wheelchair #{'space'.pluralize(room.wheelchair_spaces)}"
    else
      AccessFeatures::CHIP_WORDS.fetch(key)
    end
  end
end
