namespace :seed do
  desc "Generate 60 test people with audition requests for production 14"
  task test_production: :environment do
    require "open-uri"

    production = Production.find(14)
    production_company = production.production_company

    puts "Seeding test data for production: #{production.name} (ID: #{production.id})"

    # Clean up existing audition sessions for this production
    puts "\nCleaning up existing audition sessions..."
    existing_sessions = AuditionSession.where(production: production)
    existing_sessions.each do |session|
      session.auditions.destroy_all
      session.destroy
    end
    puts "Deleted #{existing_sessions.count} existing audition sessions"

    # Create or find call to audition
    call_to_audition = production.call_to_audition
    unless call_to_audition
      call_to_audition = CallToAudition.create!(
        production: production,
        audition_type: :in_person,
        opens_at: 1.week.ago,
        closes_at: 1.week.from_now,
        form_reviewed: true,
        include_availability_section: true,
        token: SecureRandom.hex(16)
      )
      puts "Created new call to audition"
    end

    # Get existing questions or create sample questions if none exist
    questions = call_to_audition.questions.to_a
    if questions.empty?
      puts "Creating sample questions..."
      questions << call_to_audition.questions.create!(
        text: "Why do you want to be in this production?",
        question_type: "text"
      )
      questions << call_to_audition.questions.create!(
        text: "Do you have any conflicts with rehearsal dates?",
        question_type: "yesno"
      )
      puts "Created #{questions.count} sample questions"
    else
      puts "Found #{questions.count} existing questions"
    end

    # Create audition sessions - 3 sessions, 1 week from now, 1 hour apart, max 8 people each
    location = production.production_company.locations.first || Location.create!(
      production_company: production_company,
      name: "Main Studio",
      address1: "123 Main St",
      city: "Los Angeles",
      state: "CA",
      postal_code: "90001"
    )

    puts "\nCreating fresh audition sessions..."
    sessions = []
    base_time = 1.week.from_now.change(hour: 14, min: 0) # 2 PM, one week from now
    3.times do |i|
      session = AuditionSession.create!(
        production: production,
        call_to_audition: call_to_audition,
        location: location,
        start_at: base_time + (i * 1).hours,
        end_at: base_time + (i * 1).hours + 50.minutes,
        maximum_auditionees: 8
      )
      sessions << session
      puts "Created audition session #{i + 1}: #{session.start_at.strftime('%A %B %d at %l:%M %p')} (max 8 people)"
    end

    # Get all shows for this production to create availability
    all_shows = production.shows.order(:date_and_time)
    puts "Found #{all_shows.count} shows for availability creation"

    # Get availability events if they exist
    availability_events = []
    if call_to_audition.include_availability_section && call_to_audition.availability_event_types.present?
      begin
        availability_event_ids = JSON.parse(call_to_audition.availability_event_types)
        availability_events = production.shows.where(id: availability_event_ids)
        puts "Found #{availability_events.count} events configured in call to audition"
      rescue JSON::ParserError
        puts "No valid availability events configured"
      end
    end

    # Generate 60 test people with realistic names and "TEST" suffix for easy identification
    first_names = [
      "Emma", "Liam", "Olivia", "Noah", "Ava", "Ethan", "Sophia", "Mason", "Isabella", "William",
      "Mia", "James", "Charlotte", "Benjamin", "Amelia", "Lucas", "Harper", "Henry", "Evelyn", "Alexander",
      "Abigail", "Michael", "Emily", "Daniel", "Elizabeth", "Matthew", "Sofia", "Jackson", "Avery", "Sebastian",
      "Ella", "Jack", "Scarlett", "Aiden", "Grace", "Owen", "Chloe", "Samuel", "Victoria", "David",
      "Riley", "Joseph", "Aria", "Carter", "Lily", "Wyatt", "Aubrey", "John", "Zoey", "Dylan",
      "Penelope", "Luke", "Lillian", "Gabriel", "Nora", "Anthony", "Hannah", "Isaac", "Mila", "Grayson"
    ]

    last_names = [
      "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez",
      "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson", "Thomas", "Taylor", "Moore", "Jackson", "Martin",
      "Lee", "Perez", "Thompson", "White", "Harris", "Sanchez", "Clark", "Ramirez", "Lewis", "Robinson",
      "Walker", "Young", "Allen", "King", "Wright", "Scott", "Torres", "Nguyen", "Hill", "Flores",
      "Green", "Adams", "Nelson", "Baker", "Hall", "Rivera", "Campbell", "Mitchell", "Carter", "Roberts",
      "Gomez", "Phillips", "Evans", "Turner", "Diaz", "Parker", "Cruz", "Edwards", "Collins", "Reyes"
    ]

    people = []
    60.times do |i|
      first_name = first_names[i % first_names.length]
      last_name = last_names[i % last_names.length]
      full_name = "#{first_name} #{last_name} TEST"

      person = Person.create!(
        name: full_name,
        email: "test_#{first_name.downcase}_#{last_name.downcase}_#{Time.current.to_i}@example.com",
        pronouns: [ "he/him", "she/her", "they/them" ].sample
      )

      # Associate person with the production company
      production_company.people << person unless production_company.people.include?(person)

      # Create headshot for the person
      # Use images 15-70 to avoid children (images 1-14 tend to be younger)
      begin
        avatar_number = ((i + 15) % 56) + 15  # Ensures range 15-70
        avatar_url = "https://i.pravatar.cc/400?img=#{avatar_number}"
        downloaded_image = URI.open(avatar_url)
        person.headshot.attach(
          io: downloaded_image,
          filename: "#{person.name.parameterize}_headshot.jpg",
          content_type: "image/jpeg"
        )
      rescue => e
        puts "  Warning: Failed to create headshot for #{person.name}: #{e.message}"
      end

      # Create resume as a JPEG image
      begin
        temp_file = Tempfile.new([ "resume", ".jpg" ])
        temp_path = temp_file.path
        temp_file.close  # Close it so ImageMagick can write to it

        # Simplified ImageMagick command
        escaped_name = person.name.gsub("'", "\\\\'")
        escaped_email = person.email.gsub("'", "\\\\'")

        cmd = "convert -size 800x1100 xc:white " \
              "-gravity northwest " \
              "-pointsize 24 -font Helvetica-Bold -annotate +50+50 '#{escaped_name}' " \
              "-pointsize 12 -font Helvetica -annotate +50+90 '#{escaped_email}' " \
              "-pointsize 14 -font Helvetica-Bold -annotate +50+140 'PROFESSIONAL SUMMARY' " \
              "-pointsize 11 -font Helvetica -annotate +50+170 'Talented performer with extensive experience' " \
              "-pointsize 14 -font Helvetica-Bold -annotate +50+240 'SKILLS' " \
              "-pointsize 11 -font Helvetica -annotate +50+270 'Acting, Singing, Dancing, Improvisation' " \
              "#{temp_path}"

        result = system(cmd)

        if result && File.exist?(temp_path) && File.size(temp_path) > 0
          # Attach the resume
          File.open(temp_path, "rb") do |file|
            person.resume.attach(
              io: file,
              filename: "#{person.name.parameterize}_resume.jpg",
              content_type: "image/jpeg"
            )
          end

          puts "  ✓ Resume created" if i % 10 == 0
        else
          puts "  ✗ Resume creation failed for #{person.name}"
        end

        # Clean up
        File.unlink(temp_path) if File.exist?(temp_path)
      rescue => e
        puts "  ✗ Resume error for #{person.name}: #{e.message}"
      end

      people << person
      puts "Created person #{i + 1}: #{person.name}"
    end

    # Create audition requests for all 60 people with answers
    puts "\nCreating audition requests with answers for all 60 people..."
    audition_requests = []
    people.each_with_index do |person, index|
      audition_request = AuditionRequest.create!(
        call_to_audition: call_to_audition,
        person: person,
        status: :unreviewed
      )

      # Create answers for each question
      questions.each do |question|
        answer_value = case question.question_type
        when "text"
          sample_texts = [
            "I'm passionate about theater and would love to be part of this production.",
            "This role aligns perfectly with my experience and interests.",
            "I've always wanted to work with this company and this production looks amazing.",
            "I'm excited about the creative opportunities this production offers."
          ]
          sample_texts[index % sample_texts.length]
        when "yesno"
          [ "yes", "no" ].sample
        when "multiple-single", "multiple-multiple"
          # For multiple choice, we'd need the options - skip for now
          nil
        else
          "Sample answer"
        end

        if answer_value
          Answer.create!(
            audition_request: audition_request,
            question: question,
            value: answer_value
          )
        end
      end

      # Create availability responses for ALL shows in the production
      if all_shows.any?
        all_shows.each do |show|
          # Randomly mark as available or unavailable (skip maybe to keep it simple)
          status = [ :available, :unavailable ].sample
          ShowAvailability.create!(
            person: person,
            show: show,
            status: status
          )
        end
        puts "  ✓ Created availability for #{all_shows.count} shows for #{person.name}" if index % 10 == 0
      else
        puts "  ✗ No shows found to create availability for!"
      end

      audition_requests << audition_request
    end
    puts "Created #{audition_requests.count} audition requests with answers"

    total_availability = ShowAvailability.where(person_id: people.map(&:id)).count
    puts "Created #{total_availability} total availability records (#{all_shows.count} shows × #{people.count} people)"

    # Randomly distribute statuses across all requests
    # 24 accepted (for 3 sessions × 8 people), 36 undecided/passed
    puts "\nRandomly distributing statuses..."
    statuses = ([ :undecided ] * 18) + ([ :accepted ] * 24) + ([ :passed ] * 18)
    statuses.shuffle!

    accepted_requests = []
    undecided_count = 0
    passed_count = 0

    audition_requests.each_with_index do |request, index|
      status = statuses[index]
      request.update(status: status)

      case status
      when :accepted
        accepted_requests << request
      when :undecided
        undecided_count += 1
      when :passed
        passed_count += 1
      end
    end

    puts "Status distribution:"
    puts "  - Undecided: #{undecided_count}"
    puts "  - Accepted: #{accepted_requests.count}"
    puts "  - Passed: #{passed_count}"

    # Schedule auditions for the accepted people
    puts "\nScheduling auditions for accepted auditionees..."
    accepted_requests.each_with_index do |request, index|
      session = sessions[index % sessions.length]
      _audition = Audition.create!(
        person: request.person,
        audition_request: request,
        audition_session: session
      )
      puts "Scheduled audition for #{request.person.name} in session #{session.id}"
    end

    puts "\n✓ Test data seeding complete!"
    puts "\nSummary:"
    puts "- Production: #{production.name} (ID: 14)"
    puts "- Test people created: 60 (all with TEST suffix)"
    puts "- Headshots: Created for all 60 people (from pravatar.cc)"
    puts "- Resumes: Created for all 60 people (JPEG images)"
    puts "- Call to audition: #{call_to_audition.id}"
    puts "- Questions: #{questions.count}"
    puts "- Audition sessions created: #{sessions.count} (1 week from now, 1 hour apart, max 8 people each)"
    puts "- Audition requests: 60 total (all with answers)"
    puts "- Shows in production: #{all_shows.count}"
    puts "- Availability records: #{all_shows.count} shows × 60 people = #{all_shows.count * 60} total"
    puts "  - Undecided (18): No auditions scheduled"
    puts "  - Accepted (24): Auditions scheduled across 3 sessions"
    puts "  - Passed/Rejected (18): No auditions scheduled"
    puts "\nTo delete all test data, run:"
    puts "  rails seed:delete_test_people"
    puts "\nTest data pages:"
    puts "  - Review: http://localhost:3000/manage/productions/14/auditions/review"
    puts "  - Run Auditions: http://localhost:3000/manage/productions/14/auditions/run"
    puts "  - Casting: http://localhost:3000/manage/productions/14/auditions/casting"
  end
end
