# frozen_string_literal: true

# =============================================================================
# DEMO MESSAGES SEEDING SCRIPT
# =============================================================================
#
# Creates a small set of demo messages with descriptive names showing their scenario
#
# USAGE:
#   rails demo:messages              # Create/reset demo messages
#
# REQUIREMENTS:
#   - Must have demo:seed already run (creates demo org & users)
#   - Will NOT run in production environment (safety check)
#
# =============================================================================

namespace :demo do
  desc "Seed demo messages with descriptive scenarios"
  task messages: :environment do
    if Rails.env.production?
      puts "=" * 60
      puts "ERROR: Cannot run demo:messages in production!"
      puts "=" * 60
      abort
    end

    DemoMessageSeeder.seed_all
  end
end

class DemoMessageSeeder
  DEMO_ORG_NAME = "Starlight Community Theater (Demo Organization)"

  class << self
    def seed_all
      puts "=" * 80
      puts "SEEDING DEMO MESSAGES"
      puts "=" * 80

      @org = Organization.find_by(name: DEMO_ORG_NAME)

      unless @org
        puts "\nERROR: Demo organization not found!"
        puts "Please run 'rails demo:seed' first."
        abort
      end

      puts "\nOrganization: #{@org.name}"

      ActiveRecord::Base.transaction do
        destroy_existing_messages
        gather_resources
        create_scenario_messages
        print_summary
      end

      puts "\n" + "=" * 80
      puts "COMPLETE!"
      puts "=" * 80
    end

    private

    def destroy_existing_messages
      puts "\nDestroying existing demo messages..."

      # Get all message IDs for this org
      demo_message_ids = Message.where(organization_id: @org.id).pluck(:id)

      # Delete subscriptions first (foreign key constraint)
      sub_count = MessageSubscription.where(message_id: demo_message_ids).delete_all
      puts "  Deleted #{sub_count} subscriptions"

      # Delete message recipients
      recipient_count = MessageRecipient.where(message_id: demo_message_ids).delete_all
      puts "  Deleted #{recipient_count} recipients"

      # Delete message regards
      MessageRegard.where(message_id: demo_message_ids).delete_all

      # Delete messages
      message_count = Message.where(id: demo_message_ids).delete_all
      puts "  Deleted #{message_count} messages"
    end

    def gather_resources
      puts "\nGathering resources..."

      @managers = @org.users.joins(:organization_roles)
        .where(organization_roles: { company_role: "manager" })
        .distinct.to_a
      @people = @org.people.where.not(id: @managers.map { |m| m.person&.id }.compact).to_a
      @productions = @org.productions.to_a
      @shows = Show.joins(:production).where(productions: { organization_id: @org.id }).to_a

      # Find a show with cast for messages
      @show_with_cast = @shows.find { |s| s.show_person_role_assignments.any? }

      puts "  #{@managers.count} managers"
      puts "  #{@people.count} people"
      puts "  #{@productions.count} productions"
      puts "  #{@shows.count} shows (#{@show_with_cast ? 'found show with cast' : 'no shows with cast'})"
    end

    def create_scenario_messages
      puts "\nCreating scenario messages..."

      @created = []
      manager = @managers.first
      production = @productions.first
      show = @show_with_cast || @shows.first

      # Get people with user accounts for recipients
      @people_with_users = @people.select { |p| p.user.present? }

      return puts "  No people with user accounts found!" if @people_with_users.empty?

      # 1. Direct private message (no replies)
      @created << create_direct_message(
        subject: "(Private - no replies) Welcome to the cast!",
        body: "This is a private direct message between two people.",
        sender: manager,
        recipient: @people_with_users.sample
      )

      # 2. Direct private message with replies
      msg = create_direct_message(
        subject: "(Private - 2 replies) Quick question",
        body: "Hey, I had a quick question about the schedule.",
        sender: manager,
        recipient: @people_with_users.sample
      )
      add_replies(msg, 2) if msg
      @created << msg

      # 3. Production-scoped message (visible to all managers)
      msg = create_production_message(
        subject: "(Production scope - 3 replies) Cast announcement",
        body: "Attention all cast members! Here's an important production update.",
        sender: manager,
        production: production,
        recipients: @people_with_users.sample(5)
      )
      add_replies(msg, 3) if msg
      @created << msg

      # 4. Show-scoped message (visible to production team + show cast)
      msg = create_show_message(
        subject: "(Show scope) Opening night call times",
        body: "Here are the call times for opening night. Please be on time!",
        sender: manager,
        show: show,
        recipients: @people_with_users.sample(4)
      )
      @created << msg

      # 5. Production message with images
      msg = create_production_message(
        subject: "(Production + 3 images) Set design concepts",
        body: "Here are the set design concepts I've been working on!",
        sender: manager,
        production: production,
        recipients: @people_with_users.sample(3)
      )
      attach_images(msg, 3) if msg
      @created << msg

      # 6. Show message with images and replies
      msg = create_show_message(
        subject: "(Show + 2 images + 4 replies) Pre-show photos",
        body: "Check out these photos from our pre-show prep!",
        sender: manager,
        show: show,
        recipients: @people_with_users.sample(4)
      )
      attach_images(msg, 2) if msg
      add_replies(msg, 4) if msg
      @created << msg

      # 7. Production message with many recipients
      msg = create_production_message(
        subject: "(Production + 8 recipients) Important schedule change",
        body: "We have an important schedule change to announce to everyone.",
        sender: manager,
        production: production,
        recipients: @people_with_users.sample(8)
      )
      @created << msg

      # 8. Message with 6 images (gallery test)
      msg = create_production_message(
        subject: "(6 images - gallery test) Photo dump from tech week",
        body: "Here are all the photos from tech week. What a journey!",
        sender: manager,
        production: production,
        recipients: @people_with_users.sample(3)
      )
      attach_images(msg, 6) if msg
      @created << msg

      # 9. Deep nested thread
      msg = create_production_message(
        subject: "(Deep nested - 4 levels) Character discussion",
        body: "Let's have a deep discussion about character motivations.",
        sender: manager,
        production: production,
        recipients: @people_with_users.sample(5)
      )
      add_threaded_replies(msg, 8, max_depth: 4) if msg
      @created << msg

      # 10. Single image message
      msg = create_production_message(
        subject: "(1 image) Poster design",
        body: "Here's the final poster design for the show!",
        sender: manager,
        production: production,
        recipients: @people_with_users.sample(2)
      )
      attach_images(msg, 1) if msg
      @created << msg

      puts "  Created #{@created.compact.count} scenario messages"
    end

    def create_direct_message(subject:, body:, sender:, recipient:)
      MessageService.send_direct(
        sender: sender,
        recipient_person: recipient,
        subject: subject,
        body: body,
        organization: @org
      )
    rescue => e
      puts "    Warning: Could not create direct message - #{e.message}"
      nil
    end

    def create_production_message(subject:, body:, sender:, production:, recipients:)
      MessageService.create_message(
        sender: sender,
        recipients: recipients,
        subject: subject,
        body: body,
        organization: @org,
        production: production,
        visibility: :production,
        message_type: :cast_contact
      )
    rescue => e
      puts "    Warning: Could not create production message - #{e.message}"
      nil
    end

    def create_show_message(subject:, body:, sender:, show:, recipients:)
      return nil unless show

      MessageService.create_message(
        sender: sender,
        recipients: recipients,
        subject: subject,
        body: body,
        organization: @org,
        production: show.production,
        show: show,
        visibility: :show,
        message_type: :cast_contact
      )
    rescue => e
      puts "    Warning: Could not create show message - #{e.message}"
      nil
    end

    def add_replies(parent, count)
      return unless parent

      repliers = @people_with_users.sample([ count, @people_with_users.count ].min)

      repliers.each_with_index do |person, i|
        replies = [
          "Thanks for sharing!",
          "Got it, I'll be there!",
          "Sounds good!",
          "Looking forward to it!",
          "Will do!",
          "Perfect, thanks!",
          "Confirmed!",
          "Great, see you then!",
          "This is great, thanks!",
          "Can't wait!"
        ]

        MessageService.reply(
          sender: person.user,
          parent_message: parent,
          body: replies[i % replies.length]
        )
      rescue => e
        puts "    Warning: Could not add reply - #{e.message}"
      end
    end

    def add_threaded_replies(parent, count, max_depth: 2)
      return unless parent
      return if @people_with_users.empty?

      all_messages = [ parent ]

      count.times do |i|
        reply_to = all_messages.sample
        person = @people_with_users.sample
        next unless person

        bodies = [
          "I agree with this!",
          "Great point!",
          "What about...?",
          "Following up on this...",
          "Just to add...",
          "That makes sense!",
          "Thanks for clarifying!",
          "I have a question about this.",
          "Interesting perspective!",
          "Let me think about this..."
        ]

        begin
          reply = MessageService.reply(
            sender: person.user,
            parent_message: reply_to,
            body: bodies.sample
          )

          all_messages << reply if reply
        rescue => e
          puts "    Warning: Could not add threaded reply - #{e.message}"
        end
      end
    end

    def attach_images(message, count)
      return unless message

      require "open-uri"

      count.times do |i|
        width = [ 400, 600, 800 ].sample
        height = [ 300, 400, 600 ].sample

        url = "https://picsum.photos/#{width}/#{height}"

        begin
          image_data = URI.open(url, read_timeout: 10)
          message.images.attach(
            io: image_data,
            filename: "demo_image_#{message.id}_#{i + 1}.jpg",
            content_type: "image/jpeg"
          )
        rescue => e
          puts "    Warning: Could not download placeholder image - #{e.message}"
          attach_fallback_image(message, i, width, height)
        end
      end
    rescue => e
      puts "    Warning: Could not attach images - #{e.message}"
    end

    def attach_fallback_image(message, index, width, height)
      colors = %w[f472b6 a78bfa 60a5fa 34d399 fbbf24 2dd4bf]
      color = colors[index % colors.length]

      png_data = create_minimal_png(color)

      io = StringIO.new(png_data)
      message.images.attach(
        io: io,
        filename: "demo_image_#{message.id}_#{index + 1}.png",
        content_type: "image/png"
      )
    end

    def create_minimal_png(hex_color)
      require "zlib"

      r = hex_color[0..1].to_i(16)
      g = hex_color[2..3].to_i(16)
      b = hex_color[4..5].to_i(16)

      width = 100
      height = 100

      raw_data = ""
      height.times do
        raw_data << "\x00"
        width.times do
          raw_data << [ r, g, b ].pack("CCC")
        end
      end

      compressed = Zlib::Deflate.deflate(raw_data)

      png = "\x89PNG\r\n\x1a\n"

      ihdr_data = [ width, height, 8, 2, 0, 0, 0 ].pack("NNCCCCC")
      png << png_chunk("IHDR", ihdr_data)
      png << png_chunk("IDAT", compressed)
      png << png_chunk("IEND", "")

      png
    end

    def png_chunk(type, data)
      chunk = type + data
      [ data.length ].pack("N") + chunk + [ Zlib.crc32(chunk) ].pack("N")
    end

    def print_summary
      puts "\n" + "=" * 80
      puts "SUMMARY"
      puts "=" * 80

      @created.compact.each do |msg|
        replies = msg.child_messages.count
        images = msg.images.count
        recipients = msg.recipient_count
        visibility = msg.visibility

        puts "  ✓ #{msg.subject.truncate(60)}"
        puts "    → Visibility: #{visibility}, Recipients: #{recipients}, Replies: #{replies}, Images: #{images}"
      end
    end
  end
end
