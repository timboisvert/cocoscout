# frozen_string_literal: true

# Development-only service for creating test users and simulating activity.
# All created users are marked with a special email suffix for easy cleanup.
#
# Usage via rake tasks:
#   bin/rails dev:create_users[50]           - Create 50 test users
#   bin/rails dev:submit_audition_requests   - Have test users submit audition requests
#   bin/rails dev:submit_signups             - Have test users sign up for open forms
#   bin/rails dev:delete_signups             - Delete all sign-up forms
#   bin/rails dev:delete_users               - Delete all test users
#
class DevSeedService
  TEST_EMAIL_SUFFIX = "@testuser.cocoscout.dev"

  class << self
    def create_users(count = 50)
      raise "This can only be run in development!" unless Rails.env.development?

      require "faker"
      require "open-uri"

      # Words that will be rejected by the User model's email validation
      banned_words = %w[bin cat etc passwd wget curl bash sh exec eval]

      created = 0
      attempts = 0
      max_attempts = count * 3 # Allow some retries for validation failures

      while created < count && attempts < max_attempts
        attempts += 1
        first_name = Faker::Name.first_name
        last_name = Faker::Name.last_name

        # Skip names that contain banned words
        full_name_lower = "#{first_name}#{last_name}".downcase
        next if banned_words.any? { |w| full_name_lower.include?(w) }

        full_name = "#{first_name} #{last_name}"
        email = "#{first_name.downcase}.#{last_name.downcase}.#{SecureRandom.hex(4)}#{TEST_EMAIL_SUFFIX}"

        # Skip if email already exists
        next if User.exists?(email_address: email)

        begin
          user = User.create!(
            email_address: email,
            password: "TestPass123!"
          )

          person = Person.create!(
            name: full_name,
            email: email,
            user: user
          )

          # Attach a random headshot from a placeholder service
          attach_random_headshot(person)

          created += 1
          print "." if (created % 10).zero?
        rescue ActiveRecord::RecordInvalid => e
          # Skip validation failures and try again
          puts "Skipping #{email}: #{e.message}"
        end
      end

      puts "\nCreated #{created} test users"
      created
    end

    def submit_audition_requests(count_per_cycle: 10)
      raise "This can only be run in development!" unless Rails.env.development?

      # Find open audition cycles
      open_cycles = AuditionCycle.where(opens_at: ..Time.current)
                                 .where("closes_at IS NULL OR closes_at > ?", Time.current)
                                 .where(form_reviewed: true)

      if open_cycles.empty?
        puts "No open audition cycles found."
        return 0
      end

      # Ensure we have enough test users
      test_users = User.where("email_address LIKE ?", "%#{TEST_EMAIL_SUFFIX}").to_a
      if test_users.count < count_per_cycle
        puts "Creating #{count_per_cycle - test_users.count} more test users..."
        create_users(count_per_cycle - test_users.count)
        test_users = User.where("email_address LIKE ?", "%#{TEST_EMAIL_SUFFIX}").to_a
      end

      submitted = 0
      open_cycles.each do |cycle|
        # Get test users who haven't already submitted to this cycle
        eligible_users = test_users.select do |user|
          user.person && !cycle.audition_requests.exists?(requestable: user.person)
        end

        users_to_submit = eligible_users.sample(count_per_cycle)

        users_to_submit.each do |user|
          person = user.person

          begin
            AuditionRequest.create!(
              audition_cycle: cycle,
              requestable: person
            )
            submitted += 1
          rescue => e
            puts "Error submitting for #{person.name}: #{e.message}"
          end
        end
      end

      puts "Submitted #{submitted} audition requests across #{open_cycles.count} cycles"
      submitted
    end

    def submit_signups(count_per_form: 10)
      raise "This can only be run in development!" unless Rails.env.development?

      # Find active sign-up forms with open instances
      active_forms = SignUpForm.where(active: true)

      if active_forms.empty?
        puts "No active sign-up forms found."
        return 0
      end

      # Ensure we have enough test users
      test_users = User.where("email_address LIKE ?", "%#{TEST_EMAIL_SUFFIX}").to_a
      if test_users.count < count_per_form
        puts "Creating #{count_per_form - test_users.count} more test users..."
        create_users(count_per_form - test_users.count)
        test_users = User.where("email_address LIKE ?", "%#{TEST_EMAIL_SUFFIX}").to_a
      end

      registered = 0
      active_forms.each do |form|
        # Get the current instance
        instance = if form.repeated?
          form.sign_up_form_instances
              .joins(:show)
              .where("shows.date_and_time > ?", Time.current)
              .order("shows.date_and_time ASC")
              .first
        else
          form.sign_up_form_instances.first
        end

        next unless instance

        # Shuffle slots to spread registrations throughout the list
        available_slots = instance.sign_up_slots.where(is_held: false).to_a.shuffle
        next if available_slots.empty?

        # Get test users who can still register (haven't reached form's registrations_per_person limit)
        eligible_users = test_users.select do |user|
          next false unless user.person

          existing_count = instance.sign_up_registrations
                                   .joins(:sign_up_slot)
                                   .where(person: user.person)
                                   .where.not(status: "cancelled")
                                   .count

          max_allowed = form.registrations_per_person || 1
          existing_count < max_allowed
        end

        # Shuffle users and spread them across slots
        users_to_register = eligible_users.shuffle.take(count_per_form)

        # Handle admin_assigns mode differently - queue people instead of assigning slots
        if form.admin_assigns?
          users_to_register.each do |user|
            person = user.person

            # Check if person is already queued
            next if SignUpRegistration.where(sign_up_form_instance_id: instance.id, person: person).where.not(status: "cancelled").exists?

            begin
              # Calculate next queue position
              queue_position = (instance.queued_registrations.maximum(:position) || 0) + 1

              SignUpRegistration.create!(
                sign_up_form_instance_id: instance.id,
                person: person,
                status: "queued",
                position: queue_position,
                registered_at: Time.current
              )
              registered += 1
            rescue => e
              puts "Error queuing #{person.name}: #{e.message}"
            end
          end
        else
          # Distribute users across slots round-robin style
          slot_index = 0
          users_to_register.each do |user|
            person = user.person

            # Find the next available slot starting from slot_index
            attempts = 0
            while attempts < available_slots.length
              slot = available_slots[slot_index % available_slots.length]
              slot_index += 1
              attempts += 1

              # Check if slot has capacity and person isn't already in it
              next if slot.full?
              next if slot.sign_up_registrations.where(person: person).where.not(status: "cancelled").exists?

              begin
                slot.register!(person: person)
                registered += 1
                break
              rescue => e
                puts "Error registering #{person.name}: #{e.message}"
              end
            end
          end
        end
      end

      puts "Created #{registered} sign-up registrations across #{active_forms.count} forms"
      registered
    end

    def delete_all_signups
      raise "This can only be run in development!" unless Rails.env.development?

      count = SignUpForm.count
      SignUpRegistration.delete_all
      SignUpSlot.delete_all
      SignUpFormInstance.delete_all
      SignUpFormShow.delete_all
      SignUpFormHoldout.delete_all
      SignUpForm.delete_all

      puts "Deleted #{count} sign-up forms and all related records"
      count
    end

    def delete_test_users
      raise "This can only be run in development!" unless Rails.env.development?

      test_users = User.where("email_address LIKE ?", "%#{TEST_EMAIL_SUFFIX}")
      count = test_users.count

      test_users.find_each do |user|
        # Delete associated person and their data
        if user.person
          # Clean up registrations, audition requests, etc.
          AuditionRequest.where(requestable: user.person).destroy_all
          SignUpRegistration.where(person: user.person).destroy_all
          user.person.destroy
        end
        user.destroy
      end

      puts "Deleted #{count} test users and their data"
      count
    end

    def stats
      raise "This can only be run in development!" unless Rails.env.development?

      test_users = User.where("email_address LIKE ?", "%#{TEST_EMAIL_SUFFIX}")
      test_people = Person.where("email LIKE ?", "%#{TEST_EMAIL_SUFFIX}")

      open_cycles = AuditionCycle.where(opens_at: ..Time.current)
                                 .where("closes_at IS NULL OR closes_at > ?", Time.current)
                                 .where(form_reviewed: true)

      {
        test_users: test_users.count,
        test_people: test_people.count,
        test_audition_requests: AuditionRequest.joins("INNER JOIN people ON people.id = audition_requests.requestable_id AND audition_requests.requestable_type = 'Person'")
                                               .where("people.email LIKE ?", "%#{TEST_EMAIL_SUFFIX}").count,
        test_signups: SignUpRegistration.joins(:person).where("people.email LIKE ?", "%#{TEST_EMAIL_SUFFIX}").count,
        total_signup_forms: SignUpForm.count,
        open_audition_cycles: open_cycles.count,
        active_signup_forms: SignUpForm.where(active: true).count
      }
    end

    private

    def attach_random_headshot(person)
      # Use pravatar.cc for random avatars (or ui-faces, thispersondoesnotexist alternatives)
      # We'll use pravatar.cc which gives consistent avatars based on a seed
      avatar_seed = SecureRandom.hex(8)
      avatar_url = "https://i.pravatar.cc/300?u=#{avatar_seed}"

      begin
        downloaded_image = URI.open(avatar_url)

        # Create a ProfileHeadshot record and attach the image to it
        headshot = person.profile_headshots.create!(is_primary: true)
        headshot.image.attach(
          io: downloaded_image,
          filename: "headshot_#{avatar_seed}.jpg",
          content_type: "image/jpeg"
        )
      rescue => e
        puts "Failed to attach headshot for #{person.name}: #{e.message}"
      end
    end
  end
end
