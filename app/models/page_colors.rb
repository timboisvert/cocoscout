# frozen_string_literal: true

# The colors of the public landing page and ticket pages (Tim, 2026-11-18):
# a background, a button, a heading, and a text color. The box office sets
# them for every page; a production, and then a date, can override all four
# (HasPageColors). Nothing set is the standard look, and a page with the
# standard look renders exactly as it always has.
#
# What each covers: the background is the page behind the white boxes; the
# heading and text colors are the words on that background (the boxes keep
# their own dark words, so they stay readable whatever the background); the
# button color is every button and link, and the touches of pink (inside
# the white boxes, darkened when it's too light to read on white).
class PageColors
  FIELDS = {
    background: "page_background_color",
    button: "page_button_color",
    heading: "page_heading_color",
    text: "page_text_color"
  }.freeze

  # Today's look: white, pink-500, gray-900, gray-600.
  DEFAULTS = { background: "#ffffff", button: "#ec4899", heading: "#111827", text: "#4b5563" }.freeze

  LABELS = { background: "Background", button: "Buttons", heading: "Headings", text: "Text" }.freeze

  HEX = /\A#\h{6}\z/

  attr_reader(*FIELDS.keys)

  # The colors a page shows: the date's own, else its production's, else the
  # box office's, else the standard ones.
  def self.for(profile, setup = nil, listing = nil)
    source = [ listing, setup ].compact.find(&:own_page_colors?)
    new(**(source || profile)&.page_colors_hash.to_h)
  end

  def self.normalize(value)
    hex = value.to_s.strip.downcase
    hex = "##{hex}" if hex.match?(/\A\h{6}\z/)
    hex.presence
  end

  def initialize(background: nil, button: nil, heading: nil, text: nil)
    @background = background.presence || DEFAULTS[:background]
    @button = button.presence || DEFAULTS[:button]
    @heading = heading.presence || DEFAULTS[:heading]
    @text = text.presence || DEFAULTS[:text]
  end

  def to_h
    FIELDS.keys.index_with { |key| public_send(key) }
  end

  def standard?
    to_h == DEFAULTS
  end

  # The words on a button: white on a dark one, near-black on a light one.
  def button_ink
    self.class.dark?(button) ? "#ffffff" : "#111827"
  end

  # Links and outlines inside the white boxes: the button color, or, when
  # it's too light to read on white, a darker shade of it.
  def accent
    return button if self.class.dark?(button)

    "#" + button.delete("#").scan(/../).map { |pair| format("%02x", (pair.to_i(16) * 0.45).round) }.join
  end

  # The custom properties the storefront's page-colors rules read.
  def style
    [ "--page-bg: #{background}", "--page-button: #{button}", "--page-button-ink: #{button_ink}", "--page-accent: #{accent}",
      "--page-heading: #{heading}", "--page-text: #{text}" ].join("; ")
  end

  def self.dark?(hex)
    r, g, b = hex.delete("#").scan(/../).map { |pair| pair.to_i(16) / 255.0 }
    lum = ->(c) { c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }
    (0.2126 * lum.call(r)) + (0.7152 * lum.call(g)) + (0.0722 * lum.call(b)) < 0.4
  end
end
