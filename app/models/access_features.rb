# frozen_string_literal: true

# The fixed list of accessibility features every organization answers
# (accessibility plan §1): grouped, labeled, each for guests, for performers
# and crew, or both. Keys are permanent; the list can grow.
module AccessFeatures
  Feature = Struct.new(:key, :label, :audience, keyword_init: true) do
    def guests? = audience != :backstage
    def backstage? = audience != :guests
  end

  GROUPS = [
    { key: "getting_in", label: "Getting there and in", features: [
      Feature.new(key: "step_free_entry", label: "Step-free route from the street", audience: :both),
      Feature.new(key: "accessible_parking", label: "Accessible parking or drop-off", audience: :both),
      Feature.new(key: "lift", label: "Lift to every public floor", audience: :both),
      Feature.new(key: "wide_doors", label: "Automatic or wide doors", audience: :both)
    ] },
    { key: "seating", label: "Seating and the room", features: [
      Feature.new(key: "wheelchair_spaces", label: "Wheelchair spaces", audience: :guests),
      Feature.new(key: "transfer_seats", label: "Transfer seats (aisle seat, armrest lifts)", audience: :guests),
      Feature.new(key: "easy_access_seats", label: "Seats near an exit with no steps", audience: :guests),
      Feature.new(key: "waiting_seating", label: "Seating while waiting", audience: :guests)
    ] },
    { key: "restrooms", label: "Restrooms", features: [
      Feature.new(key: "accessible_restroom", label: "Accessible restroom for guests", audience: :guests),
      Feature.new(key: "all_gender_restroom", label: "All-gender restroom", audience: :guests),
      Feature.new(key: "changing_table", label: "Adult changing table", audience: :guests)
    ] },
    { key: "senses", label: "Hearing, sight, senses", features: [
      Feature.new(key: "assistive_listening", label: "Assistive listening (loop or headsets)", audience: :guests),
      Feature.new(key: "large_print", label: "Large print or braille programs", audience: :guests),
      Feature.new(key: "quiet_room", label: "Quiet room", audience: :guests),
      Feature.new(key: "service_animals", label: "Service animals welcome", audience: :guests)
    ] },
    { key: "backstage", label: "Backstage", features: [
      Feature.new(key: "step_free_stage", label: "Step-free route to the stage", audience: :backstage),
      Feature.new(key: "accessible_dressing_room", label: "Accessible dressing room", audience: :backstage),
      Feature.new(key: "backstage_restroom", label: "Accessible backstage restroom", audience: :backstage),
      Feature.new(key: "accessible_stage_door", label: "Accessible stage door", audience: :backstage)
    ] }
  ].freeze
  CATALOG = GROUPS.flat_map { |g| g[:features] }.freeze
  BY_KEY = CATALOG.index_by(&:key).freeze
  KEYS = BY_KEY.keys.freeze

  ANSWERS = %w[yes no ask].freeze
  ANSWER_LABELS = { "yes" => "Yes", "no" => "No", "ask" => "Ask us" }.freeze

  # Short words for a yes, in the summaries and the pop-up chips.
  CHIP_WORDS = {
    "step_free_entry" => "Step-free entrance", "accessible_parking" => "Accessible parking", "lift" => "Lift", "wide_doors" => "Wide doors",
    "wheelchair_spaces" => "Wheelchair spaces", "transfer_seats" => "Transfer seats", "easy_access_seats" => "Seats near an exit", "waiting_seating" => "Seating while waiting",
    "accessible_restroom" => "Accessible restroom", "all_gender_restroom" => "All-gender restroom", "changing_table" => "Adult changing table",
    "assistive_listening" => "Hearing loop or headsets", "large_print" => "Large print programs", "quiet_room" => "Quiet room", "service_animals" => "Service animals welcome",
    "step_free_stage" => "Step-free to the stage", "accessible_dressing_room" => "Accessible dressing room", "backstage_restroom" => "Accessible backstage restroom", "accessible_stage_door" => "Accessible stage door"
  }.freeze

  def self.find(key) = BY_KEY[key.to_s]
  def self.label(key) = BY_KEY.fetch(key.to_s).label
end
