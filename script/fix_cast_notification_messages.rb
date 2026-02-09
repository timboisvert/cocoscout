# =============================================================================
# PRODUCTION FIX: Update incorrectly-sent cast notification messages
# =============================================================================
#
# Problem: The send_consolidated_cast_email method in casting_controller.rb
# was using a hardcoded body instead of the user's ContentTemplate. Messages
# sent via "Finalize and Notify" had the wrong content.
#
# This script finds cast notification messages that contain the old hardcoded
# text and replaces their body with the correctly-rendered template content.
#
# Run in rails console: load 'script/fix_cast_notification_messages.rb'
# =============================================================================

puts "=" * 70
puts "CAST NOTIFICATION MESSAGE FIX"
puts "=" * 70
puts

# ── Step 1: Find messages with cast notification body that needs fixing ──
# The broken send_consolidated_cast_email had two failure modes:
#
# A) Single-show path: Did .gsub("[Name]", ...) but template uses {{variable}},
#    so gsubs matched nothing. The raw template with literal {{role_name}},
#    {{shows_list}}, etc. was sent to recipients.
#
# B) Multi-show path: Used a completely hardcoded <<~BODY that contained
#    "You have been cast as [role] in the following shows/events for [production]"
#
# C) Removed notification: "There has been a change to the casting for"

# Pattern A: Raw template placeholders sent as literal text
uninterpolated_patterns = [
  "%{{role_name}}%",
  "%{{shows_list}}%",
  "%{{production_name}}%"
]

# Pattern B & C: Hardcoded body text
hardcoded_patterns = [
  "%You have been cast as%in the following shows/events for%",
  "%There has been a change to the casting for%"
]

# Pattern D: Old template content (pre-rendered with old template before user updated it)
# The current template does NOT have "Congratulations!" — if a message has it,
# it was rendered from the old version of the template.
old_template_patterns = [
  "%Congratulations! You have been cast%"
]

all_patterns = uninterpolated_patterns + hardcoded_patterns + old_template_patterns

affected_rich_texts = ActionText::RichText.where(record_type: "Message", name: "body")
  .where(
    all_patterns.map { "body LIKE ?" }.join(" OR "),
    *all_patterns
  )

puts "Found #{affected_rich_texts.count} messages with broken cast notification body"
puts

affected_rich_texts.each do |rt|
  msg = Message.find_by(id: rt.record_id)
  next unless msg
  recipients = msg.message_recipients.includes(:recipient).map { |mr| mr.recipient&.name }.compact.join(", ")
  puts "  Message ##{msg.id} (#{msg.created_at.in_time_zone.strftime('%b %-d %H:%M')}) production=#{msg.production_id}"
  puts "    To: #{recipients.presence || 'N/A'}"
  puts "    Subject: #{msg.subject}"
  puts "    Body preview: #{rt.body.to_s.truncate(120)}"
  puts
end

# ── Step 2: Also check ShowCastNotification records for the wrong body ──
puts "-" * 70
puts "Checking ShowCastNotification records with hardcoded body..."

affected_notifications = ShowCastNotification.where(
  all_patterns.map { "email_body LIKE ?" }.join(" OR "),
  *all_patterns
)

puts "Found #{affected_notifications.count} ShowCastNotification records with hardcoded body"

affected_notifications.each do |scn|
  puts "  SCN ##{scn.id} — Show ##{scn.show_id}, #{scn.assignable_type} ##{scn.assignable_id}, role ##{scn.role_id}"
  puts "    Type: #{scn.notification_type}, Notified: #{scn.notified_at.in_time_zone.strftime('%b %-d %H:%M')}"
  puts "    Body preview: #{scn.email_body.to_s.truncate(120)}"
  puts
end

puts "=" * 70
puts
puts "IMPORTANT: Review the messages above carefully."
puts "To fix them, you need to know what the CORRECT content should be."
puts "The correct content comes from your 'cast_notification' ContentTemplate."
puts
puts "Current template content:"
template = ContentTemplate.active.find_by(key: "cast_notification")
if template
  puts "  Subject: #{template.subject}"
  puts "  Body: #{template.body.truncate(200)}"
else
  puts "  ⚠️  No active 'cast_notification' template found!"
end
puts

puts "=" * 70
print "Do you want to re-render and fix the affected messages? (yes/no): "
confirmation = gets&.strip

if confirmation == "yes"
  fixed_messages = 0
  fixed_notifications = 0

  ActiveRecord::Base.transaction do
    # Fix Messages
    affected_rich_texts.each do |rt|
      msg = Message.find_by(id: rt.record_id)
      next unless msg

      # Find the production from the message
      production = msg.production
      next unless production

      # Try to find the matching ShowCastNotification records for better data
      # These link to the specific shows, roles, and people notified
      scns = ShowCastNotification.where(notification_type: :cast)
        .where("notified_at BETWEEN ? AND ?", msg.created_at - 1.minute, msg.created_at + 1.minute)
        .joins(:show).where(shows: { production_id: production.id })

      if scns.any?
        shows = scns.includes(:show).map(&:show).uniq.sort_by(&:date_and_time)
        role_names = scns.includes(:role).map { |s| s.role.name }.uniq
        show_dates = shows.map { |s| s.date_and_time.strftime("%B %-d") }.uniq.join(", ")
        shows_list = shows.map { |s| "<li>#{s.date_and_time.strftime('%A, %B %-d at %-l:%M %p')}: #{s.display_name}</li>" }.join
      else
        show = msg.show || production.shows.order(:date_and_time).first
        next unless show
        shows = [ show ]
        role_names = [ "Cast Member" ]
        show_dates = show.date_and_time.strftime("%B %-d")
        shows_list = "<li>#{show.date_and_time.strftime('%A, %B %-d at %-l:%M %p')}: #{show.display_name}</li>"
      end

      variables = {
        production_name: production.name,
        show_dates: show_dates,
        shows_list: shows_list,
        role_name: role_names.join(", "),
        role_names: role_names.join(", ")
      }

      new_body = ContentTemplateService.render_body("cast_notification", variables)
      new_subject = ContentTemplateService.render_subject("cast_notification", variables)

      # Update the ActionText body
      rt.update!(body: new_body)

      # Update the message subject if it was also hardcoded
      msg.update_column(:subject, new_subject) if msg.subject != new_subject

      puts "✅ Fixed Message ##{msg.id}"
      fixed_messages += 1
    end

    # Fix ShowCastNotification records
    affected_notifications.each do |scn|
      show = scn.show
      production = show.production

      variables = {
        production_name: production.name,
        show_dates: show.date_and_time.strftime("%B %-d"),
        shows_list: "<li>#{show.date_and_time.strftime('%A, %B %-d at %-l:%M %p')}: #{show.display_name}</li>",
        role_name: scn.role.name,
        role_names: scn.role.name
      }

      new_body = ContentTemplateService.render_body("cast_notification", variables)
      scn.update_column(:email_body, new_body)

      puts "✅ Fixed ShowCastNotification ##{scn.id}"
      fixed_notifications += 1
    end
  end

  puts
  puts "🎉 Fixed #{fixed_messages} messages and #{fixed_notifications} notification records!"
else
  puts "❌ No changes made."
end
