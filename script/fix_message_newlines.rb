# frozen_string_literal: true

# Script to fix message bodies that were stored without proper HTML formatting
#
# This script identifies messages that appear to have lost newline formatting
# and re-applies HTML paragraph/line break formatting.
#
# Run in production console after deploy:
#   DRY_RUN=1 rails runner script/fix_message_newlines.rb
#
# Once verified, run for real:
#   rails runner script/fix_message_newlines.rb
#
# CAUTION: This modifies message content. Use DRY_RUN first!

DRY_RUN = ENV["DRY_RUN"].present?

puts "=" * 60
puts DRY_RUN ? "DRY RUN - No changes will be made" : "LIVE RUN - Messages will be updated"
puts "=" * 60

# Helper to convert plain text with newlines to HTML
def format_as_html(text)
  return text if text.blank?

  # If it already has HTML block elements, skip
  return text if text.match?(/<(p|div|br)[>\s\/]/i)

  # Convert double newlines to paragraphs, single newlines to <br>
  paragraphs = text.split(/\n{2,}/)
  formatted = paragraphs.map do |para|
    content = para.gsub(/\n/, "<br>")
    "<p>#{content}</p>"
  end.join

  formatted
end

# Find messages with bodies that look like they need formatting
# These are typically system-generated messages with template content
candidates = []

Message.includes(:rich_text_body).find_each do |msg|
  next unless msg.body.present?

  html = msg.body.body&.to_html rescue nil
  next unless html.present?

  # Skip if already properly formatted with paragraphs
  next if html.match?(/<p[>\s]/i)

  # Skip short messages (likely intentionally single-line)
  plain_text = ActionText::Content.new(html).to_plain_text
  next if plain_text.length < 50

  # Check if the plain text has newlines that weren't rendered
  next unless plain_text.include?("\n")

  candidates << {
    id: msg.id,
    subject: msg.subject,
    current_html: html,
    plain_text: plain_text
  }
end

puts "\nFound #{candidates.count} messages that may need newline fixes"

if candidates.empty?
  puts "No messages need fixing!"
  exit 0
end

# Show samples
puts "\nSample messages (first 5):"
candidates.first(5).each do |c|
  puts "-" * 40
  puts "ID: #{c[:id]} - #{c[:subject]&.truncate(50)}"
  puts "Current HTML: #{c[:current_html][0..100]}..."
  puts "Has newlines: #{c[:plain_text].count("\n")} newlines in #{c[:plain_text].length} chars"
end

if DRY_RUN
  puts "\n[DRY RUN] Would update #{candidates.count} messages"
  puts "\nRun without DRY_RUN=1 to apply fixes."
else
  puts "\nUpdating #{candidates.count} messages..."

  updated_count = 0
  error_count = 0

  candidates.each do |c|
    begin
      msg = Message.find(c[:id])

      # Get the plain text and re-format it
      plain_text = msg.body.to_plain_text
      formatted_html = format_as_html(plain_text)

      # Update the body
      msg.body = formatted_html
      msg.save!

      updated_count += 1
      print "." if updated_count % 10 == 0
    rescue StandardError => e
      error_count += 1
      puts "\nError updating message #{c[:id]}: #{e.message}"
    end
  end

  puts "\n\nDone! Updated #{updated_count} messages, #{error_count} errors."
end

puts "=" * 60
