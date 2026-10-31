# frozen_string_literal: true

# Content notes a guest should know before they come (accessibility plan §2):
# on a production (every date) and on a show (a date can add more).
module ContentNotes
  KEYS = %w[strobe haze loud nudity participation gunshots].freeze
  LABELS = { "strobe" => "Strobe or flashing lights", "haze" => "Haze or fog", "loud" => "Loud sounds", "nudity" => "Nudity",
             "participation" => "Audience participation", "gunshots" => "Gunshots or sudden bangs" }.freeze

  def self.clean(keys) = Array(keys).map(&:to_s).select { |k| KEYS.include?(k) }.uniq
  def self.label(key) = LABELS.fetch(key)

  # Mixed into Production and Show: the keys as labels plus the free text.
  module Owner
    def content_note_keys=(keys)
      super(ContentNotes.clean(keys))
    end

    def content_note_words
      Array(content_note_keys).map { |k| ContentNotes.label(k) } + [ content_note_text.presence ].compact
    end
  end
end
